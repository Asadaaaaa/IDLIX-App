import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:webview_domain_lock/core/utils/domain_utils.dart';
import 'package:webview_domain_lock/features/cast/models/detected_subtitle.dart';
import 'package:webview_domain_lock/features/cast/models/detected_video.dart';

class VideoDetectorService {
  final ValueNotifier<List<DetectedVideo>> detectedVideosNotifier =
      ValueNotifier<List<DetectedVideo>>([]);

  final ValueNotifier<List<DetectedSubtitle>> standaloneSubtitlesNotifier =
      ValueNotifier<List<DetectedSubtitle>>([]);

  List<DetectedVideo> get detectedVideos => detectedVideosNotifier.value;
  List<DetectedSubtitle> get standaloneSubtitles =>
      standaloneSubtitlesNotifier.value;

  String currentPageUrl = '';
  String currentPageTitle = '';

  /// Update URL halaman saat ini untuk referer cast
  void updateCurrentPage(String url) {
    currentPageUrl = url;
  }

  /// Update judul halaman saat ini untuk penamaan video yang terdeteksi
  void updatePageTitle(String title) {
    currentPageTitle = title.trim();
    if (currentPageTitle.isEmpty) return;

    final currentList = List<DetectedVideo>.from(detectedVideosNotifier.value);
    var updated = false;
    for (var i = 0; i < currentList.length; i++) {
      final v = currentList[i];
      if (v.title == 'Web Video' || v.title == 'IDLIX Stream' || v.title.isEmpty) {
        currentList[i] = v.copyWith(title: currentPageTitle);
        updated = true;
      }
    }
    if (updated) {
      detectedVideosNotifier.value = currentList;
    }
  }

  /// Returns the highest quality/priority main movie stream (excluding ads)
  DetectedVideo? getBestVideo() {
    if (detectedVideos.isEmpty) return null;
    final nonAds = detectedVideos.where((v) => !v.isLikelyAd).toList();
    if (nonAds.isEmpty) return detectedVideos.first;
    nonAds.sort((a, b) => b.priorityScore.compareTo(a.priorityScore));
    return nonAds.first;
  }

  /// Membersihkan video dan subtitle terdeteksi saat halaman utama berpindah
  void clear() {
    detectedVideosNotifier.value = [];
    standaloneSubtitlesNotifier.value = [];
  }

  /// Memeriksa URL yang dimuat oleh WebView di level jaringan / WebViewClient.onLoadResource
  /// Mampu menangkap m3u8 / mp4 / vtt di dalam iframe cross-origin sekalipun!
  void inspectNetworkUrl(String url, {String? pageTitle, String? referer}) {
    if (url.trim().isEmpty) return;
    final trimmedUrl = url.trim();
    final lower = trimmedUrl.toLowerCase();

    // 1. Abaikan blob, data, dan javascript URLs
    if (lower.startsWith('blob:') ||
        lower.startsWith('data:') ||
        lower.startsWith('javascript:')) {
      return;
    }

    // 2. Blokir domain iklan dan URL sponsor judi (asia9, sbobet, mpo, dsb.)
    if (DomainUtils.isBlockedAdDomain(trimmedUrl)) {
      return;
    }
    const adKeywords = [
      'asia9',
      'sbobet',
      'mposport',
      'judionline',
      'monetag',
      'highcpm',
      'slot',
      'casino',
      'betting',
      '/ad/',
      '/ads/',
      '/advert',
      'preroll',
      'pre-roll',
      'midroll',
      'postroll',
      'vast',
      'vpaid',
      'ima3',
      'imasdk',
      'popads',
      'adsterra',
      'propeller',
      'doubleclick',
      'googlesyndication',
      'adsystem',
      'adservice',
    ];
    for (final kw in adKeywords) {
      if (lower.contains(kw)) return;
    }

    final cleanUrl = lower.split('?').first;

    // 3. Deteksi Subtitle (.vtt, .srt)
    final isSubtitle = cleanUrl.endsWith('.vtt') ||
        cleanUrl.endsWith('.srt') ||
        cleanUrl.endsWith('.sub') ||
        lower.contains('.vtt?') ||
        lower.contains('.srt?') ||
        lower.contains('/subtitles/') ||
        lower.contains('/sub/');

    if (isSubtitle) {
      String label = 'Subtitle';
      String lang = 'auto';
      if (lower.contains('indonesia') ||
          lower.contains('_id') ||
          lower.contains('-id') ||
          lower.contains('ind') ||
          lower.contains('indo')) {
        label = 'Indonesian';
        lang = 'id';
      } else if (lower.contains('english') ||
          lower.contains('_en') ||
          lower.contains('-en') ||
          lower.contains('eng')) {
        label = 'English';
        lang = 'en';
      }
      _addSubtitle(DetectedSubtitle(url: trimmedUrl, label: label, lang: lang));
      return;
    }

    // 4. Deteksi Video Stream (.m3u8, /hls/, .mp4, .webm, .mpd)
    final isVideo = cleanUrl.endsWith('.m3u8') ||
        cleanUrl.endsWith('.mpd') ||
        cleanUrl.endsWith('.mp4') ||
        cleanUrl.endsWith('.webm') ||
        cleanUrl.endsWith('.mkv') ||
        lower.contains('.m3u8') ||
        lower.contains('/hls/');

    if (isVideo) {
      // Filter file chunk / segmen video agar tidak memenuhi daftar
      if (cleanUrl.endsWith('.ts') ||
          cleanUrl.endsWith('.m4s') ||
          cleanUrl.contains('segment') ||
          cleanUrl.contains('frag') ||
          cleanUrl.contains('/chunk')) {
        return;
      }

      final title = (pageTitle != null && pageTitle.isNotEmpty)
          ? pageTitle
          : (currentPageTitle.isNotEmpty
              ? currentPageTitle
              : 'IDLIX Stream');

      final headers = <String, String>{};
      final ref = referer ?? (currentPageUrl.isNotEmpty ? currentPageUrl : null);
      if (ref != null && ref.isNotEmpty) {
        headers['Referer'] = ref;
      }

      _addOrUpdateVideo(
        DetectedVideo(
          url: trimmedUrl,
          title: title,
          subtitles: standaloneSubtitles,
          headers: headers,
        ),
      );
    }
  }

  /// Menangani pesan dari JavaScriptChannel WebView
  void handleMessage(String rawMessage) {
    try {
      final data = jsonDecode(rawMessage) as Map<String, dynamic>;
      final type = data['type'] as String?;

      if (type == 'video_detected') {
        final video = DetectedVideo.fromJson(data);
        if (video.url.isEmpty) return;

        _addOrUpdateVideo(video);
      } else if (type == 'subtitle_detected') {
        final subtitle = DetectedSubtitle.fromJson(data);
        if (subtitle.url.isEmpty) return;

        _addSubtitle(subtitle);
      }
    } catch (e) {
      debugPrint('VideoDetectorService: error parsing message: $e');
    }
  }

  void _addOrUpdateVideo(DetectedVideo newVideo, {bool isManual = false}) {
    // 1. Filter out known ad videos (short prerolls, ad domains, ad keywords)
    if (!isManual) {
      if (newVideo.isLikelyAd || DomainUtils.isBlockedAdDomain(newVideo.url)) {
        debugPrint('VideoDetectorService: filtered out ad video: ${newVideo.url}');
        return;
      }
    }

    final currentList = List<DetectedVideo>.from(detectedVideosNotifier.value);
    final index = currentList.indexWhere((v) => v.url == newVideo.url);

    if (index >= 0) {
      // Gabungkan subtitle jika ada yang baru
      final existing = currentList[index];
      final mergedSubtitles = List<DetectedSubtitle>.from(existing.subtitles);
      for (final sub in newVideo.subtitles) {
        if (!mergedSubtitles.any((s) => s.url == sub.url)) {
          mergedSubtitles.add(sub);
        }
      }
      for (final sSub in standaloneSubtitlesNotifier.value) {
        if (!mergedSubtitles.any((s) => s.url == sSub.url)) {
          mergedSubtitles.add(sSub);
        }
      }
      currentList[index] = existing.copyWith(
        subtitles: mergedSubtitles,
        title: existing.title.isNotEmpty ? existing.title : newVideo.title,
        duration: newVideo.duration ?? existing.duration,
      );
    } else {
      // Tambahkan video baru beserta standalone subtitles yang sudah terkumpul
      final mergedSubtitles = List<DetectedSubtitle>.from(newVideo.subtitles);
      for (final sSub in standaloneSubtitlesNotifier.value) {
        if (!mergedSubtitles.any((s) => s.url == sSub.url)) {
          mergedSubtitles.add(sSub);
        }
      }
      currentList.add(newVideo.copyWith(subtitles: mergedSubtitles));
    }

    // 2. Prioritize: Sort so the real movie/series stream is ALWAYS at index 0
    currentList.sort((a, b) => b.priorityScore.compareTo(a.priorityScore));

    detectedVideosNotifier.value = currentList;
  }

  void _addSubtitle(DetectedSubtitle subtitle) {
    final currentSubs =
        List<DetectedSubtitle>.from(standaloneSubtitlesNotifier.value);
    if (!currentSubs.any((s) => s.url == subtitle.url)) {
      currentSubs.add(subtitle);
      standaloneSubtitlesNotifier.value = currentSubs;
    }

    // Pasangkan juga ke semua video yang sudah terdeteksi
    final currentVideos =
        List<DetectedVideo>.from(detectedVideosNotifier.value);
    var updated = false;
    for (var i = 0; i < currentVideos.length; i++) {
      final video = currentVideos[i];
      if (!video.subtitles.any((s) => s.url == subtitle.url)) {
        final newSubs = List<DetectedSubtitle>.from(video.subtitles)
          ..add(subtitle);
        currentVideos[i] = video.copyWith(subtitles: newSubs);
        updated = true;
      }
    }
    if (updated) {
      currentVideos.sort((a, b) => b.priorityScore.compareTo(a.priorityScore));
      detectedVideosNotifier.value = currentVideos;
    }
  }

  /// Menambahkan video manual dari input user
  void addManualVideo({
    required String url,
    String? title,
    String? subtitleUrl,
    String? subtitleLabel,
  }) {
    List<DetectedSubtitle> subs = [];
    if (subtitleUrl != null && subtitleUrl.trim().isNotEmpty) {
      subs.add(
        DetectedSubtitle(
          url: subtitleUrl.trim(),
          label: subtitleLabel ?? 'Custom Subtitle',
          lang: 'id',
        ),
      );
    }
    _addOrUpdateVideo(
      DetectedVideo(
        url: url.trim(),
        title: title ?? 'Manual Video',
        subtitles: subs,
      ),
      isManual: true,
    );
  }

  /// Script JavaScript lengkap untuk sniffing video & deteksi transisi iklan ke film
  static String getInjectionScript() {
    return '''
      (function() {
        if (window.__videoSnifferInjected) return;
        window.__videoSnifferInjected = true;

        function isAdUrl(url) {
          if (!url || typeof url !== 'string') return true;
          var u = url.toLowerCase();
          var adKeywords = [
            '/ad/', '/ads/', '/advert', 'preroll', 'pre-roll', 'midroll', 'postroll',
            'vast', 'vpaid', 'ima3', 'imasdk', 'doubleclick', 'googlesyndication',
            'popads', 'adsterra', 'propeller', 'adnxs', 'commercial', 'sponsor',
            'promo_', 'spotx', 'teads', 'outbrain', 'taboola', 'springserve',
            'videology', 'adsystem', 'adservice', 'asia9', 'sbobet', 'mposport',
            'judionline', 'monetag', 'highcpm', 'slot', 'casino', 'betting'
          ];
          for (var i = 0; i < adKeywords.length; i++) {
            if (u.indexOf(adKeywords[i]) !== -1) return true;
          }
          return false;
        }

        function isAdVideoElement(v) {
          if (!v) return true;
          // Pre-roll ads are almost always <= 75 seconds
          if (v.duration && v.duration > 0 && v.duration <= 75) return true;

          // Check if parent container has ad markers
          var p = v.closest(
            '.jw-flag-ads, .jw-ad, .vjs-ad-playing, .ad-showing, .ima-ad-container, .video-ad, [class*="ad-container"], [id*="ad-container"]'
          );
          if (p) return true;

          // Check if skip button is currently visible on screen while video is short
          var skipBtn = document.querySelector(
            '.jw-skip, .video-ads-skip, [class*="skip__btn"], [class*="skip-button"], [id*="skip"], [class*="skipBtn"]'
          );
          if (skipBtn && window.getComputedStyle(skipBtn).display !== 'none' && (v.duration && v.duration <= 90)) {
            return true;
          }

          try {
            if (window.jwplayer && typeof window.jwplayer === 'function') {
              var jw = window.jwplayer();
              if (jw && typeof jw.getAd === 'function' && jw.getAd()) return true;
              if (jw && typeof jw.getState === 'function' && jw.getState() === 'ad') return true;
            }
          } catch(e) {}

          return false;
        }

        function reportVideo(videoUrl, title, subtitles, duration) {
          if (!videoUrl || typeof videoUrl !== 'string') return;
          if (videoUrl.startsWith('blob:') || videoUrl.startsWith('data:') || videoUrl.startsWith('javascript:')) return;
          if (isAdUrl(videoUrl)) return;

          // Normalisasi URL relatif
          try {
            videoUrl = new URL(videoUrl, window.location.href).href;
          } catch(e) {}

          if (window.VideoDetectorChannel) {
            window.VideoDetectorChannel.postMessage(JSON.stringify({
              type: 'video_detected',
              videoUrl: videoUrl,
              title: title || document.title || 'Web Video',
              subtitles: subtitles || [],
              duration: (typeof duration === 'number' && !isNaN(duration) && isFinite(duration)) ? duration : null,
              headers: {
                'Referer': window.location.href
              }
            }));
          }
        }

        function reportSubtitle(subUrl, label, lang) {
          if (!subUrl || typeof subUrl !== 'string') return;
          try {
            subUrl = new URL(subUrl, window.location.href).href;
          } catch(e) {}

          if (window.VideoDetectorChannel) {
            window.VideoDetectorChannel.postMessage(JSON.stringify({
              type: 'subtitle_detected',
              url: subUrl,
              label: label || 'Subtitle',
              lang: lang || 'auto'
            }));
          }
        }

        // 1. Intercept window.fetch
        var origFetch = window.fetch;
        if (origFetch) {
          window.fetch = function(input, init) {
            try {
              var url = (typeof input === 'string') ? input : (input && input.url ? input.url : '');
              inspectUrl(url);
            } catch(e) {}
            return origFetch.apply(this, arguments);
          };
        }

        // 2. Intercept XMLHttpRequest
        var origOpen = XMLHttpRequest.prototype.open;
        XMLHttpRequest.prototype.open = function(method, url) {
          try {
            inspectUrl(url);
          } catch(e) {}
          return origOpen.apply(this, arguments);
        };

        // 3. Intercept Hls.js (jika player menggunakan Hls library)
        try {
          if (window.Hls && window.Hls.prototype && window.Hls.prototype.loadSource) {
            var origHls = window.Hls.prototype.loadSource;
            window.Hls.prototype.loadSource = function(src) {
              inspectUrl(src);
              return origHls.apply(this, arguments);
            };
          }
        } catch(e) {}

        // 4. Intercept HTMLMediaElement.src
        try {
          var origSrcDesc = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
          if (origSrcDesc && origSrcDesc.set) {
            var origSetSrc = origSrcDesc.set;
            Object.defineProperty(HTMLMediaElement.prototype, 'src', {
              configurable: true,
              enumerable: true,
              get: origSrcDesc.get,
              set: function(val) {
                try { inspectUrl(val); } catch(e) {}
                return origSetSrc.call(this, val);
              }
            });
          }
        } catch(e) {}

        function inspectUrl(url) {
          if (!url || typeof url !== 'string') return;
          if (isAdUrl(url)) return;

          var clean = url.split('?')[0].toLowerCase();

          // Deteksi file manifest HLS / MP4 / WebM (hindari segmen .ts)
          var isVideo = clean.endsWith('.m3u8') || 
                        clean.endsWith('.mp4') || 
                        clean.endsWith('.webm') || 
                        clean.endsWith('.mpd') ||
                        url.indexOf('.m3u8') !== -1 ||
                        url.indexOf('/hls/') !== -1;

          if (isVideo) {
            if (clean.indexOf('.ts') === -1 && clean.indexOf('segment') === -1 && clean.indexOf('frag') === -1 && clean.indexOf('.m4s') === -1) {
              reportVideo(url, document.title, [], null);
            }
          }

          // Deteksi subtitle WebVTT atau SRT
          var isSubtitle = clean.endsWith('.vtt') || 
                           clean.endsWith('.srt') || 
                           clean.endsWith('.sub') ||
                           url.indexOf('.vtt?') !== -1 || 
                           url.indexOf('.srt?') !== -1 ||
                           url.indexOf('/subtitles/') !== -1 ||
                           url.indexOf('/sub/') !== -1;

          if (isSubtitle) {
            var lower = url.toLowerCase();
            var label = 'Subtitle';
            var lang = 'auto';
            if (lower.indexOf('indonesia') !== -1 || lower.indexOf('_id') !== -1 || lower.indexOf('-id') !== -1 || lower.indexOf('ind') !== -1 || lower.indexOf('indo') !== -1) {
              label = 'Indonesian';
              lang = 'id';
            } else if (lower.indexOf('english') !== -1 || lower.indexOf('_en') !== -1 || lower.indexOf('-en') !== -1 || lower.indexOf('eng') !== -1) {
              label = 'English';
              lang = 'en';
            }
            reportSubtitle(url, label, lang);
          }
        }

        function hookVideoElement(v) {
          if (!v || v.__hookedForSniffer) return;
          v.__hookedForSniffer = true;

          function checkAndReport() {
            var vSrc = v.currentSrc || v.src || v.getAttribute('src');
            if (!vSrc || vSrc.startsWith('blob:') || isAdUrl(vSrc)) return;

            // Jika terindikasi iklan, lewati
            if (isAdVideoElement(v)) {
              return;
            }

            var subs = [];
            var tracks = v.querySelectorAll('track');
            for (var t = 0; t < tracks.length; t++) {
              var tr = tracks[t];
              var sUrl = tr.src || tr.getAttribute('src');
              if (sUrl) {
                subs.push({
                  url: sUrl,
                  label: tr.label || tr.srclang || 'Subtitle ' + (t + 1),
                  lang: tr.srclang || 'auto'
                });
              }
            }

            reportVideo(vSrc, document.title, subs, v.duration || null);
          }

          v.addEventListener('durationchange', checkAndReport);
          v.addEventListener('loadedmetadata', checkAndReport);
          v.addEventListener('loadeddata', checkAndReport);
          v.addEventListener('playing', checkAndReport);
          v.addEventListener('canplay', checkAndReport);

          // Saat video/iklan selesai (ended), player biasanya memuat film utama!
          v.addEventListener('ended', function() {
            setTimeout(scanMediaElements, 400);
            setTimeout(scanMediaElements, 1200);
            setTimeout(scanMediaElements, 2500);
          });

          checkAndReport();
        }

        // 5. Perbaiki izin Fullscreen untuk semua iframe di halaman
        function fixIframeFullscreen() {
          try {
            var iframes = document.querySelectorAll('iframe');
            for (var i = 0; i < iframes.length; i++) {
              var ifr = iframes[i];
              if (!ifr.hasAttribute('allowfullscreen')) {
                ifr.setAttribute('allowfullscreen', 'true');
              }
              ifr.setAttribute('webkitallowfullscreen', 'true');
              ifr.setAttribute('mozallowfullscreen', 'true');
              var currentAllow = ifr.getAttribute('allow') || '';
              if (currentAllow.indexOf('fullscreen') === -1) {
                ifr.setAttribute('allow', (currentAllow ? currentAllow + '; ' : '') + 'fullscreen; autoplay; encrypted-media; picture-in-picture');
              }
            }
          } catch(e) {}
        }

        // 6. Injeksi Kontrol In-Player (Cast & Fullscreen) Langsung di Atas Player
        function findStreamContainer() {
          return document.getElementById('embed-holder') ||
                 document.getElementById('player') ||
                 document.querySelector('.player-embed') ||
                 document.querySelector('.player-large') ||
                 document.querySelector('.play-wrapper') ||
                 document.querySelector('.embed-responsive') ||
                 document.querySelector('iframe[src*="embed"]') ||
                 document.querySelector('iframe[src*="player"]') ||
                 document.querySelector('iframe[src*="stream"]') ||
                 document.querySelector('iframe') ||
                 document.querySelector('video');
        }

        function togglePlayerFullscreen() {
          var container = findStreamContainer();
          if (!container) return;

          // Jika sedang fullscreen (HTML5 atau CSS), keluar
          if (document.fullscreenElement || document.webkitFullscreenElement || window.__isCssFullscreen) {
            if (document.exitFullscreen) {
              document.exitFullscreen().catch(function() {});
            } else if (document.webkitExitFullscreen) {
              document.webkitExitFullscreen();
            }
            exitCssFullscreen();
            return;
          }

          // Coba request fullscreen HTML5 standar
          var rfs = container.requestFullscreen || container.webkitRequestFullscreen || container.mozRequestFullScreen;
          if (rfs) {
            rfs.call(container).catch(function() {
              // Jika container ditolak, coba elemen video langsung
              try {
                var v = container.querySelector('video') || document.querySelector('video');
                if (v && (v.requestFullscreen || v.webkitEnterFullscreen)) {
                  if (v.webkitEnterFullscreen) v.webkitEnterFullscreen();
                  else v.requestFullscreen();
                  return;
                }
              } catch(err) {}
              enterCssFullscreen(container);
            });
          } else {
            enterCssFullscreen(container);
          }
        }

        function enterCssFullscreen(container) {
          window.__isCssFullscreen = true;
          container.dataset.origStyle = container.getAttribute('style') || '';
          container.style.cssText = 'position: fixed !important; top: 0 !important; left: 0 !important; width: 100vw !important; height: 100vh !important; z-index: 2147483646 !important; background: #000 !important; margin: 0 !important; padding: 0 !important; border: none !important;';
          var ifr = container.querySelector('iframe');
          if (ifr) {
            ifr.dataset.origStyle = ifr.getAttribute('style') || '';
            ifr.style.cssText = 'width: 100% !important; height: 100% !important; border: none !important;';
          }
          var fsText = document.getElementById('idlix-fs-btn-text');
          if (fsText) fsText.textContent = 'Kecilkan';
        }

        function exitCssFullscreen() {
          window.__isCssFullscreen = false;
          var container = findStreamContainer();
          if (!container) return;
          if (container.dataset.origStyle !== undefined) {
            container.style.cssText = container.dataset.origStyle;
          }
          var ifr = container.querySelector('iframe');
          if (ifr && ifr.dataset.origStyle !== undefined) {
            ifr.style.cssText = ifr.dataset.origStyle;
          }
          var fsText = document.getElementById('idlix-fs-btn-text');
          if (fsText) fsText.textContent = 'Layar Penuh';
        }

        window.__exitPlayerFullscreen = function() {
          if (window.__isCssFullscreen) {
            exitCssFullscreen();
            return true;
          }
          if (document.fullscreenElement || document.webkitFullscreenElement) {
            if (document.exitFullscreen) document.exitFullscreen().catch(function() {});
            else if (document.webkitExitFullscreen) document.webkitExitFullscreen();
            return true;
          }
          return false;
        };

        function injectInPlayerControls() {
          if (document.getElementById('idlix-inplayer-controls-bar')) return;

          var container = findStreamContainer();
          if (!container) return;

          var parent = container.parentElement || container;
          if (window.getComputedStyle(parent).position === 'static') {
            parent.style.position = 'relative';
          }

          var bar = document.createElement('div');
          bar.id = 'idlix-inplayer-controls-bar';
          bar.className = 'idlix-inplayer-controls-bar';
          bar.style.cssText = 'position: absolute; top: 12px; right: 12px; z-index: 2147483647; display: inline-flex; align-items: center; gap: 8px; user-select: none;';

          // 1. Tombol Cast
          var castBtn = document.createElement('div');
          castBtn.id = 'idlix-inplayer-cast-btn';
          castBtn.className = 'idlix-inplayer-cast-btn btn';
          castBtn.setAttribute('tabindex', '0');
          castBtn.setAttribute('role', 'button');
          castBtn.setAttribute('aria-label', 'Cast Video ke TV');
          castBtn.title = 'Cast ke TV (Chromecast & DLNA)';
          castBtn.innerHTML = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M2 16.1A5 5 0 0 1 5.9 20M2 12.05A9 9 0 0 1 9.95 20M2 8V6a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-6"></path><line x1="2" y1="20" x2="2.01" y2="20"></line></svg><span id="idlix-cast-btn-text">Cast ke TV</span>';
          castBtn.style.cssText = 'display: inline-flex; align-items: center; gap: 6px; padding: 7px 13px; background: rgba(18, 18, 18, 0.90); color: #FFFFFF; border: 1.5px solid #E50914; border-radius: 24px; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; font-size: 13px; font-weight: 600; cursor: pointer; box-shadow: 0 4px 14px rgba(0, 0, 0, 0.6), 0 0 10px rgba(229, 9, 20, 0.4); backdrop-filter: blur(8px); -webkit-backdrop-filter: blur(8px); transition: all 0.2s cubic-bezier(0.2, 0, 0, 1);';

          function triggerCast() {
            castBtn.style.transform = 'scale(0.92)';
            setTimeout(function() { castBtn.style.transform = ''; }, 120);
            if (window.VideoDetectorChannel) {
              window.VideoDetectorChannel.postMessage(JSON.stringify({ type: 'open_cast_dialog' }));
            }
          }
          castBtn.addEventListener('click', function(e) { e.stopPropagation(); e.preventDefault(); triggerCast(); });
          castBtn.addEventListener('keydown', function(e) { if (e.key === 'Enter' || e.keyCode === 13 || e.key === ' ') { e.stopPropagation(); e.preventDefault(); triggerCast(); } });

          // 2. Tombol Layar Penuh (Fullscreen)
          var fsBtn = document.createElement('div');
          fsBtn.id = 'idlix-inplayer-fs-btn';
          fsBtn.className = 'idlix-inplayer-fs-btn btn';
          fsBtn.setAttribute('tabindex', '0');
          fsBtn.setAttribute('role', 'button');
          fsBtn.setAttribute('aria-label', 'Layar Penuh');
          fsBtn.title = 'Layar Penuh (Fullscreen)';
          fsBtn.innerHTML = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M8 3H5a2 2 0 0 0-2 2v3m18 0V5a2 2 0 0 0-2-2h-3m0 18h3a2 2 0 0 0 2-2v-3M3 16v3a2 2 0 0 0 2 2h3"></path></svg><span id="idlix-fs-btn-text">Layar Penuh</span>';
          fsBtn.style.cssText = 'display: inline-flex; align-items: center; gap: 6px; padding: 7px 13px; background: rgba(18, 18, 18, 0.90); color: #FFFFFF; border: 1.5px solid #555555; border-radius: 24px; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; font-size: 13px; font-weight: 600; cursor: pointer; box-shadow: 0 4px 14px rgba(0, 0, 0, 0.6); backdrop-filter: blur(8px); -webkit-backdrop-filter: blur(8px); transition: all 0.2s cubic-bezier(0.2, 0, 0, 1);';

          function triggerFs() {
            fsBtn.style.transform = 'scale(0.92)';
            setTimeout(function() { fsBtn.style.transform = ''; }, 120);
            togglePlayerFullscreen();
          }
          fsBtn.addEventListener('click', function(e) { e.stopPropagation(); e.preventDefault(); triggerFs(); });
          fsBtn.addEventListener('keydown', function(e) { if (e.key === 'Enter' || e.keyCode === 13 || e.key === ' ') { e.stopPropagation(); e.preventDefault(); triggerFs(); } });

          bar.appendChild(castBtn);
          bar.appendChild(fsBtn);
          parent.appendChild(bar);
        }

        window.__updateCastStatus = function(isCasting) {
          var btn = document.getElementById('idlix-inplayer-cast-btn');
          var text = document.getElementById('idlix-cast-btn-text');
          if (!btn) return;
          if (isCasting) {
            btn.style.background = 'rgba(46, 125, 50, 0.92)';
            btn.style.borderColor = '#4CAF50';
            btn.style.boxShadow = '0 4px 14px rgba(0, 0, 0, 0.6), 0 0 12px rgba(76, 175, 80, 0.6)';
            if (text) text.textContent = 'Casting Aktif 📡';
          } else {
            btn.style.background = 'rgba(18, 18, 18, 0.90)';
            btn.style.borderColor = '#E50914';
            btn.style.boxShadow = '0 4px 14px rgba(0, 0, 0, 0.6), 0 0 10px rgba(229, 9, 20, 0.4)';
            if (text) text.textContent = 'Cast ke TV';
          }
        };

        // 7. Scan DOM untuk tag <video>, <source>, <track>, dan iframes
        function scanMediaElements() {
          fixIframeFullscreen();
          injectInPlayerControls();

          var videos = document.querySelectorAll('video');
          for (var i = 0; i < videos.length; i++) {
            hookVideoElement(videos[i]);
          }

          // 7. Hook dan periksa JWPlayer
          try {
            if (window.jwplayer && typeof window.jwplayer === 'function') {
              var jw = window.jwplayer();
              if (jw && jw.getPlaylist) {
                var playlist = jw.getPlaylist();
                if (playlist && playlist.length > 0) {
                  for (var p = 0; p < playlist.length; p++) {
                    var item = playlist[p];
                    var jwSubs = [];
                    if (item.tracks) {
                      for (var ti = 0; ti < item.tracks.length; ti++) {
                        var trk = item.tracks[ti];
                        if (trk.file && (trk.kind === 'captions' || trk.kind === 'subtitles')) {
                          jwSubs.push({
                            url: trk.file,
                            label: trk.label || 'Subtitle',
                            lang: trk.language || ''
                          });
                        }
                      }
                    }
                    if (item.file && !isAdUrl(item.file)) {
                      reportVideo(item.file, item.title || document.title, jwSubs, item.duration || null);
                    }
                    if (item.sources) {
                      for (var si = 0; si < item.sources.length; si++) {
                        var sFile = item.sources[si].file;
                        if (sFile && !isAdUrl(sFile)) {
                          reportVideo(sFile, item.title || document.title, jwSubs, item.duration || null);
                        }
                      }
                    }
                  }
                }
              }

              // Pasang listener event saat iklan JWPlayer selesai/di-skip
              if (jw.on && !jw.__adEventsHooked) {
                jw.__adEventsHooked = true;
                jw.on('adComplete', function() {
                  setTimeout(scanMediaElements, 500);
                  setTimeout(scanMediaElements, 1500);
                });
                jw.on('adSkipped', function() {
                  setTimeout(scanMediaElements, 500);
                  setTimeout(scanMediaElements, 1500);
                });
                jw.on('playlistItem', function() {
                  setTimeout(scanMediaElements, 500);
                });
              }
            }
          } catch(e) {}

          // 8. Periksa VideoJS
          try {
            if (window.videojs && window.videojs.getPlayers) {
              var players = window.videojs.getPlayers();
              for (var id in players) {
                var player = players[id];
                if (player && player.currentSrc) {
                  var pSrc = player.currentSrc();
                  if (pSrc && !pSrc.startsWith('blob:') && !isAdUrl(pSrc)) {
                    reportVideo(pSrc, document.title, [], player.duration ? player.duration() : null);
                  }
                }
              }
            }
          } catch(e) {}

          // 9. Periksa iframe embeds yang mengarah ke streaming/player
          try {
            var iframes = document.querySelectorAll('iframe');
            for (var ifr = 0; ifr < iframes.length; ifr++) {
              var fSrc = iframes[ifr].src || iframes[ifr].getAttribute('src');
              if (fSrc && (fSrc.indexOf('embed') !== -1 || fSrc.indexOf('player') !== -1 || fSrc.indexOf('stream') !== -1)) {
                try {
                  var doc = iframes[ifr].contentDocument || iframes[ifr].contentWindow.document;
                  if (doc) {
                    var innerVideos = doc.querySelectorAll('video');
                    for (var iv = 0; iv < innerVideos.length; iv++) {
                      hookVideoElement(innerVideos[iv]);
                    }
                  }
                } catch(crossOriginErr) {}
              }
            }
          } catch(e) {}
        }

        // 10. Deteksi klik pada tombol "Skip Ad" / "Lewati Iklan" di seluruh halaman
        document.addEventListener('click', function(e) {
          var target = e.target;
          if (!target) return;
          var btn = target.closest('button, a, div[role="button"], [class*="skip"], [id*="skip"]');
          if (btn) {
            var txt = (btn.innerText || btn.textContent || '').toLowerCase();
            var cls = (btn.className || '').toLowerCase();
            if (txt.indexOf('skip') !== -1 || txt.indexOf('lewati') !== -1 || cls.indexOf('skip') !== -1) {
              // Tombol skip diklik, scan beberapa saat kemudian saat film utama mulai memuat
              setTimeout(scanMediaElements, 400);
              setTimeout(scanMediaElements, 1000);
              setTimeout(scanMediaElements, 2200);
            }
          }
        }, true);

        // Event-driven media scanning
        document.addEventListener('play', function() {
          setTimeout(scanMediaElements, 300);
        }, true);
        document.addEventListener('loadeddata', function() {
          setTimeout(scanMediaElements, 300);
        }, true);

        // Scan berkala
        setTimeout(scanMediaElements, 1000);
        setTimeout(scanMediaElements, 2500);
        setTimeout(scanMediaElements, 5000);
      })();
    ''';
  }
}
