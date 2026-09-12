import 'package:dart_cast/dart_cast.dart';
import 'package:flutter/material.dart';
import 'package:webview_domain_lock/features/cast/models/detected_video.dart';
import 'package:webview_domain_lock/features/cast/presentation/widgets/cast_modal_bottom_sheet.dart';
import 'package:webview_domain_lock/features/cast/services/cast_manager.dart';
import 'package:webview_domain_lock/features/cast/services/video_detector_service.dart';

class CastControlBar extends StatelessWidget {
  final CastManager castManager;
  final VideoDetectorService videoDetectorService;

  const CastControlBar({
    super.key,
    required this.castManager,
    required this.videoDetectorService,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CastDevice?>(
      valueListenable: castManager.activeDeviceNotifier,
      builder: (context, activeDevice, _) {
        if (activeDevice == null) return const SizedBox.shrink();

        return ValueListenableBuilder<SessionState>(
          valueListenable: castManager.sessionStateNotifier,
          builder: (context, state, _) {
            if (state == SessionState.disconnected) {
              return const SizedBox.shrink();
            }

            return ValueListenableBuilder<DetectedVideo?>(
              valueListenable: castManager.activeVideoNotifier,
              builder: (context, video, _) {
                final isPlaying = state == SessionState.playing;

                return Material(
                  elevation: 8,
                  color: const Color(0xFF161922),
                  child: InkWell(
                    onTap: () {
                      CastModalBottomSheet.show(
                        context: context,
                        videoDetectorService: videoDetectorService,
                        castManager: castManager,
                      );
                    },
                    child: SafeArea(
                      top: false,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: const BoxDecoration(
                          border: Border(
                            top: BorderSide(color: Color(0xFFE50914), width: 1.5),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.cast_connected_rounded,
                              color: Color(0xFFE50914),
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    video?.title ?? 'Casting to TV',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${activeDevice.name} (${state.name})',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.grey.shade400,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                isPlaying ? Icons.pause : Icons.play_arrow,
                                color: Colors.white,
                              ),
                              onPressed: () {
                                if (isPlaying) {
                                  castManager.pause();
                                } else {
                                  castManager.play();
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.stop,
                                color: Colors.redAccent,
                              ),
                              tooltip: 'Stop Cast',
                              onPressed: () => castManager.disconnect(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
