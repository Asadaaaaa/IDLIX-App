import 'package:flutter_test/flutter_test.dart';
import 'package:webview_domain_lock/features/remote_sync/models/remote_command.dart';

void main() {
  group('RemoteCommand Model Tests', () {
    test('serializes and deserializes navigate command with autoPlay', () {
      const cmd = RemoteCommand(
        action: RemoteAction.navigate,
        url: 'https://z2.idlixku.com/movie/moana-2026',
        title: 'Moana (2026)',
        autoPlay: true,
      );

      final jsonStr = cmd.toJsonString();
      final decoded = RemoteCommand.fromJsonString(jsonStr);

      expect(decoded.action, RemoteAction.navigate);
      expect(decoded.url, 'https://z2.idlixku.com/movie/moana-2026');
      expect(decoded.title, 'Moana (2026)');
      expect(decoded.autoPlay, isTrue);
    });

    test('serializes and deserializes cursorMove and scroll commands', () {
      const moveCmd = RemoteCommand(
        action: RemoteAction.cursorMove,
        dx: 12.5,
        dy: -8.0,
      );

      final moveJson = moveCmd.toJsonString();
      final decodedMove = RemoteCommand.fromJsonString(moveJson);

      expect(decodedMove.action, RemoteAction.cursorMove);
      expect(decodedMove.dx, 12.5);
      expect(decodedMove.dy, -8.0);

      const scrollCmd = RemoteCommand(
        action: RemoteAction.scroll,
        dy: 150.0,
      );
      final scrollJson = scrollCmd.toJsonString();
      final decodedScroll = RemoteCommand.fromJsonString(scrollJson);

      expect(decodedScroll.action, RemoteAction.scroll);
      expect(decodedScroll.dy, 150.0);
    });

    test('serializes and deserializes fullscreen and control actions', () {
      const actions = [
        RemoteAction.fullscreen,
        RemoteAction.playPause,
        RemoteAction.seekForward,
        RemoteAction.seekRewind,
        RemoteAction.reload,
        RemoteAction.goBack,
        RemoteAction.cursorClick,
        RemoteAction.autoPlay,
      ];

      for (final action in actions) {
        final cmd = RemoteCommand(action: action);
        final jsonStr = cmd.toJsonString();
        final decoded = RemoteCommand.fromJsonString(jsonStr);
        expect(decoded.action, action);
      }
    });

    test('handles fallback defaults on unknown action', () {
      final json = {'action': 'unknownAction'};
      final decoded = RemoteCommand.fromJson(json);
      expect(decoded.action, RemoteAction.playPause);
    });
  });
}
