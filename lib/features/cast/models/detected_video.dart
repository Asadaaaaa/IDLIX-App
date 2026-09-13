import 'package:webview_domain_lock/features/cast/models/detected_subtitle.dart';

class DetectedVideo {
  final String url;
  final String title;
  final List<DetectedSubtitle> subtitles;
  final Map<String, String> headers;
  final String? quality;
  final double? duration;
  final bool isAd;

  const DetectedVideo({
    required this.url,
    required this.title,
    this.subtitles = const [],
    this.headers = const {},
    this.quality,
    this.duration,
    this.isAd = false,
  });

  bool get isHls =>
      url.toLowerCase().contains('.m3u8') ||
      url.toLowerCase().contains('/hls/');

  bool get isMp4 => url.toLowerCase().contains('.mp4');

  bool get isLikelyAd {
    if (isAd) return true;
    if (duration != null && duration! > 0 && duration! <= 75) return true;
    final lower = url.toLowerCase();
    const adKeywords = [
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
      'adnxs',
      'commercial',
      'sponsor',
      'promo_',
      'spotx',
      'doubleclick',
      'googlesyndication',
      'teads',
      'outbrain',
      'taboola',
      'springserve',
      'adservice',
      'asia9',
      'sbobet',
      'mposport',
      'judionline',
      'monetag',
      'highcpm',
      'slot',
      'casino',
      'betting',
    ];
    for (final kw in adKeywords) {
      if (lower.contains(kw)) return true;
    }
    return false;
  }

  int get priorityScore {
    if (isLikelyAd) return -100;
    int score = 0;
    if (isHls) score += 40;
    if (subtitles.isNotEmpty) score += 50;
    if (duration != null && duration! > 300) {
      score += 60;
    } else if (duration != null && duration! > 60) {
      score += 20;
    }
    final lower = url.toLowerCase();
    if (lower.contains('master.m3u8') || lower.contains('playlist.m3u8')) {
      score += 30;
    }
    if (lower.contains('stream') ||
        lower.contains('embed') ||
        lower.contains('video')) {
      score += 10;
    }
    return score;
  }

  DetectedVideo copyWith({
    String? url,
    String? title,
    List<DetectedSubtitle>? subtitles,
    Map<String, String>? headers,
    String? quality,
    double? duration,
    bool? isAd,
  }) {
    return DetectedVideo(
      url: url ?? this.url,
      title: title ?? this.title,
      subtitles: subtitles ?? this.subtitles,
      headers: headers ?? this.headers,
      quality: quality ?? this.quality,
      duration: duration ?? this.duration,
      isAd: isAd ?? this.isAd,
    );
  }

  factory DetectedVideo.fromJson(Map<String, dynamic> json) {
    final rawSubs = json['subtitles'] as List<dynamic>? ?? [];
    final dur = (json['duration'] as num?)?.toDouble();
    final isAdFlag = json['isAd'] as bool? ?? false;

    return DetectedVideo(
      url: json['videoUrl'] as String? ?? json['url'] as String? ?? '',
      title: json['title'] as String? ?? 'Web Video',
      subtitles: rawSubs
          .map((e) => DetectedSubtitle.fromJson(e as Map<String, dynamic>))
          .toList(),
      headers: (json['headers'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, v.toString()),
          ) ??
          {},
      quality: json['quality'] as String?,
      duration: dur,
      isAd: isAdFlag,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DetectedVideo &&
          runtimeType == other.runtimeType &&
          url == other.url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() =>
      'DetectedVideo(title: $title, url: $url, subtitles: ${subtitles.length}, duration: $duration, isAd: $isAd)';
}
