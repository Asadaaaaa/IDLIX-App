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
}

/// Model pesan komando remote LAN
class RemoteCommand {
  final RemoteAction action;
  final String? url;
  final String? title;

  const RemoteCommand({
    required this.action,
    this.url,
    this.title,
  });

  Map<String, dynamic> toJson() => {
        'action': action.name,
        if (url != null) 'url': url,
        if (title != null) 'title': title,
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
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory RemoteCommand.fromJsonString(String raw) {
    return RemoteCommand.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}
