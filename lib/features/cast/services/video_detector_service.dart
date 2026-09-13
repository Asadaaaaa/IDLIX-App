import 'dart:convert';
import 'dart:io';
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

  final Set<String> _resolvedEmbedUrls = <String>{};

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
    _resolvedEmbedUrls.clear();
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

  /// Menyelesaikan URL embed iframe pihak ketiga di latar belakang (tanpa batasan CORS browser)
  /// Mengekstrak playlist master .m3u8, video .mp4, dan subtitle .vtt
  Future<void> resolveEmbedUrl(
    String embedUrl, {
    String? pageTitle,
    String? referer,
    int depth = 0,
  }) async {
    if (depth > 2 || embedUrl.trim().isEmpty) return;
    var targetUrl = embedUrl.trim();
    if (targetUrl.startsWith('//')) {
      targetUrl = 'https:$targetUrl';
    } else if (targetUrl.startsWith('/') && currentPageUrl.isNotEmpty) {
      final baseUri = Uri.tryParse(currentPageUrl);
      if (baseUri != null) {
        targetUrl = '${baseUri.scheme}://${baseUri.host}$targetUrl';
      }
    }

    final lower = targetUrl.toLowerCase();
    if (lower.startsWith('blob:') ||
        lower.startsWith('data:') ||
        lower.startsWith('javascript:') ||
        DomainUtils.isBlockedAdDomain(targetUrl)) {
      return;
    }

    if (_resolvedEmbedUrls.contains(targetUrl)) return;
    _resolvedEmbedUrls.add(targetUrl);

    try {
      final uri = Uri.tryParse(targetUrl);
      if (uri == null ||
          !uri.hasScheme ||
          (uri.scheme != 'http' && uri.scheme != 'https')) {
        return;
      }

      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 7)
        ..badCertificateCallback = (cert, host, port) => true;

      final request = await client.getUrl(uri);
      request.followRedirects = true;
      request.maxRedirects = 5;
      request.headers.set(
        'User-Agent',
        'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36',
      );
      request.headers.set(
        'Accept',
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      );
      request.headers.set(
        'Accept-Language',
        'id-ID,id;q=0.9,en-US;q=0.8,en;q=0.7',
      );
      final ref = referer ?? (currentPageUrl.isNotEmpty ? currentPageUrl : null);
      if (ref != null && ref.isNotEmpty) {
        request.headers.set('Referer', ref);
      }

      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 400) {
        client.close();
        return;
      }

      final body = await response.transform(utf8.decoder).join().catchError(
        (_) async => '',
      );
      client.close();

      if (body.isEmpty) return;

      // 1. Unpack script Dean Edwards jika ada di dalam embed player
      final unpackedBody = unpackJs(body);
      final fullText = '$body\n$unpackedBody';

      final title = (pageTitle != null && pageTitle.isNotEmpty)
          ? pageTitle
          : (currentPageTitle.isNotEmpty ? currentPageTitle : 'IDLIX Stream');

      // 2. Ekstrak Subtitle (.vtt, .srt)
      final subRegex = RegExp(
        r'''https?://[^\s"'<>]+\.(?:vtt|srt)[^\s"'<>]*''',
        caseSensitive: false,
      );
      final foundSubs = <DetectedSubtitle>[];
      for (final match in subRegex.allMatches(fullText)) {
        final subUrl = match.group(0);
        if (subUrl != null && !DomainUtils.isBlockedAdDomain(subUrl)) {
          final subLower = subUrl.toLowerCase();
          String label = 'Subtitle';
          String lang = 'auto';
          if (subLower.contains('indonesia') ||
              subLower.contains('_id') ||
              subLower.contains('-id') ||
              subLower.contains('indo')) {
            label = 'Indonesian';
            lang = 'id';
          } else if (subLower.contains('english') ||
              subLower.contains('_en') ||
              subLower.contains('-en') ||
              subLower.contains('eng')) {
            label = 'English';
            lang = 'en';
          }
          final subObj = DetectedSubtitle(url: subUrl, label: label, lang: lang);
          foundSubs.add(subObj);
          _addSubtitle(subObj);
        }
      }

      // 3. Ekstrak Stream URL (.m3u8, .mp4, /hls/)
      final streamRegex = RegExp(
        r'''https?://[^\s"'<>]+\.(?:m3u8|mp4|webm|mpd)[^\s"'<>]*|https?://[^\s"'<>]+/hls/[^\s"'<>]+''',
        caseSensitive: false,
      );

      final foundStreams = <String>{};
      for (final match in streamRegex.allMatches(fullText)) {
        final streamUrl = match.group(0);
        if (streamUrl != null &&
            !streamUrl.contains('.ts') &&
            !streamUrl.contains('.m4s') &&
            !streamUrl.contains('segment') &&
            !streamUrl.contains('frag') &&
            !DomainUtils.isBlockedAdDomain(streamUrl)) {
          foundStreams.add(streamUrl);
        }
      }

      // Cari juga format deklarasi JS: file: "https://..." atau source: "https://..."
      final fileRegex = RegExp(
        r'''(?:file|source|src)\s*:\s*["'](https?://[^"']+)["']''',
        caseSensitive: false,
      );
      for (final match in fileRegex.allMatches(fullText)) {
        final fileUrl = match.group(1);
        if (fileUrl != null &&
            (fileUrl.contains('.m3u8') ||
                fileUrl.contains('.mp4') ||
                fileUrl.contains('/hls/')) &&
            !fileUrl.contains('.ts') &&
            !fileUrl.contains('.m4s') &&
            !DomainUtils.isBlockedAdDomain(fileUrl)) {
          foundStreams.add(fileUrl);
        }
      }

      for (final sUrl in foundStreams) {
        _addOrUpdateVideo(
          DetectedVideo(
            url: sUrl,
            title: title,
            subtitles: foundSubs.isNotEmpty ? foundSubs : standaloneSubtitles,
            headers: {'Referer': targetUrl},
          ),
        );
      }

      // 4. Jika tidak ada stream yang ditemukan langsung, periksa apakah ada iframe bersarang (nested)
      if (foundStreams.isEmpty && depth < 2) {
        final iframeRegex = RegExp(
          r'''<iframe[^>]+src=["'](https?://[^"']+)["']''',
          caseSensitive: false,
        );
        for (final match in iframeRegex.allMatches(fullText)) {
          final nestedUrl = match.group(1);
          if (nestedUrl != null && !DomainUtils.isBlockedAdDomain(nestedUrl)) {
            resolveEmbedUrl(
              nestedUrl,
              pageTitle: pageTitle,
              referer: targetUrl,
              depth: depth + 1,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('VideoDetectorService: error resolving embed $targetUrl: $e');
    }
  }

  /// Unpack Dean Edwards packed JavaScript
  static String unpackJs(String code) {
    try {
      final matches = RegExp(
        r"eval\(function\(p,a,c,k,e,[rd]\)\{.+?\}\(\s*[\x27\x22](.*?)[\x27\x22]\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*[\x27\x22](.*?)[\x27\x22]\.split\([\x27\x22]\|[\x27\x22]\)",
        dotAll: true,
      ).allMatches(code);

      if (matches.isEmpty) return code;

      final sb = StringBuffer();
      for (final match in matches) {
        final p = match.group(1);
        final aStr = match.group(2);
        final kStr = match.group(4);
        if (p == null || aStr == null || kStr == null) continue;

        final a = int.tryParse(aStr) ?? 36;
        final k = kStr.split('|');

        int unbase(String str, int radix) {
          if (radix <= 36) {
            return int.tryParse(str, radix: radix) ?? -1;
          }
          int res = 0;
          for (int i = 0; i < str.length; i++) {
            final codeUnit = str.codeUnitAt(i);
            int val = -1;
            if (codeUnit >= 48 && codeUnit <= 57) {
              val = codeUnit - 48;
            } else if (codeUnit >= 97 && codeUnit <= 122) {
              val = codeUnit - 97 + 10;
            } else if (codeUnit >= 65 && codeUnit <= 90) {
              val = codeUnit - 65 + 36;
            }
            if (val < 0 || val >= radix) return -1;
            res = res * radix + val;
          }
          return res;
        }

        final unpacked = p.replaceAllMapped(RegExp(r'\b\w+\b'), (m) {
          final word = m.group(0)!;
          final idx = unbase(word, a);
          if (idx >= 0 && idx < k.length && k[idx].isNotEmpty) {
            return k[idx];
          }
          return word;
        });
        sb.writeln(unpacked);
      }
      return sb.toString();
    } catch (_) {
      return code;
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
      } else if (type == 'embed_detected') {
        final embedUrl = data['embedUrl'] as String?;
        final title = data['pageTitle'] as String?;
        final pageUrl = data['pageUrl'] as String?;
        if (embedUrl != null && embedUrl.trim().isNotEmpty) {
          resolveEmbedUrl(embedUrl.trim(), pageTitle: title, referer: pageUrl);
        }
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

  /// Script JavaScript ringan untuk injeksi seawal mungkin (onPageStarted)
  /// Mengaitkan window.fetch, XHR, ObjectURL, dan prototype setter sebelum script halaman dieksekusi
  static String getPreInjectionScript() {
    return '''
      (function() {
        if (window.__videoPreSnifferInjected) return;
        window.__videoPreSnifferInjected = true;

        window.__lastHlsSource = null;
        window.__lastVideoUrl = null;

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

        function reportVideoUrl(url) {
          if (!url || typeof url !== 'string') return;
          if (url.indexOf('blob:') === 0 || url.indexOf('data:') === 0 || url.indexOf('javascript:') === 0) return;
          if (isAdUrl(url)) return;

          var clean = url.split('?')[0].toLowerCase();
          var isVideo = clean.endsWith('.m3u8') || 
                        clean.endsWith('.mp4') || 
                        clean.endsWith('.webm') || 
                        clean.endsWith('.mpd') ||
                        url.indexOf('.m3u8') !== -1 ||
                        url.indexOf('/hls/') !== -1;

          if (isVideo) {
            if (clean.indexOf('.ts') === -1 && clean.indexOf('segment') === -1 && clean.indexOf('frag') === -1 && clean.indexOf('.m4s') === -1) {
              window.__lastHlsSource = url;
              window.__lastVideoUrl = url;
              if (window.VideoDetectorChannel) {
                window.VideoDetectorChannel.postMessage(JSON.stringify({
                  type: 'video_detected',
                  videoUrl: url,
                  title: document.title || 'IDLIX Stream',
                  subtitles: [],
                  headers: { 'Referer': window.location.href }
                }));
              }
            }
          }

          // Subtitle
          var isSub = clean.endsWith('.vtt') || clean.endsWith('.srt') || url.indexOf('.vtt?') !== -1 || url.indexOf('.srt?') !== -1;
          if (isSub && window.VideoDetectorChannel) {
            var lower = url.toLowerCase();
            var label = 'Subtitle';
            var lang = 'auto';
            if (lower.indexOf('indonesia') !== -1 || lower.indexOf('_id') !== -1 || lower.indexOf('-id') !== -1 || lower.indexOf('indo') !== -1) {
              label = 'Indonesian'; lang = 'id';
            } else if (lower.indexOf('english') !== -1 || lower.indexOf('_en') !== -1 || lower.indexOf('eng') !== -1) {
              label = 'English'; lang = 'en';
            }
            window.VideoDetectorChannel.postMessage(JSON.stringify({
              type: 'subtitle_detected',
              url: url,
              label: label,
              lang: lang
            }));
          }
        }

        // 1. Hook window.fetch
        var origFetch = window.fetch;
        if (origFetch) {
          window.fetch = function(input, init) {
            try {
              var u = (typeof input === 'string') ? input : (input && input.url ? input.url : '');
              reportVideoUrl(u);
            } catch(e) {}
            return origFetch.apply(this, arguments);
          };
        }

        // 2. Hook XMLHttpRequest
        var origOpen = XMLHttpRequest.prototype.open;
        XMLHttpRequest.prototype.open = function(method, url) {
          try { reportVideoUrl(url); } catch(e) {}
          return origOpen.apply(this, arguments);
        };

        // 3. Hook URL.createObjectURL (Dipanggil player Hls.js saat blob dipasangkan ke video)
        var origCreateObjectURL = URL.createObjectURL;
        URL.createObjectURL = function(obj) {
          var blobUrl = origCreateObjectURL.apply(this, arguments);
          try {
            if (window.__triggerFastScan) {
              setTimeout(window.__triggerFastScan, 100);
            }
          } catch(e) {}
          return blobUrl;
        };

        // 4. Hook window.postMessage antar iframe player & top window
        window.addEventListener('message', function(event) {
          try {
            if (!event.data) return;
            var data = event.data;
            if (typeof data === 'string') {
              try { data = JSON.parse(data); } catch(_) { reportVideoUrl(data); }
            }
            if (typeof data === 'object') {
              if (data.file) reportVideoUrl(data.file);
              if (data.url) reportVideoUrl(data.url);
              if (data.src) reportVideoUrl(data.src);
              if (data.source) reportVideoUrl(data.source);
            }
          } catch(e) {}
        });
      })();
    ''';
  }

  /// Script JavaScript lengkap untuk sniffing video & deteksi transisi iklan ke film
  static String getInjectionScript() {
    return '''
      (function() {
        if (window.__videoSnifferInjected) {
          if (window.__triggerFastScan) window.__triggerFastScan();
          return;
        }
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
          if (videoUrl.indexOf('blob:') === 0 || videoUrl.indexOf('data:') === 0 || videoUrl.indexOf('javascript:') === 0) return;
          if (isAdUrl(videoUrl)) return;

          // Normalisasi URL relatif
          try {
            videoUrl = new URL(videoUrl, window.location.href).href;
          } catch(e) {}

          window.__lastHlsSource = videoUrl;
          window.__lastVideoUrl = videoUrl;

          if (window.VideoDetectorChannel) {
            window.VideoDetectorChannel.postMessage(JSON.stringify({
              type: 'video_detected',
              videoUrl: videoUrl,
              title: title || document.title || 'IDLIX Stream',
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

        function reportEmbed(embedUrl) {
          if (!embedUrl || typeof embedUrl !== 'string') return;
          if (embedUrl.indexOf('about:') === 0 || embedUrl.indexOf('javascript:') === 0 || embedUrl.indexOf('blob:') === 0) return;
          if (isAdUrl(embedUrl)) return;
          try {
            embedUrl = new URL(embedUrl, window.location.href).href;
          } catch(e) {}

          if (window.VideoDetectorChannel) {
            window.VideoDetectorChannel.postMessage(JSON.stringify({
              type: 'embed_detected',
              embedUrl: embedUrl,
              pageTitle: document.title,
              pageUrl: window.location.href
            }));
          }
        }

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
                           url.indexOf('/sub/');

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

        // 1. Performance API Scanner (Mampu membaca semua request jaringan yang sudah lalu sejak halaman dibuka!)
        function scanPerformanceEntries() {
          try {
            if (window.performance && window.performance.getEntriesByType) {
              var entries = window.performance.getEntriesByType('resource');
              for (var i = 0; i < entries.length; i++) {
                inspectUrl(entries[i].name);
              }
            }
          } catch(e) {}
        }

        try {
          if (window.PerformanceObserver) {
            var po = new PerformanceObserver(function(list) {
              var entries = list.getEntries();
              for (var i = 0; i < entries.length; i++) {
                inspectUrl(entries[i].name);
              }
            });
            po.observe({ entryTypes: ['resource'] });
          }
        } catch(e) {}

        // 2. Intercept Hls.js dinamis (bahkan jika Hls dimuat belakangan)
        function hookHlsClass(hlsClass) {
          if (!hlsClass || !hlsClass.prototype || hlsClass.__hookedForDetector) return;
          hlsClass.__hookedForDetector = true;
          var origLoad = hlsClass.prototype.loadSource;
          if (origLoad) {
            hlsClass.prototype.loadSource = function(src) {
              window.__lastHlsSource = src;
              inspectUrl(src);
              return origLoad.apply(this, arguments);
            };
          }
        }
        if (window.Hls) hookHlsClass(window.Hls);

        // 3. Intercept HTMLMediaElement.src
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

        // 4. Intercept HTMLIFrameElement.src dan setAttribute
        try {
          var origIframeSrcDesc = Object.getOwnPropertyDescriptor(HTMLIFrameElement.prototype, 'src');
          if (origIframeSrcDesc && origIframeSrcDesc.set) {
            var origSetIframeSrc = origIframeSrcDesc.set;
            Object.defineProperty(HTMLIFrameElement.prototype, 'src', {
              configurable: true,
              enumerable: true,
              get: origIframeSrcDesc.get,
              set: function(val) {
                try { reportEmbed(val); } catch(e) {}
                return origSetIframeSrc.call(this, val);
              }
            });
          }
        } catch(e) {}

        function hookVideoElement(v) {
          if (!v || v.__hookedForSniffer) return;
          v.__hookedForSniffer = true;

          function checkAndReport() {
            var vSrc = v.currentSrc || v.src || v.getAttribute('src');
            if (!vSrc || isAdUrl(vSrc)) return;

            // Jika vSrc adalah blob, ambil sumber asli yang tersimpan atau scan performance API
            if (vSrc.indexOf('blob:') === 0) {
              var realSrc = v.dataset.src || v.getAttribute('data-src') || window.__lastHlsSource || window.__lastVideoUrl;
              if (realSrc && !isAdUrl(realSrc)) {
                vSrc = realSrc;
              } else {
                scanPerformanceEntries();
                return;
              }
            }

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

          // Saat video/iklan selesai (ended), player memuat film utama!
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

          if (document.fullscreenElement || document.webkitFullscreenElement || window.__isCssFullscreen) {
            if (document.exitFullscreen) {
              document.exitFullscreen().catch(function() {});
            } else if (document.webkitExitFullscreen) {
              document.webkitExitFullscreen();
            }
            exitCssFullscreen();
            return;
          }

          var rfs = container.requestFullscreen || container.webkitRequestFullscreen || container.mozRequestFullScreen;
          if (rfs) {
            rfs.call(container).catch(function() {
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
            scanMediaElements();
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

        // 7. Scan semua elemen embed, iframe, dan server buttons
        function scanEmbedElements() {
          var iframes = document.querySelectorAll('iframe');
          for (var i = 0; i < iframes.length; i++) {
            var ifr = iframes[i];
            var fSrc = ifr.src || ifr.getAttribute('src') || ifr.getAttribute('data-src') || ifr.getAttribute('data-url');
            if (fSrc) reportEmbed(fSrc);
          }

          var serverBtns = document.querySelectorAll('[data-embed], [data-src], [data-url], [data-frame], .server, .server-item, ul.servers li, [class*="server"], [id*="server"]');
          for (var b = 0; b < serverBtns.length; b++) {
            var btn = serverBtns[b];
            var bSrc = btn.getAttribute('data-embed') || btn.getAttribute('data-src') || btn.getAttribute('data-url') || btn.getAttribute('data-frame') || btn.getAttribute('data-id');
            if (bSrc && (bSrc.indexOf('http') === 0 || bSrc.indexOf('//') === 0 || bSrc.indexOf('/') === 0)) {
              reportEmbed(bSrc);
            }
          }
        }

        // 8. Scan DOM untuk tag <video>, <source>, <track>, dan iframes
        function scanMediaElements() {
          scanPerformanceEntries();
          fixIframeFullscreen();
          injectInPlayerControls();
          scanEmbedElements();

          var videos = document.querySelectorAll('video');
          for (var i = 0; i < videos.length; i++) {
            hookVideoElement(videos[i]);
          }

          // Periksa JWPlayer
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

          // Periksa VideoJS
          try {
            if (window.videojs && window.videojs.getPlayers) {
              var players = window.videojs.getPlayers();
              for (var id in players) {
                var player = players[id];
                if (player && player.currentSrc) {
                  var pSrc = player.currentSrc();
                  if (pSrc && !isAdUrl(pSrc)) {
                    if (pSrc.indexOf('blob:') === 0 && window.__lastHlsSource) {
                      pSrc = window.__lastHlsSource;
                    }
                    if (pSrc.indexOf('blob:') !== 0) {
                      reportVideo(pSrc, document.title, [], player.duration ? player.duration() : null);
                    }
                  }
                }
              }
            }
          } catch(e) {}
        }

        window.__triggerFastScan = scanMediaElements;

        // 9. Deteksi klik pada tombol "Skip Ad" / "Lewati Iklan" di seluruh halaman
        document.addEventListener('click', function(e) {
          var target = e.target;
          if (!target) return;
          var btn = target.closest('button, a, div[role="button"], [class*="skip"], [id*="skip"], .server, [data-embed]');
          if (btn) {
            setTimeout(scanMediaElements, 300);
            setTimeout(scanMediaElements, 1000);
            setTimeout(scanMediaElements, 2200);
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
        scanMediaElements();
        setTimeout(scanMediaElements, 1000);
        setTimeout(scanMediaElements, 2500);
        setTimeout(scanMediaElements, 5000);
      })();
    ''';
  }
}
