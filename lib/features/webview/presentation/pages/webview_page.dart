import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_domain_lock/core/services/storage_service.dart';
import 'package:webview_domain_lock/features/remote_sync/models/remote_command.dart';
import 'package:webview_domain_lock/features/remote_sync/presentation/widgets/draggable_tv_remote_button.dart';
import 'package:webview_domain_lock/features/remote_sync/services/mobile_remote_service.dart';
import 'package:webview_domain_lock/features/remote_sync/services/tv_receiver_service.dart';
import 'package:webview_domain_lock/features/tv/presentation/widgets/tv_quick_menu.dart';
import 'package:webview_domain_lock/features/tv/presentation/widgets/tv_virtual_cursor.dart';
import 'package:webview_domain_lock/features/tv/services/tv_remote_controller.dart';
import 'package:webview_domain_lock/features/webview/models/webview_config.dart';
import 'package:webview_domain_lock/features/webview/presentation/widgets/loading_overlay.dart';
import 'package:webview_domain_lock/core/services/dns_service.dart';
import 'package:webview_domain_lock/core/services/remote_config_service.dart';
import 'package:webview_domain_lock/features/update/presentation/widgets/app_update_dialog.dart';
import 'package:webview_domain_lock/features/update/services/app_update_service.dart';
import 'package:webview_domain_lock/features/webview/presentation/widgets/idlix_splash_screen.dart';
import 'package:webview_domain_lock/features/webview/services/webview_navigation_service.dart';

class WebViewPage extends StatefulWidget {
  final StorageService storageService;
  final RemoteConfigService remoteConfigService;
  final WebViewConfig initialConfig;
  final bool isTv;

  const WebViewPage({
    super.key,
    required this.storageService,
    required this.remoteConfigService,
    required this.initialConfig,
    this.isTv = false,
  });

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late final WebViewNavigationService _navigationService;
  TvRemoteController? _tvRemoteController;

  MobileRemoteService? _mobileRemoteService;
  TvReceiverService? _tvReceiverService;

  WebViewController? _controller;
  WebViewConfig? _config;

  late final AppUpdateService _updateService;
  late final DnsService _dnsService;

  bool _isLoading = true;
  int _loadingProgress = 0;
  bool _hasError = false;
  String? _errorMessage;
  bool _isInitialSplashVisible = true;

  bool _isTvMenuOpen = false;
  Widget? _fullscreenCustomWidget;
  void Function()? _onHideCustomWidget;

  String _currentLoadedUrl = '';
  String _currentLoadedTitle = '';
  bool _pendingAutoPlay = false;

  @override
  void initState() {
    super.initState();
    _navigationService = WebViewNavigationService();
    _updateService = AppUpdateService();
    _dnsService = DnsService();
    _config = widget.initialConfig;

    if (widget.isTv) {
      _tvReceiverService = TvReceiverService(
        onCommandReceived: _handleTvRemoteCommand,
      );
      _tvReceiverService!.start();

      _tvRemoteController = TvRemoteController(
        getController: () => _controller!,
        onToggleMenu: () {
          setState(() {
            _isTvMenuOpen = !_isTvMenuOpen;
          });
        },
        onBack: () => _handleBackPress(),
        onMediaPlayPause: () => _toggleWebVideoPlayPause(),
        onMediaForward: () => _seekWebVideo(10),
        onMediaRewind: () => _seekWebVideo(-10),
      );
      _tvRemoteController!.init();
    } else {
      _mobileRemoteService = MobileRemoteService();
      _mobileRemoteService!.startAutoDiscovery();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeWebView();
      _checkRemoteConfigUpdate();
      _checkForAppUpdate();
    });
  }

  @override
  void dispose() {
    _tvRemoteController?.dispose();
    _tvReceiverService?.dispose();
    _mobileRemoteService?.dispose();
    super.dispose();
  }

  void _handleTvRemoteCommand(RemoteCommand cmd) {
    switch (cmd.action) {
      case RemoteAction.navigate:
        if (cmd.url != null && cmd.url!.isNotEmpty && _controller != null) {
          _pendingAutoPlay = (cmd.autoPlay == true);
          _controller!.loadRequest(Uri.parse(cmd.url!));
        }
        break;
      case RemoteAction.autoPlay:
        _triggerAutoPlay();
        break;
      case RemoteAction.fullscreen:
        _togglePlayerFullscreen();
        break;
      case RemoteAction.cursorMove:
        if (cmd.dx != null && cmd.dy != null) {
          _tvRemoteController?.moveCursorBy(cmd.dx!, cmd.dy!);
        }
        break;
      case RemoteAction.cursorClick:
        _tvRemoteController?.performClick();
        break;
      case RemoteAction.scroll:
        if (cmd.dy != null) {
          _tvRemoteController?.scrollWeb(0, cmd.dy!.toInt());
        }
        break;
      case RemoteAction.playPause:
        _toggleWebVideoPlayPause();
        break;
      case RemoteAction.seekForward:
        _seekWebVideo(10);
        break;
      case RemoteAction.seekRewind:
        _seekWebVideo(-10);
        break;
      case RemoteAction.reload:
        _controller?.reload();
        break;
      case RemoteAction.goBack:
        _handleBackPress();
        break;
    }
  }

  /// Otomatis mencari tombol play / iframe player dan memutarnya setelah redirect
  void _triggerAutoPlay() {
    _controller?.runJavaScript('''
      (function() {
        function tryClickPlay() {
          // 1. Cari tombol play banner / movie info
          var playBtns = [
            document.querySelector('.play-btn'),
            document.querySelector('.btn-play'),
            document.querySelector('.play-button'),
            document.querySelector('a[href*="#player"]'),
            document.querySelector('a.lnk-blk'),
            document.querySelector('.dooplay_player_option'),
            document.querySelector('#playeroptionsul li.on'),
            document.querySelector('#playeroptionsul li:first-child'),
            document.querySelector('.server-item'),
            document.querySelector('.btn-server'),
            document.querySelector('.jw-display-icon-container'),
            document.querySelector('.vjs-big-play-button')
          ];
          for (var i = 0; i < playBtns.length; i++) {
            var b = playBtns[i];
            if (b && typeof b.click === 'function') {
              try { b.click(); } catch(e) {}
              break;
            }
          }

          // 2. Play tag video jika sudah ada
          var videos = document.querySelectorAll('video');
          for (var j = 0; j < videos.length; j++) {
            try {
              if (videos[j].paused) {
                videos[j].play();
              }
            } catch(e) {}
          }

          // 3. Scroll ke player jika ada
          var player = document.getElementById('embed-holder') || document.getElementById('player') || document.querySelector('.player-embed');
          if (player) {
            try { player.scrollIntoView({ behavior: 'smooth', block: 'center' }); } catch(e) {}
          }
        }

        tryClickPlay();
        setTimeout(tryClickPlay, 800);
        setTimeout(tryClickPlay, 1800);
        setTimeout(tryClickPlay, 3500);
      })();
    ''').catchError((_) {});
  }

  /// Toggle Fullscreen handal untuk Android TV (CSS Fixed Overlay + Native Fullscreen fallback)
  void _togglePlayerFullscreen() {
    _controller?.runJavaScript('''
      (function() {
        var container = document.getElementById('embed-holder') ||
                        document.getElementById('player') ||
                        document.querySelector('.player-embed') ||
                        document.querySelector('.player-large') ||
                        document.querySelector('.play-wrapper') ||
                        document.querySelector('.embed-responsive') ||
                        document.querySelector('iframe[src*="embed"]') ||
                        document.querySelector('iframe[src*="player"]') ||
                        document.querySelector('iframe') ||
                        document.querySelector('video');
        if (!container) return;

        if (window.__isIdlixCssFullscreen) {
          window.__isIdlixCssFullscreen = false;
          if (container.dataset.origStyle !== undefined) {
            container.style.cssText = container.dataset.origStyle;
          } else {
            container.style.cssText = '';
          }
          var ifr = container.querySelector('iframe') || (container.tagName === 'IFRAME' ? container : null);
          if (ifr && ifr.dataset.origStyle !== undefined) {
            ifr.style.cssText = ifr.dataset.origStyle;
          }
          document.body.style.overflow = '';
          if (document.exitFullscreen) {
            document.exitFullscreen().catch(function(){});
          } else if (document.webkitExitFullscreen) {
            document.webkitExitFullscreen();
          }
          return;
        }

        window.__isIdlixCssFullscreen = true;
        container.dataset.origStyle = container.getAttribute('style') || '';
        container.style.cssText = 'position: fixed !important; top: 0 !important; left: 0 !important; width: 100vw !important; height: 100vh !important; z-index: 2147483647 !important; background: #000 !important; margin: 0 !important; padding: 0 !important; border: none !important;';

        var ifr = container.querySelector('iframe') || (container.tagName === 'IFRAME' ? container : null);
        if (ifr) {
          ifr.dataset.origStyle = ifr.getAttribute('style') || '';
          ifr.style.cssText = 'width: 100vw !important; height: 100vh !important; border: none !important; position: fixed !important; top: 0 !important; left: 0 !important; z-index: 2147483647 !important;';
          ifr.setAttribute('allowfullscreen', 'true');
        }

        document.body.style.overflow = 'hidden';

        try {
          var v = container.querySelector('video') || (container.tagName === 'VIDEO' ? container : null);
          if (v && v.requestFullscreen) {
            v.requestFullscreen().catch(function(){});
          } else if (container.requestFullscreen) {
            container.requestFullscreen().catch(function(){});
          } else if (container.webkitRequestFullscreen) {
            container.webkitRequestFullscreen();
          }
        } catch(e) {}
      })();
    ''').catchError((_) {});
  }

  void _toggleWebVideoPlayPause() {
    _controller?.runJavaScript('''
      (function() {
        var videos = document.querySelectorAll('video');
        if (videos.length > 0) {
          var v = videos[0];
          if (v.paused) v.play(); else v.pause();
        }
      })();
    ''').catchError((_) {});
  }

  void _seekWebVideo(int seconds) {
    _controller?.runJavaScript('''
      (function() {
        var videos = document.querySelectorAll('video');
        if (videos.length > 0) {
          var v = videos[0];
          v.currentTime = Math.max(0, v.currentTime + ($seconds));
        }
      })();
    ''').catchError((_) {});
  }

  /// Memeriksa pembaruan URL domain dari GitHub raw secara berkala atau saat diminta pengguna
  Future<void> _checkRemoteConfigUpdate({bool showFeedback = false}) async {
    try {
      final latest = await widget.remoteConfigService.fetchLatestConfig();
      if (!mounted) return;

      if (latest.mainUrl != _config?.mainUrl || latest.allowedHost != _config?.allowedHost) {
        setState(() {
          _config = latest;
          _hasError = false;
          _errorMessage = null;
          _isLoading = true;
        });

        if (_controller != null) {
          await _controller!.loadRequest(Uri.parse(latest.mainUrl));
        } else {
          _initializeWebView();
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('IDLIX domain updated: ${latest.mainUrl}'),
              backgroundColor: Colors.teal,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('IDLIX domain is up to date (${latest.mainUrl})'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to check for IDLIX domain updates.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// Memeriksa pembaruan aplikasi IDLIX dari GitHub raw
  Future<void> _checkForAppUpdate({bool showFeedback = false}) async {
    try {
      final updateInfo = await _updateService.checkForUpdate();
      if (!mounted) return;

      if (updateInfo != null) {
        await AppUpdateDialog.show(
          context: context,
          updateInfo: updateInfo,
          isTv: widget.isTv,
          updateService: _updateService,
        );
      } else if (showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('IDLIX app is up to date.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to check for app updates.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// Inisialisasi WebViewController beserta pengamanan navigasi dan popup
  void _initializeWebView() {
    if (_config == null) return;

    final WebViewController controller = WebViewController();

    // Set platform-specific params jika di Android
    if (controller.platform is AndroidWebViewController) {
      final androidController = controller.platform as AndroidWebViewController;
      androidController.setMediaPlaybackRequiresUserGesture(false);
      androidController.setCustomWidgetCallbacks(
        onShowCustomWidget: (Widget customWidget, OnHideCustomWidgetCallback callback) {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
          if (!widget.isTv) {
            SystemChrome.setPreferredOrientations([
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
              DeviceOrientation.portraitUp,
            ]);
          }
          setState(() {
            _fullscreenCustomWidget = customWidget;
            _onHideCustomWidget = callback;
          });
        },
        onHideCustomWidget: () {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
          if (!widget.isTv) {
            SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
          }
          setState(() {
            _fullscreenCustomWidget = null;
            _onHideCustomWidget = null;
          });
        },
      );
    }

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (mounted) {
              setState(() {
                _loadingProgress = progress;
              });
            }
          },
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _hasError = false;
                _errorMessage = null;
                _currentLoadedUrl = url;
              });
            }
          },
          onPageFinished: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _currentLoadedUrl = url;
              });
              // Injeksi JS untuk mencegah popup window.open dan target="_blank"
              _preventPopupsAndNewWindows(controller);

              // Update judul halaman
              controller.getTitle().then((title) {
                if (title != null && title.isNotEmpty && mounted) {
                  setState(() {
                    _currentLoadedTitle = title;
                  });
                }
              }).catchError((_) {});

              // Terapkan zoom default untuk layar TV jika di TV
              if (widget.isTv && _tvRemoteController != null) {
                controller
                    .runJavaScript(
                      "document.body.style.zoom = '${_tvRemoteController!.textScaleNotifier.value}';",
                    )
                    .catchError((_) {});
              }

              // Jika terdapat perintah navigasi dari 'Putar di TV', langsung otomatis jalankan pemutaran film
              if (_pendingAutoPlay) {
                _pendingAutoPlay = false;
                Future.delayed(const Duration(milliseconds: 600), () {
                  if (mounted) _triggerAutoPlay();
                });
              }
            }
          },
          onUrlChange: (UrlChange change) {
            if (change.url != null && change.url!.isNotEmpty && mounted) {
              setState(() {
                _currentLoadedUrl = change.url!;
              });
            }
          },
          onWebResourceError: (WebResourceError error) {
            if (error.isForMainFrame ?? true) {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _hasError = true;
                  _errorMessage = 'Unable to load website: ${error.description}';
                });
              }
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            final allowedHost = _config?.allowedHost ?? '';
            final eval = _navigationService.evaluateNavigation(
              request.url,
              allowedHost,
              isMainFrame: request.isMainFrame,
            );

            if (eval == NavigationResult.allowed) {
              return NavigationDecision.navigate;
            }

            // Blokir navigasi
            _handleBlockedNavigation(eval, request.url);
            return NavigationDecision.prevent;
          },
        ),
      );

    // Resolve domain target via Cloudflare DNS 1.1.1.1 DoH sebelum membuka URL
    try {
      final host = Uri.parse(_config!.mainUrl).host;
      _dnsService.resolveHost(host);
    } catch (_) {}

    controller.loadRequest(Uri.parse(_config!.mainUrl));

    setState(() {
      _controller = controller;
    });
  }

  /// JavaScript injection untuk mengarahkan window.open dan target="_blank" ke dalam WebView
  /// Menggunakan event delegation ringan tanpa MutationObserver agar scrolling tetap 60/120 FPS
  void _preventPopupsAndNewWindows(WebViewController controller) {
    const jsScript = '''
      (function() {
        if (window.__popupProtectionInjected) return;
        window.__popupProtectionInjected = true;

        // Override window.open agar membuka di frame saat ini
        window.open = function(url) {
          if (url) {
            window.location.href = url;
          }
          return null;
        };

        // Event delegation ringan saat click: mengubah target=_blank menjadi target=_self
        document.addEventListener('click', function(e) {
          try {
            var el = e.target;
            while (el && el.tagName !== 'A' && el !== document.body) {
              el = el.parentElement;
            }
            if (el && el.tagName === 'A' && el.getAttribute('target') === '_blank') {
              el.setAttribute('target', '_self');
            }
          } catch(err) {}
        }, true);
      })();
    ''';
    controller.runJavaScript(jsScript).catchError((_) {});
  }

  void _handleBlockedNavigation(NavigationResult result, String url) {
    if (!mounted || result == NavigationResult.allowed) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: const [
            Icon(Icons.shield, color: Colors.amber, size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Popup Ads Blocked',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red.shade900.withValues(alpha: 0.9),
      ),
    );
  }

  Future<void> _handleBackPress() async {
    if (_fullscreenCustomWidget != null) {
      _onHideCustomWidget?.call();
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      if (!widget.isTv) {
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      }
      setState(() {
        _fullscreenCustomWidget = null;
        _onHideCustomWidget = null;
      });
      return;
    }
    if (_controller != null) {
      try {
        final isFs = await _controller!.runJavaScriptReturningResult(
          'window.__isIdlixCssFullscreen ? true : false;',
        );
        if (isFs == true || isFs == 'true') {
          _togglePlayerFullscreen();
          return;
        }
      } catch (_) {}
    }
    if (_isTvMenuOpen) {
      setState(() {
        _isTvMenuOpen = false;
      });
      return;
    }
    if (_controller != null && await _controller!.canGoBack()) {
      await _controller!.goBack();
    } else {
      if (mounted) {
        Navigator.of(context).maybePop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isTv && _tvRemoteController != null) {
      _tvRemoteController!.updateScreenSize(MediaQuery.of(context).size);
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBackPress();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Main content wrapped in SafeArea
            SafeArea(
              top: !widget.isTv && _fullscreenCustomWidget == null,
              bottom: false,
              left: _fullscreenCustomWidget == null,
              right: _fullscreenCustomWidget == null,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 1. Main WebView (always kept alive in widget tree)
                  if (_controller != null && !_hasError)
                    WebViewWidget(controller: _controller!),

                  // 2. Fullscreen Custom HTML5 Video Widget (rendered on top)
                  if (_fullscreenCustomWidget != null)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black,
                        child: _fullscreenCustomWidget!,
                      ),
                    ),

                  // 3. Error State
                  if (_hasError && _fullscreenCustomWidget == null)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: 64,
                              color: Colors.redAccent,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Unable to load website.',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (_errorMessage != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _hasError = false;
                                  _errorMessage = null;
                                });
                                if (_controller != null && _config != null) {
                                  _controller!.loadRequest(Uri.parse(_config!.mainUrl));
                                }
                              },
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // 4. Loading Overlay during subsequent navigation
                  if (!_isInitialSplashVisible && _isLoading && !_hasError && _fullscreenCustomWidget == null)
                    LoadingOverlay(progress: _loadingProgress),

                  // 5. Draggable TV Remote Companion Button (Mobile mode)
                  if (!widget.isTv && _mobileRemoteService != null && _fullscreenCustomWidget == null)
                    DraggableTvRemoteButton(
                      remoteService: _mobileRemoteService!,
                      getCurrentUrl: () => _currentLoadedUrl.isNotEmpty ? _currentLoadedUrl : (_config?.mainUrl ?? ''),
                      getCurrentTitle: () => _currentLoadedTitle.isNotEmpty ? _currentLoadedTitle : 'IDLIX Film',
                    ),

                  // 6b. TV Remote Menu Shortcut Button
                  if (widget.isTv && _fullscreenCustomWidget == null)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _isTvMenuOpen = !_isTvMenuOpen;
                            });
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.settings_remote, color: Colors.blueAccent, size: 16),
                                SizedBox(width: 6),
                                Text(
                                  'TV Remote (Menu)',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                  // 7. TV Quick Menu Overlay
                  if (widget.isTv && _isTvMenuOpen && _tvRemoteController != null)
                    Positioned.fill(
                      child: TvQuickMenu(
                        remoteController: _tvRemoteController!,
                        getController: () => _controller!,
                        tvReceiverService: _tvReceiverService,
                        onOpenSettings: () {
                          _checkRemoteConfigUpdate(showFeedback: true);
                          _checkForAppUpdate(showFeedback: true);
                        },
                        onClose: () {
                          setState(() {
                            _isTvMenuOpen = false;
                          });
                        },
                      ),
                    ),

                  // 8. Virtual Mouse Cursor untuk layar TV
                  if (widget.isTv && _tvRemoteController != null && _fullscreenCustomWidget == null)
                    TvVirtualCursor(remoteController: _tvRemoteController!),
                ],
              ),
            ),

            // Pure Edge-to-Edge Fullscreen IDLIX Splash Screen
            if (_isInitialSplashVisible && _fullscreenCustomWidget == null)
              Positioned.fill(
                child: IdlixSplashScreen(
                  loadingProgress: _loadingProgress,
                  isFinished: !_isLoading && !_hasError,
                  onDismissed: () {
                    if (mounted) {
                      setState(() {
                        _isInitialSplashVisible = false;
                      });
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
