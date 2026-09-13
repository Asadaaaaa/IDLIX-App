import 'dart:async';
import 'package:dart_cast/dart_cast.dart';
import 'package:flutter/foundation.dart';
import 'package:webview_domain_lock/features/cast/models/detected_subtitle.dart';
import 'package:webview_domain_lock/features/cast/models/detected_video.dart';
import 'package:webview_domain_lock/features/cast/services/video_detector_service.dart';

class CastManager {
  static final CastManager _instance = CastManager._internal();
  factory CastManager() => _instance;
  CastManager._internal();

  CastService? _castService;
  StreamSubscription<List<CastDevice>>? _discoverySub;
  CastSession? _activeSession;

  final ValueNotifier<List<CastDevice>> devicesNotifier =
      ValueNotifier<List<CastDevice>>([]);
  final ValueNotifier<bool> isScanningNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<CastDevice?> activeDeviceNotifier =
      ValueNotifier<CastDevice?>(null);
  final ValueNotifier<SessionState> sessionStateNotifier =
      ValueNotifier<SessionState>(SessionState.disconnected);
  final ValueNotifier<DetectedVideo?> activeVideoNotifier =
      ValueNotifier<DetectedVideo?>(null);
  final ValueNotifier<DetectedSubtitle?> activeSubtitleNotifier =
      ValueNotifier<DetectedSubtitle?>(null);
  final ValueNotifier<Duration> positionNotifier =
      ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<Duration> durationNotifier =
      ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<double> volumeNotifier = ValueNotifier<double>(1.0);

  bool get isCasting =>
      activeDeviceNotifier.value != null &&
      sessionStateNotifier.value != SessionState.disconnected;

  void init() {
    if (_castService != null) return;

    _castService = CastService(
      discoveryProviders: [
        ChromecastDiscoveryProvider(),
        DlnaDiscoveryProvider(),
      ],
      sessionFactory: (device) {
        switch (device.protocol) {
          case CastProtocol.chromecast:
            return ChromecastSession(device: device);
          case CastProtocol.dlna:
            return DlnaSession.fromDevice(device);
          case CastProtocol.airplay:
            return AirPlaySession(device);
        }
      },
    );
  }

  /// Memulai pemindaian perangkat Cast (Chromecast & DLNA/Smart TV) di jaringan lokal
  void startDiscovery({Duration timeout = const Duration(seconds: 12)}) {
    init();
    stopDiscovery();

    isScanningNotifier.value = true;
    devicesNotifier.value = [];

    _discoverySub = _castService!.startDiscovery(timeout: timeout).listen(
      (devices) {
        devicesNotifier.value = devices;
      },
      onError: (error) {
        debugPrint('CastManager: discovery error: $error');
        isScanningNotifier.value = false;
      },
      onDone: () {
        isScanningNotifier.value = false;
      },
    );
  }

  /// Menghentikan pemindaian perangkat
  void stopDiscovery() {
    _discoverySub?.cancel();
    _discoverySub = null;
    _castService?.stopDiscovery();
    isScanningNotifier.value = false;
  }

  /// Menghubungkan ke perangkat Cast
  Future<CastSession> connect(CastDevice device) async {
    init();
    try {
      activeDeviceNotifier.value = device;
      sessionStateNotifier.value = SessionState.connecting;

      final session = await _castService!.connect(device);
      _activeSession = session;
      sessionStateNotifier.value = session.state;

      // Listen state changes
      session.stateStream.listen((state) {
        sessionStateNotifier.value = state;
        if (state == SessionState.disconnected) {
          _cleanupSession();
        }
      });

      // Listen position & duration updates
      session.positionStream.listen((pos) {
        positionNotifier.value = pos;
      });
      session.durationStream.listen((dur) {
        durationNotifier.value = dur;
      });
      session.volumeStream.listen((vol) {
        volumeNotifier.value = vol;
      });

      return session;
    } catch (e) {
      debugPrint('CastManager: error connecting to device: $e');
      _cleanupSession();
      rethrow;
    }
  }

  /// Mengirim media video dan subtitle ke perangkat Cast
  Future<void> castVideo({
    required DetectedVideo video,
    DetectedSubtitle? subtitle,
    CastDevice? targetDevice,
  }) async {
    init();

    if (targetDevice != null &&
        (_activeSession == null ||
            activeDeviceNotifier.value?.id != targetDevice.id)) {
      await connect(targetDevice);
    }

    if (_activeSession == null) {
      throw StateError('Tidak ada perangkat Cast yang terhubung');
    }

    activeVideoNotifier.value = video;
    activeSubtitleNotifier.value = subtitle;

    final mediaType = video.isHls ? CastMediaType.hls : CastMediaType.mp4;

    final castSubtitles = <CastSubtitle>[];
    for (final s in video.subtitles) {
      castSubtitles.add(
        CastSubtitle(
          url: s.url,
          label: s.label,
          language: s.lang,
          format: s.url.toLowerCase().contains('.vtt') ? 'vtt' : 'srt',
        ),
      );
    }

    CastSubtitle? defaultSub;
    if (subtitle != null) {
      defaultSub = CastSubtitle(
        url: subtitle.url,
        label: subtitle.label,
        language: subtitle.lang,
        format: subtitle.url.toLowerCase().contains('.vtt') ? 'vtt' : 'srt',
      );
      // Pastikan ada dalam list jika belum ada
      if (!castSubtitles.any((s) => s.url == defaultSub!.url)) {
        castSubtitles.add(defaultSub);
      }
    }

    final media = CastMedia(
      url: video.url,
      type: mediaType,
      title: video.title,
      subtitles: castSubtitles,
      defaultSubtitle: defaultSub,
      httpHeaders: video.headers,
    );

    await _activeSession!.loadMedia(media);
  }

  Future<void> play() async {
    await _activeSession?.play();
  }

  Future<void> pause() async {
    await _activeSession?.pause();
  }

  Future<void> seek(Duration position) async {
    await _activeSession?.seek(position);
  }

  Future<void> setVolume(double volume) async {
    await _activeSession?.setVolume(volume);
  }

  Future<void> setSubtitle(DetectedSubtitle? subtitle) async {
    activeSubtitleNotifier.value = subtitle;
    if (subtitle == null) {
      await _activeSession?.setSubtitle(null);
    } else {
      await _activeSession?.setSubtitle(
        CastSubtitle(
          url: subtitle.url,
          label: subtitle.label,
          language: subtitle.lang,
          format: subtitle.url.toLowerCase().contains('.vtt') ? 'vtt' : 'srt',
        ),
      );
    }
  }

  Future<void> disconnect() async {
    try {
      await _activeSession?.disconnect();
    } catch (e) {
      debugPrint('CastManager: error during disconnect: $e');
    } finally {
      _cleanupSession();
    }
  }

  /// Monitors for movie stream upgrades when an ad stream finishes or real film stream is detected
  void monitorVideoUpgrades(VideoDetectorService videoDetectorService) {
    videoDetectorService.detectedVideosNotifier.addListener(() {
      if (isCasting && activeVideoNotifier.value != null) {
        final cur = activeVideoNotifier.value!;
        final best = videoDetectorService.getBestVideo();
        if (best != null && best.url != cur.url) {
          if (cur.isLikelyAd || (best.priorityScore > cur.priorityScore + 30)) {
            debugPrint('CastManager: Auto-upgrading cast stream to detected movie stream: ${best.url}');
            castVideo(
              video: best,
              subtitle: activeSubtitleNotifier.value ?? (best.subtitles.isNotEmpty ? best.subtitles.first : null),
              targetDevice: activeDeviceNotifier.value,
            ).catchError((e) {
              debugPrint('CastManager: error auto-upgrading stream: $e');
            });
          }
        }
      }
    });
  }

  void _cleanupSession() {
    _activeSession = null;
    activeDeviceNotifier.value = null;
    activeVideoNotifier.value = null;
    activeSubtitleNotifier.value = null;
    sessionStateNotifier.value = SessionState.disconnected;
    positionNotifier.value = Duration.zero;
    durationNotifier.value = Duration.zero;
  }
}
