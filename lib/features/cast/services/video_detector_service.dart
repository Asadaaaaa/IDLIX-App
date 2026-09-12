import 'dart:convert';
import 'package:flutter/foundation.dart';
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

  void _addOrUpdateVideo(DetectedVideo newVideo) {
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
    );
  }

  /// Script JavaScript lengkap untuk sniffing video (<video>, <source>, JWPlayer, XHR/Fetch, iframe)
  static String getInjectionScript() {
    return '''
      (function() {
        if (window.__videoSnifferInjected) return;
        window.__videoSnifferInjected = true;

        function reportVideo(videoUrl, title, subtitles) {
          if (!videoUrl || typeof videoUrl !== 'string') return;
          if (videoUrl.startsWith('blob:') || videoUrl.startsWith('data:') || videoUrl.startsWith('javascript:')) return;

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
          var clean = url.split('?')[0].toLowerCase();

          // Deteksi file manifest HLS / MP4 / WebM
          var isVideo = clean.endsWith('.m3u8') || 
                        clean.endsWith('.mp4') || 
                        clean.endsWith('.webm') || 
                        clean.endsWith('.mpd') ||
                        url.indexOf('.m3u8') !== -1 ||
                        url.indexOf('/hls/') !== -1;

          if (isVideo) {
            // Hindari fragmen kecil (.ts atau chunk)
            if (clean.indexOf('.ts') === -1 && clean.indexOf('segment') === -1 && clean.indexOf('frag') === -1) {
              reportVideo(url, document.title, []);
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

        // 3. Scan DOM untuk tag <video>, <source>, dan <track>
        function scanMediaElements() {
          var videos = document.querySelectorAll('video');
          for (var i = 0; i < videos.length; i++) {
            var v = videos[i];
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

            var vSrc = v.currentSrc || v.src || v.getAttribute('src');
            if (vSrc && !vSrc.startsWith('blob:')) {
              reportVideo(vSrc, document.title, subs);
            } else {
              var sources = v.querySelectorAll('source');
              for (var s = 0; s < sources.length; s++) {
                var srcUrl = sources[s].src || sources[s].getAttribute('src');
                if (srcUrl && !srcUrl.startsWith('blob:')) {
                  reportVideo(srcUrl, document.title, subs);
                }
              }
            }
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
                    if (item.file) {
                      reportVideo(item.file, item.title || document.title, jwSubs);
                    }
                    if (item.sources) {
                      for (var si = 0; si < item.sources.length; si++) {
                        if (item.sources[si].file) {
                          reportVideo(item.sources[si].file, item.title || document.title, jwSubs);
                        }
                      }
                    }
                  }
                }
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
                  if (pSrc && !pSrc.startsWith('blob:')) {
                    reportVideo(pSrc, document.title, []);
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
                // Periksa jika iframe same-origin
                try {
                  var doc = iframes[ifr].contentDocument || iframes[ifr].contentWindow.document;
                  if (doc) {
                    var innerVideos = doc.querySelectorAll('video');
                    for (var iv = 0; iv < innerVideos.length; iv++) {
                      var iSrc = innerVideos[iv].currentSrc || innerVideos[iv].src;
                      if (iSrc && !iSrc.startsWith('blob:')) {
                        reportVideo(iSrc, document.title, []);
                      }
                    }
                  }
                } catch(crossOriginErr) {}
              }
            }
          } catch(e) {}
        }

        // Event-driven media scanning: hanya scan saat media mulai dimuat atau diputar
        document.addEventListener('play', function() {
          setTimeout(scanMediaElements, 300);
        }, true);
        document.addEventListener('loadeddata', function() {
          setTimeout(scanMediaElements, 300);
        }, true);

        // Scan awal setelah halaman siap
        setTimeout(scanMediaElements, 1000);
        setTimeout(scanMediaElements, 3000);
      })();
    ''';
  }
}
