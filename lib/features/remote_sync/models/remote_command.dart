import 'dart:convert';

/// Kumpulan aksi remote yang didukung dari Mobile ke TV
enum RemoteAction {
  navigate,
  playPause,
  seekForward,
  seekRewind,
  fullscreen,
  reload,
  goBack,
  cursorMove,
  cursorClick,
  scroll,
  autoPlay,
}

/// Model pesan komando remote LAN
class RemoteCommand {
  final RemoteAction action;
  final String? url;
  final String? title;
  final double? dx;
  final double? dy;
  final bool? autoPlay;

  const RemoteCommand({
    required this.action,
    this.url,
    this.title,
    this.dx,
    this.dy,
    this.autoPlay,
  });

  Map<String, dynamic> toJson() => {
        'action': action.name,
        if (url != null) 'url': url,
        if (title != null) 'title': title,
        if (dx != null) 'dx': dx,
        if (dy != null) 'dy': dy,
        if (autoPlay != null) 'autoPlay': autoPlay,
      };

  factory RemoteCommand.fromJson(Map<String, dynamic> json) {
    final actionStr = json['action'] as String? ?? 'playPause';
    final action = RemoteAction.values.firstWhere(
      (a) => a.name == actionStr,
      orElse: () => RemoteAction.playPause,
    );
    return RemoteCommand(
      action: action,
      url: json['url'] as String?,
      title: json['title'] as String?,
      dx: (json['dx'] as num?)?.toDouble(),
      dy: (json['dy'] as num?)?.toDouble(),
      autoPlay: json['autoPlay'] as bool?,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory RemoteCommand.fromJsonString(String raw) {
    return RemoteCommand.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}
