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
            'videology', 'adsystem', 'adservice'
          ];
          for (var i = 0; i < adKeywords.length; i++) {
            if (u.indexOf(adKeywords[i]) !== -1) return true;
          }
          return false;
        }

        function isAdVideoElement(v) {
          if (!v) return true;
          // Pre-roll ads are almost always <= 65 seconds
          if (v.duration && v.duration > 0 && v.duration <= 65) return true;

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
            if (clean.indexOf('.ts') === -1 && clean.indexOf('segment') === -1 && clean.indexOf('frag') === -1) {
              reportVideo(url, document.title, [], null);
            }
          }

          // Deteksi subtitle WebVTT atau SRT
          var isSubtitle = clean.endsWith('.vtt') || 
                           clean.endsWith('.srt') || 
                           url.indexOf('.vtt?') !== -1 || 
                           url.indexOf('.srt?') !== -1 ||
                           url.indexOf('/subtitles/') !== -1 ||
                           url.indexOf('/sub/') !== -1;

          if (isSubtitle) {
            var lower = url.toLowerCase();
            var label = 'Subtitle';
            var lang = 'auto';
            if (lower.indexOf('indonesia') !== -1 || lower.indexOf('_id') !== -1 || lower.indexOf('-id') !== -1 || lower.indexOf('ind') !== -1) {
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

        // 3. Scan DOM untuk tag <video>, <source>, <track>, dan iframes
        function scanMediaElements() {
          var videos = document.querySelectorAll('video');
          for (var i = 0; i < videos.length; i++) {
            hookVideoElement(videos[i]);
          }

          // 4. Hook dan periksa JWPlayer
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

          // 5. Periksa VideoJS
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

          // 6. Periksa iframe embeds yang mengarah ke streaming/player
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

        // 7. Deteksi klik pada tombol "Skip Ad" / "Lewati Iklan" di seluruh halaman
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

        // Scan awal
        setTimeout(scanMediaElements, 1000);
        setTimeout(scanMediaElements, 3000);
      })();
    ''';
  }
}
