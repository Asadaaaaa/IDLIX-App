import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_domain_lock/features/cast/models/detected_subtitle.dart';
import 'package:webview_domain_lock/features/cast/models/detected_video.dart';
import 'package:webview_domain_lock/features/cast/services/video_detector_service.dart';
import 'package:webview_domain_lock/features/webview/services/webview_navigation_service.dart';

void main() {
  group('DetectedVideo & DetectedSubtitle Model Tests', () {
    test('HLS and MP4 format detection', () {
      const hlsVideo = DetectedVideo(
        url: 'https://stream.server.com/live/moana/master.m3u8',
        title: 'Moana (2026)',
      );
      expect(hlsVideo.isHls, isTrue);
      expect(hlsVideo.isMp4, isFalse);

      const mp4Video = DetectedVideo(
        url: 'https://cdn.server.com/movies/moana.mp4',
        title: 'Moana (2026)',
      );
      expect(mp4Video.isHls, isFalse);
      expect(mp4Video.isMp4, isTrue);
    });

    test('DetectedSubtitle serialization', () {
      const sub = DetectedSubtitle(
        url: 'https://sub.server.com/indonesian.vtt',
        label: 'Indonesian',
        lang: 'id',
      );
      final json = sub.toJson();
      final fromJson = DetectedSubtitle.fromJson(json);

      expect(fromJson.url, sub.url);
      expect(fromJson.label, 'Indonesian');
      expect(fromJson.lang, 'id');
    });
  });

  group('VideoDetectorService Tests', () {
    late VideoDetectorService service;

    setUp(() {
      service = VideoDetectorService();
    });

    test('handles video_detected message and deduplicates', () {
      final msg1 = jsonEncode({
        'type': 'video_detected',
        'videoUrl': 'https://stream.server.com/master.m3u8',
        'title': 'Moana (2026)',
        'subtitles': [
          {
            'url': 'https://sub.server.com/id.vtt',
            'label': 'Indonesian',
            'lang': 'id',
          }
        ],
      });

      service.handleMessage(msg1);
      expect(service.detectedVideos.length, 1);
      expect(service.detectedVideos.first.subtitles.length, 1);
      expect(service.detectedVideos.first.subtitles.first.label, 'Indonesian');

      // Duplicate video report with an extra English subtitle
      final msg2 = jsonEncode({
        'type': 'video_detected',
        'videoUrl': 'https://stream.server.com/master.m3u8',
        'title': 'Moana (2026)',
        'subtitles': [
          {
            'url': 'https://sub.server.com/en.vtt',
            'label': 'English',
            'lang': 'en',
          }
        ],
      });

      service.handleMessage(msg2);
      expect(service.detectedVideos.length, 1); // Not duplicated
      expect(service.detectedVideos.first.subtitles.length, 2); // Merged
    });

    test('handles subtitle_detected message and attaches to existing videos', () {
      // First, a video is detected without subtitles
      service.handleMessage(jsonEncode({
        'type': 'video_detected',
        'videoUrl': 'https://stream.server.com/movie.mp4',
        'title': 'Sample Movie',
        'subtitles': [],
      }));
      expect(service.detectedVideos.first.subtitles, isEmpty);

      // Later, XHR sniffs a subtitle file
      service.handleMessage(jsonEncode({
        'type': 'subtitle_detected',
        'url': 'https://sub.server.com/bahasa.srt',
        'label': 'Indonesian',
        'lang': 'id',
      }));

      expect(service.detectedVideos.first.subtitles.length, 1);
      expect(service.detectedVideos.first.subtitles.first.label, 'Indonesian');
    });

    test('manual video addition works properly', () {
      service.addManualVideo(
        url: 'https://manual.stream/hls/master.m3u8',
        title: 'Custom Title',
        subtitleUrl: 'https://manual.stream/sub.vtt',
        subtitleLabel: 'Indonesian Sub',
      );

      expect(service.detectedVideos.length, 1);
      expect(service.detectedVideos.first.title, 'Custom Title');
      expect(service.detectedVideos.first.subtitles.length, 1);
    });

    test('clear resets video and subtitle lists', () {
      service.addManualVideo(url: 'https://test.com/vid.mp4');
      expect(service.detectedVideos.isNotEmpty, isTrue);

      service.clear();
      expect(service.detectedVideos, isEmpty);
      expect(service.standaloneSubtitles, isEmpty);
    });

    test('filters out ad videos and prerolls', () {
      // 1. Ad with ad keyword
      service.handleMessage(jsonEncode({
        'type': 'video_detected',
        'videoUrl': 'https://adserver.com/vast/preroll_ad.mp4',
        'title': 'Ad Video',
        'subtitles': [],
      }));
      expect(service.detectedVideos, isEmpty);

      // 2. Ad with short duration (e.g. 15s)
      service.handleMessage(jsonEncode({
        'type': 'video_detected',
        'videoUrl': 'https://stream.server.com/promo.mp4',
        'title': 'Promo Ad',
        'duration': 15,
        'subtitles': [],
      }));
      expect(service.detectedVideos, isEmpty);

      // 3. Ad from blocked ad domain
      service.handleMessage(jsonEncode({
        'type': 'video_detected',
        'videoUrl': 'https://doubleclick.net/media/video.mp4',
        'title': 'DoubleClick Ad',
        'subtitles': [],
      }));
      expect(service.detectedVideos, isEmpty);

      // 4. Real movie (HLS + duration 2600s + subtitles)
      service.handleMessage(jsonEncode({
        'type': 'video_detected',
        'videoUrl': 'https://stream.server.com/the-mentalist/master.m3u8',
        'title': 'The Mentalist S07E01',
        'duration': 2600,
        'subtitles': [
          {
            'url': 'https://sub.server.com/id.vtt',
            'label': 'Indonesian',
            'lang': 'id',
          }
        ],
      }));
      expect(service.detectedVideos.length, 1);
      expect(service.detectedVideos.first.title, 'The Mentalist S07E01');
      expect(service.getBestVideo()?.title, 'The Mentalist S07E01');
    });

    test('getBestVideo prioritizes full movie over secondary clips', () {
      // Clip A: short mp4 clip without subtitles
      service.handleMessage(jsonEncode({
        'type': 'video_detected',
        'videoUrl': 'https://stream.server.com/sample_preview.mp4',
        'title': 'Preview Clip',
        'duration': 95,
        'subtitles': [],
      }));

      // Clip B: full movie HLS master playlist with subtitles
      service.handleMessage(jsonEncode({
        'type': 'video_detected',
        'videoUrl': 'https://stream.server.com/the-mentalist/master.m3u8',
        'title': 'The Mentalist S07E01',
        'duration': 2600,
        'subtitles': [
          {
            'url': 'https://sub.server.com/id.vtt',
            'label': 'Indonesian',
            'lang': 'id',
          }
        ],
      }));

      final best = service.getBestVideo();
      expect(best, isNotNull);
      expect(best!.title, 'The Mentalist S07E01');
      expect(best.isHls, isTrue);
      expect(service.detectedVideos.first.title, 'The Mentalist S07E01');
    });
  });

  group('Navigation with Subframe Video Embeds', () {
    final navService = WebViewNavigationService();
    const mainHost = 'idlixku.com';

    test('allows subframes / iframes for video player embeds while blocking ads', () {
      // Subframe video player embed from streaming CDN
      expect(
        navService.shouldAllowNavigation(
          'https://stream-provider.xyz/embed/12345',
          mainHost,
          isMainFrame: false,
        ),
        isTrue,
      );

      // Subframe ad is still blocked
      expect(
        navService.shouldAllowNavigation(
          'https://doubleclick.net/ad/frame',
          mainHost,
          isMainFrame: false,
        ),
        isFalse,
      );

      // Subframe invalid scheme (e.g. intent / whatsapp) is blocked
      expect(
        navService.shouldAllowNavigation(
          'intent://stream',
          mainHost,
          isMainFrame: false,
        ),
        isFalse,
      );

      // Main frame to external domain is blocked (top-level redirect lock)
      expect(
        navService.shouldAllowNavigation(
          'https://stream-provider.xyz/page',
          mainHost,
          isMainFrame: true,
        ),
        isFalse,
      );

      // Main frame to allowed domain is allowed
      expect(
        navService.shouldAllowNavigation(
          'https://z2.idlixku.com/movie/moana-2026',
          mainHost,
          isMainFrame: true,
        ),
        isTrue,
      );
    });
  });
}
