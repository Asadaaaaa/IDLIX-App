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

  /// Returns the JavaScript injection script for Netflix-style TV spatial navigation
  static String getSpatialNavInjectionScript() => TvSpatialNavigationScript.script;

  // Legacy cursor position notifier (preserved for compatibility)
  final ValueNotifier<Offset> cursorPositionNotifier =
      ValueNotifier<Offset>(const Offset(300, 300));

  // Cursor is hidden by default in favor of Netflix-style element selection
  final ValueNotifier<bool> isCursorVisibleNotifier =
      ValueNotifier<bool>(false);

  // Click animation state
  final ValueNotifier<bool> isClickingNotifier = ValueNotifier<bool>(false);

  // Web text scale / zoom level
  final ValueNotifier<double> textScaleNotifier = ValueNotifier<double>(1.25);

  Size screenSize = const Size(1920, 1080);
  Timer? _continuousMoveTimer;
  LogicalKeyboardKey? _currentHeldKey;

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
      if (cursorPositionNotifier.value == const Offset(300, 300)) {
        cursorPositionNotifier.value = Offset(size.width / 2, size.height / 2);
      }
    }
  }

  bool _handleKeyEvent(KeyEvent event) {
    final key = event.logicalKey;

    // 1. Menu Button on TV Remote
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

    // 2. Media Buttons (Play / Pause / Rewind / FastForward)
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

    // 3. Back Button
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      if (event is KeyDownEvent) {
        onBack();
        return true;
      }
      return false;
    }

    // 4. OK / Select / Center / Enter Button -> Click currently selected element
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

    // 5. Page Up / Page Down / Channel Up / Channel Down -> Fast smooth scrolling
    if (key == LogicalKeyboardKey.pageUp || key == LogicalKeyboardKey.channelUp) {
      if (event is KeyDownEvent) {
        _scrollWeb(0, -350);
        return true;
      }
      return false;
    }
    if (key == LogicalKeyboardKey.pageDown || key == LogicalKeyboardKey.channelDown) {
      if (event is KeyDownEvent) {
        _scrollWeb(0, 350);
        return true;
      }
      return false;
    }

    // 6. D-Pad Directional Navigation (Up, Down, Left, Right) -> Netflix-style element selection
    final isArrow = key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;

    if (isArrow) {
      if (event is KeyDownEvent) {
        // Prevent duplicate initial navigation if OS fires repeat keydown events
        if (_currentHeldKey != key) {
          _currentHeldKey = key;
          final dir = _getDirectionFromKey(key);
          if (dir != null) {
            navigateDirection(dir);
          }

          // When held down, smoothly step through elements
          _continuousMoveTimer?.cancel();
          _continuousMoveTimer = Timer(const Duration(milliseconds: 280), () {
            if (_currentHeldKey == key) {
              _continuousMoveTimer = Timer.periodic(
                const Duration(milliseconds: 160),
                (_) {
                  if (_currentHeldKey != null) {
                    final d = _getDirectionFromKey(_currentHeldKey!);
                    if (d != null) {
                      navigateDirection(d);
                    }
                  }
                },
              );
            }
          });
        }
        return true;
      } else if (event is KeyUpEvent) {
        if (_currentHeldKey == key) {
          _continuousMoveTimer?.cancel();
          _continuousMoveTimer = null;
          _currentHeldKey = null;
        }
        return true;
      }
    }

    return false;
  }

  String? _getDirectionFromKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowUp) return 'up';
    if (key == LogicalKeyboardKey.arrowDown) return 'down';
    if (key == LogicalKeyboardKey.arrowLeft) return 'left';
    if (key == LogicalKeyboardKey.arrowRight) return 'right';
    return null;
  }

  /// Navigates focus spatially in the given direction ('up', 'down', 'left', 'right')
  void navigateDirection(String direction) {
    final js = '''
      (function() {
        if (window.__idlixTvNav) {
          window.__idlixTvNav.navigate('$direction');
        } else {
          if ('$direction' === 'down') window.scrollBy({ top: 300, behavior: 'smooth' });
          if ('$direction' === 'up') window.scrollBy({ top: -300, behavior: 'smooth' });
        }
      })();
    ''';
    try {
      getController().runJavaScript(js).catchError((_) {});
    } catch (_) {}
  }

  /// Clicks the currently selected / focused element
  void performClick() {
    isClickingNotifier.value = true;
    Timer(const Duration(milliseconds: 200), () {
      isClickingNotifier.value = false;
    });

    final js = '''
      (function() {
        if (window.__idlixTvNav) {
          window.__idlixTvNav.click();
        } else {
          var el = document.activeElement;
          if (el && typeof el.click === 'function') el.click();
        }
      })();
    ''';
    try {
      getController().runJavaScript(js).catchError((_) {});
    } catch (_) {}
  }

  void _scrollWeb(int x, int y) {
    final js = '''
      (function() {
        if (window.__idlixTvNav && typeof window.__idlixTvNav.scroll === 'function') {
          window.__idlixTvNav.scroll($y);
        } else {
          window.scrollBy({ top: $y, behavior: 'smooth' });
        }
      })();
    ''';
    try {
      getController().runJavaScript(js).catchError((_) {});
    } catch (_) {}
  }

  void setZoom(double scale) {
    textScaleNotifier.value = scale;
    final js = "document.body.style.zoom = '$scale';";
    try {
      getController().runJavaScript(js).catchError((_) {});
    } catch (_) {}
  }
}
