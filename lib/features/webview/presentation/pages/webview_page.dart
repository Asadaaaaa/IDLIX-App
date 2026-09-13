import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_domain_lock/core/services/storage_service.dart';
import 'package:webview_domain_lock/features/cast/presentation/widgets/cast_modal_bottom_sheet.dart';
import 'package:webview_domain_lock/features/cast/presentation/widgets/draggable_cast_button.dart';
import 'package:webview_domain_lock/features/cast/services/cast_manager.dart';
import 'package:webview_domain_lock/features/cast/services/video_detector_service.dart';
import 'package:webview_domain_lock/features/tv/presentation/widgets/tv_quick_menu.dart';
import 'package:webview_domain_lock/features/tv/services/tv_remote_controller.dart';
import 'package:webview_domain_lock/features/webview/models/webview_config.dart';
import 'package:webview_domain_lock/features/webview/presentation/widgets/loading_overlay.dart';
import 'package:webview_domain_lock/core/services/dns_service.dart';
import 'package:webview_domain_lock/core/services/remote_config_service.dart';
import 'package:webview_domain_lock/features/update/presentation/widgets/app_update_dialog.dart';
import 'package:webview_domain_lock/features/update/services/app_update_service.dart';
import 'package:webview_domain_lock/features/webview/presentation/widgets/idlix_splash_screen.dart';
import 'package:webview_domain_lock/features/webview/services/webview_navigation_service.dart';
import 'package:dart_cast/dart_cast.dart';

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
  late final VideoDetectorService _videoDetectorService;
  late final CastManager _castManager;
  TvRemoteController? _tvRemoteController;

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

  @override
  void initState() {
    super.initState();
    _navigationService = WebViewNavigationService();
    _videoDetectorService = VideoDetectorService();
    _castManager = CastManager();
    _castManager.init();
    _castManager.monitorVideoUpgrades(_videoDetectorService);
    _updateService = AppUpdateService();
    _dnsService = DnsService();
    _config = widget.initialConfig;
    _castManager.sessionStateNotifier.addListener(_syncCastStatusToWeb);

    if (widget.isTv) {
      _tvRemoteController = TvRemoteController(
        getController: () => _controller!,
        onToggleMenu: () {
          setState(() {
            _isTvMenuOpen = !_isTvMenuOpen;
          });
        },
        onBack: () => _handleBackPress(),
        onMediaPlayPause: () {
          if (_castManager.isCasting) {
            final isPlaying =
                _castManager.sessionStateNotifier.value == SessionState.playing;
            if (isPlaying) {
              _castManager.pause();
            } else {
              _castManager.play();
            }
          } else {
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
        },
        onMediaForward: () {
          if (_castManager.isCasting) {
            final cur = _castManager.positionNotifier.value;
            _castManager.seek(cur + const Duration(seconds: 10));
          } else {
            _controller?.runJavaScript('''
              (function() {
                var videos = document.querySelectorAll('video');
                if (videos.length > 0) videos[0].currentTime += 10;
              })();
            ''').catchError((_) {});
          }
        },
        onMediaRewind: () {
          if (_castManager.isCasting) {
            final cur = _castManager.positionNotifier.value;
            final newPos = cur - const Duration(seconds: 10);
            _castManager.seek(newPos.isNegative ? Duration.zero : newPos);
          } else {
            _controller?.runJavaScript('''
              (function() {
                var videos = document.querySelectorAll('video');
                if (videos.length > 0) videos[0].currentTime = Math.max(0, videos[0].currentTime - 10);
              })();
            ''').catchError((_) {});
          }
        },
      );
      _tvRemoteController!.init();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeWebView();
      _checkRemoteConfigUpdate();
      _checkForAppUpdate();
    });
  }

  @override
  void dispose() {
    _castManager.sessionStateNotifier.removeListener(_syncCastStatusToWeb);
    _tvRemoteController?.dispose();
    _castManager.stopDiscovery();
    super.dispose();
  }

  void _syncCastStatusToWeb() {
    final isCasting = _castManager.isCasting;
    _controller?.runJavaScript(
      'if (window.__updateCastStatus) window.__updateCastStatus($isCasting);',
    ).catchError((_) {});
  }

  void _openCastDialog() {
    _controller?.runJavaScript(
      'if (window.__triggerFastScan) window.__triggerFastScan();',
    ).catchError((_) {});
    if (widget.isTv) {
      setState(() {
        _isTvMenuOpen = true;
      });
    } else {
      CastModalBottomSheet.show(
        context: context,
        videoDetectorService: _videoDetectorService,
        castManager: _castManager,
      );
    }
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
      ..addJavaScriptChannel(
        'VideoDetectorChannel',
        onMessageReceived: (JavaScriptMessage message) {
          try {
            final data = jsonDecode(message.message) as Map<String, dynamic>;
            final type = data['type'] as String?;
            if (type == 'open_cast_dialog') {
              _openCastDialog();
              return;
            }
          } catch (_) {}
          _videoDetectorService.handleMessage(message.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (mounted) {
              setState(() {
                _loadingProgress = progress;
              });
            }
            if (progress >= 50 && progress <= 65) {
              controller
                  .runJavaScript(VideoDetectorService.getInjectionScript())
                  .catchError((_) {});
            }
          },
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _hasError = false;
                _errorMessage = null;
              });
            }
            _videoDetectorService.clear();
            _videoDetectorService.updateCurrentPage(url);
            // Injeksi awal sebelum script halaman lain dieksekusi
            controller
                .runJavaScript(VideoDetectorService.getPreInjectionScript())
                .catchError((_) {});
          },
          onPageFinished: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
              // Injeksi JS untuk mencegah popup window.open dan target="_blank"
              _preventPopupsAndNewWindows(controller);
              // Injeksi JS sniffer video & subtitle lengkap
              controller
                  .runJavaScript(VideoDetectorService.getInjectionScript())
                  .catchError((_) {});
              // Sinkronkan status cast ke tombol in-player
              _syncCastStatusToWeb();
              // Update judul halaman untuk video detector
              controller.getTitle().then((title) {
                if (title != null && title.isNotEmpty) {
                  _videoDetectorService.updatePageTitle(title);
                }
              }).catchError((_) {});
              // Terapkan zoom default dan spatial navigation untuk layar TV jika di TV
              if (widget.isTv && _tvRemoteController != null) {
                controller
                    .runJavaScript(
                      "document.body.style.zoom = '${_tvRemoteController!.textScaleNotifier.value}';",
                    )
                    .catchError((_) {});
                controller
                    .runJavaScript(TvRemoteController.getSpatialNavInjectionScript())
                    .catchError((_) {});
              }
            }
          },
          onUrlChange: (UrlChange change) {
            if (change.url != null && change.url!.isNotEmpty) {
              _videoDetectorService.inspectNetworkUrl(
                change.url!,
                referer: _videoDetectorService.currentPageUrl,
              );
            }
          },
          onWebResourceError: (WebResourceError error) {
            // Hanya tangani error level halaman utama (bukan resource minor seperti favicon yang gagal)
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
            _videoDetectorService.inspectNetworkUrl(
              request.url,
              referer: _videoDetectorService.currentPageUrl,
            );

            final lowerReq = request.url.toLowerCase();
            if (lowerReq.contains('embed') ||
                lowerReq.contains('player') ||
                lowerReq.contains('stream') ||
                lowerReq.contains('jeniusplay') ||
                lowerReq.contains('vidhide')) {
              _videoDetectorService.resolveEmbedUrl(
                request.url,
                referer: _videoDetectorService.currentPageUrl,
              );
            }

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
        final exited = await _controller!.runJavaScriptReturningResult(
          'window.__exitPlayerFullscreen ? window.__exitPlayerFullscreen() : false;',
        );
        if (exited == true || exited == 'true') {
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

                  // 5. Draggable Circular Floating Cast Button
                  if (_fullscreenCustomWidget == null)
                    DraggableCastButton(
                      videoDetectorService: _videoDetectorService,
                      castManager: _castManager,
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
                        videoDetectorService: _videoDetectorService,
                        castManager: _castManager,
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
