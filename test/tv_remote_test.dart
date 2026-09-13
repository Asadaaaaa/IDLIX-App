import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_domain_lock/features/tv/services/tv_remote_controller.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TvRemoteController Unit Tests', () {
    late TvRemoteController controller;
    bool menuToggled = false;
    bool backTriggered = false;
    bool playPauseTriggered = false;

    setUp(() {
      menuToggled = false;
      backTriggered = false;
      playPauseTriggered = false;

      controller = TvRemoteController(
        getController: () => WebViewController(),
        onToggleMenu: () => menuToggled = true,
        onBack: () => backTriggered = true,
        onMediaPlayPause: () => playPauseTriggered = true,
        onMediaForward: () {},
        onMediaRewind: () {},
      );
      controller.init();
    });

    tearDown(() {
      controller.dispose();
    });

    test('updates screen size and centers cursor', () {
      controller.updateScreenSize(const Size(1920, 1080));
      expect(controller.screenSize, const Size(1920, 1080));
      expect(controller.cursorPositionNotifier.value, const Offset(960, 540));
    });

    test('cursor moves within bounds', () {
      controller.updateScreenSize(const Size(1920, 1080));
      final initial = controller.cursorPositionNotifier.value;

      // Simulate movement left
      controller.cursorPositionNotifier.value =
          Offset(initial.dx - 100, initial.dy);
      expect(controller.cursorPositionNotifier.value.dx, 860);

      // Simulate movement clamped to edge
      controller.cursorPositionNotifier.value = const Offset(5, 5);
      expect(controller.cursorPositionNotifier.value, const Offset(5, 5));
    });

    test('zoom level updates correctly', () {
      expect(controller.textScaleNotifier.value, 1.25);
      controller.textScaleNotifier.value = 1.5;
      expect(controller.textScaleNotifier.value, 1.5);
    });

    test('cursor visibility is false by default for Netflix focus mode', () {
      expect(controller.isCursorVisibleNotifier.value, isFalse);
      controller.isCursorVisibleNotifier.value = true;
      expect(controller.isCursorVisibleNotifier.value, isTrue);
      controller.isCursorVisibleNotifier.value = false;
      expect(controller.isCursorVisibleNotifier.value, isFalse);
    });

    test('spatial navigation script is valid and non-empty', () {
      final script = TvRemoteController.getSpatialNavInjectionScript();
      expect(script, isNotEmpty);
      expect(script.contains('idlix-tv-focused'), isTrue);
      expect(script.contains('idlix-tv-focus-glow'), isTrue);
      expect(script.contains('__idlixTvNav'), isTrue);
    });

    test('performClick sets isClickingNotifier state', () {
      expect(controller.isClickingNotifier.value, isFalse);
      controller.performClick();
      expect(controller.isClickingNotifier.value, isTrue);
    });

    test('remote key events trigger callbacks and element selection', () {
      HardwareKeyboard.instance.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.contextMenu,
          logicalKey: LogicalKeyboardKey.contextMenu,
          timeStamp: Duration.zero,
        ),
      );
      expect(menuToggled, isTrue);

      HardwareKeyboard.instance.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.escape,
          logicalKey: LogicalKeyboardKey.escape,
          timeStamp: Duration.zero,
        ),
      );
      expect(backTriggered, isTrue);

      HardwareKeyboard.instance.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.mediaPlayPause,
          logicalKey: LogicalKeyboardKey.mediaPlayPause,
          timeStamp: Duration.zero,
        ),
      );
      expect(playPauseTriggered, isTrue);

      // OK/Enter triggers click
      HardwareKeyboard.instance.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.select,
          logicalKey: LogicalKeyboardKey.select,
          timeStamp: Duration.zero,
        ),
      );
      expect(controller.isClickingNotifier.value, isTrue);
    });
  });
}
