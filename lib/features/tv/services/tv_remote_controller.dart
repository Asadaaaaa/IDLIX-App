import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_domain_lock/features/tv/services/tv_spatial_navigation_script.dart';

class TvRemoteController {
  final WebViewController Function() getController;
  final VoidCallback onToggleMenu;
  final VoidCallback onBack;
  final VoidCallback onMediaPlayPause;
  final VoidCallback onMediaForward;
  final VoidCallback onMediaRewind;

  /// Spatial navigation script fallback (kept for compatibility)
  static String getSpatialNavInjectionScript() => TvSpatialNavigationScript.script;

  // Koordinat kursor virtual (default di tengah layar)
  final ValueNotifier<Offset> cursorPositionNotifier =
      ValueNotifier<Offset>(const Offset(960, 540));

  // Status kursor virtual (aktif secara default untuk TV)
  final ValueNotifier<bool> isCursorVisibleNotifier =
      ValueNotifier<bool>(true);

  // Efek klik animasi
  final ValueNotifier<bool> isClickingNotifier = ValueNotifier<bool>(false);

  // Tingkat zoom web (TV scaling)
  final ValueNotifier<double> textScaleNotifier = ValueNotifier<double>(1.25);

  Size screenSize = const Size(1920, 1080);
  Timer? _continuousMoveTimer;
  LogicalKeyboardKey? _currentHeldKey;
  int _heldSteps = 0;

  bool _initialized = false;

  TvRemoteController({
    required this.getController,
    required this.onToggleMenu,
    required this.onBack,
    required this.onMediaPlayPause,
    required this.onMediaForward,
    required this.onMediaRewind,
  });

  void init() {
    if (!_initialized) {
      HardwareKeyboard.instance.addHandler(_handleKeyEvent);
      _initialized = true;
    }
  }

  void dispose() {
    if (_initialized) {
      HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
      _initialized = false;
    }
    _continuousMoveTimer?.cancel();
  }

  void updateScreenSize(Size size) {
    if (size.width > 0 && size.height > 0) {
      screenSize = size;
      if (cursorPositionNotifier.value == const Offset(960, 540) ||
          cursorPositionNotifier.value == const Offset(300, 300)) {
        cursorPositionNotifier.value = Offset(size.width / 2, size.height / 2);
      }
    }
  }

  /// Menggeser posisi kursor berdasarkan delta (dx, dy) - digunakan untuk Trackpad HP
  void moveCursorBy(double dx, double dy) {
    if (!isCursorVisibleNotifier.value) {
      isCursorVisibleNotifier.value = true;
    }

    final current = cursorPositionNotifier.value;
    double newX = (current.dx + dx).clamp(10.0, screenSize.width - 10.0);
    double newY = (current.dy + dy).clamp(10.0, screenSize.height - 10.0);

    cursorPositionNotifier.value = Offset(newX, newY);

    // Auto-scroll jika trackpad mengarahkan kursor ke tepi atas / bawah layar TV
    if (newY <= 40 && dy < 0) {
      scrollWeb(0, -120);
    } else if (newY >= screenSize.height - 40 && dy > 0) {
      scrollWeb(0, 120);
    }
  }

  bool _handleKeyEvent(KeyEvent event) {
    final key = event.logicalKey;

    // 1. Menu Button pada Remote TV
    if (key == LogicalKeyboardKey.contextMenu ||
        key == LogicalKeyboardKey.mediaTopMenu ||
        key == LogicalKeyboardKey.tvContentsMenu ||
        event.physicalKey == PhysicalKeyboardKey.contextMenu) {
      if (event is KeyDownEvent) {
        onToggleMenu();
        return true;
      }
      return false;
    }

    // 2. Tombol Media (Play / Pause / Rewind / FastForward)
    if (key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause) {
      if (event is KeyDownEvent) {
        onMediaPlayPause();
        return true;
      }
      return false;
    }
    if (key == LogicalKeyboardKey.mediaFastForward) {
      if (event is KeyDownEvent) {
        onMediaForward();
        return true;
      }
      return false;
    }
    if (key == LogicalKeyboardKey.mediaRewind) {
      if (event is KeyDownEvent) {
        onMediaRewind();
        return true;
      }
      return false;
    }

    // 3. Tombol Back
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      if (event is KeyDownEvent) {
        onBack();
        return true;
      }
      return false;
    }

    // 4. Tombol OK / Select / Center -> Klik kursor virtual pada layar TV
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA) {
      if (event is KeyDownEvent) {
        performClick();
        return true;
      }
      return false;
    }

    // 5. Tombol Page Up / Page Down untuk Scroll Cepat
    if (key == LogicalKeyboardKey.pageUp || key == LogicalKeyboardKey.channelUp) {
      if (event is KeyDownEvent) {
        scrollWeb(0, -320);
        return true;
      }
      return false;
    }
    if (key == LogicalKeyboardKey.pageDown || key == LogicalKeyboardKey.channelDown) {
      if (event is KeyDownEvent) {
        scrollWeb(0, 320);
        return true;
      }
      return false;
    }

    // 6. Tombol D-Pad Navigasi (Arrow Up, Down, Left, Right) -> Gerakkan Kursor Virtual
    final isArrow = key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;

    if (isArrow) {
      if (event is KeyDownEvent) {
        _currentHeldKey = key;
        _heldSteps = 0;
        _moveCursorByDpad(key);

        // Akselerasi pergerakan saat tombol ditahan
        _continuousMoveTimer?.cancel();
        _continuousMoveTimer = Timer.periodic(
          const Duration(milliseconds: 50),
          (_) {
            _heldSteps++;
            if (_currentHeldKey != null) {
              _moveCursorByDpad(_currentHeldKey!);
            }
          },
        );
        return true;
      } else if (event is KeyUpEvent) {
        if (_currentHeldKey == key) {
          _continuousMoveTimer?.cancel();
          _continuousMoveTimer = null;
          _currentHeldKey = null;
          _heldSteps = 0;
        }
        return true;
      }
    }

    return false;
  }

  void _moveCursorByDpad(LogicalKeyboardKey key) {
    if (!isCursorVisibleNotifier.value) {
      isCursorVisibleNotifier.value = true;
    }

    // Kecepatan akselerasi bertahap:
    double speed = 16.0;
    if (_heldSteps > 15) {
      speed = 46.0;
    } else if (_heldSteps > 6) {
      speed = 28.0;
    }

    double dx = 0;
    double dy = 0;

    if (key == LogicalKeyboardKey.arrowLeft) dx = -speed;
    if (key == LogicalKeyboardKey.arrowRight) dx = speed;
    if (key == LogicalKeyboardKey.arrowUp) dy = -speed;
    if (key == LogicalKeyboardKey.arrowDown) dy = speed;

    moveCursorBy(dx, dy);
  }

  /// Melakukan simulasi klik kursor pada elemen di koordinat kursor virtual TV
  void performClick() {
    isClickingNotifier.value = true;
    Timer(const Duration(milliseconds: 200), () {
      isClickingNotifier.value = false;
    });

    final pos = cursorPositionNotifier.value;
    final jsCode = '''
      (function(x, y) {
        var el = document.elementFromPoint(x, y);
        if (el) {
          if (el.focus) {
            try { el.focus(); } catch(_) {}
          }

          var down = new MouseEvent('mousedown', {
            bubbles: true,
            cancelable: true,
            view: window,
            clientX: x,
            clientY: y
          });
          var up = new MouseEvent('mouseup', {
            bubbles: true,
            cancelable: true,
            view: window,
            clientX: x,
            clientY: y
          });
          var click = new MouseEvent('click', {
            bubbles: true,
            cancelable: true,
            view: window,
            clientX: x,
            clientY: y
          });

          el.dispatchEvent(down);
          el.dispatchEvent(up);
          el.dispatchEvent(click);

          if (el.tagName === 'A' || el.tagName === 'BUTTON' || el.tagName === 'INPUT') {
            try { el.click(); } catch(_) {}
          } else {
            var parent = el.closest('a, button, [role="button"], .play-btn, .btn-play');
            if (parent && typeof parent.click === 'function') {
              try { parent.click(); } catch(_) {}
            }
          }
        }
      })(${pos.dx.toInt()}, ${pos.dy.toInt()});
    ''';

    try {
      getController().runJavaScript(jsCode).catchError((_) {});
    } catch (_) {}
  }

  void scrollWeb(int x, int y) {
    try {
      getController().scrollBy(x, y);
    } catch (_) {
      try {
        getController().runJavaScript('window.scrollBy({ top: $y, left: $x, behavior: "smooth" });').catchError((_) {});
      } catch (_) {}
    }
  }

  void setZoom(double scale) {
    textScaleNotifier.value = scale;
    final js = "document.body.style.zoom = '$scale';";
    try {
      getController().runJavaScript(js).catchError((_) {});
    } catch (_) {}
  }
}
