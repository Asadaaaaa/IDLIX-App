import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_domain_lock/features/cast/models/detected_video.dart';
import 'package:webview_domain_lock/features/cast/presentation/widgets/cast_modal_bottom_sheet.dart';
import 'package:webview_domain_lock/features/cast/services/cast_manager.dart';
import 'package:webview_domain_lock/features/cast/services/video_detector_service.dart';
import 'package:webview_domain_lock/features/tv/services/tv_remote_controller.dart';

class TvQuickMenu extends StatelessWidget {
  final TvRemoteController remoteController;
  final WebViewController Function() getController;
  final VideoDetectorService videoDetectorService;
  final CastManager castManager;
  final VoidCallback onOpenSettings;
  final VoidCallback onClose;

  const TvQuickMenu({
    super.key,
    required this.remoteController,
    required this.getController,
    required this.videoDetectorService,
    required this.castManager,
    required this.onOpenSettings,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.75),
      child: Center(
        child: Container(
          width: 520,
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1E2430),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.4)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  const Icon(Icons.settings_remote_rounded, color: Color(0xFFE50914), size: 28),
                  const SizedBox(width: 12),
                  const Text(
                    'Android TV Remote Menu',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: onClose,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(color: Colors.white24),
              const SizedBox(height: 12),

              // 1. Status Video Terdeteksi
              ValueListenableBuilder<List<DetectedVideo>>(
                valueListenable: videoDetectorService.detectedVideosNotifier,
                builder: (context, videos, _) {
                  if (videos.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  final bestVideo = videoDetectorService.getBestVideo() ?? videos.first;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE50914).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE50914).withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.movie_filter_rounded, color: Color(0xFFE50914), size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Stream: ${bestVideo.title}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                '${bestVideo.subtitles.length} Subtitles available${bestVideo.duration != null && bestVideo.duration! > 0 ? " • ${(bestVideo.duration! / 60).floor()}m" : ""}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () {
                            onClose();
                            CastModalBottomSheet.show(
                              context: context,
                              videoDetectorService: videoDetectorService,
                              castManager: castManager,
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE50914),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          icon: const Icon(Icons.cast, size: 16),
                          label: const Text('Cast / Play', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  );
                },
              ),

              // 2. TV Navigation Mode Info
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.tv_rounded,
                  color: Color(0xFFE50914),
                ),
                title: const Text(
                  'Netflix-Style Navigation',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
                subtitle: const Text(
                  'Direct element & button selection using TV Remote D-Pad (Up, Down, Left, Right, OK)',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE50914).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE50914)),
                  ),
                  child: const Text(
                    'Active',
                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ),

              // 3. Zoom Layar TV (Ukuran Teks Web)
              ValueListenableBuilder<double>(
                valueListenable: remoteController.textScaleNotifier,
                builder: (context, currentScale, _) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'TV Display & Zoom Scale',
                              style: TextStyle(color: Colors.white, fontSize: 14),
                            ),
                            Text(
                              '${(currentScale * 100).toInt()}%',
                              style: const TextStyle(
                                color: Color(0xFFE50914),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _buildScaleButton(remoteController, 1.0, '100%'),
                            const SizedBox(width: 8),
                            _buildScaleButton(remoteController, 1.25, '125% (TV)'),
                            const SizedBox(width: 8),
                            _buildScaleButton(remoteController, 1.5, '150% (Large)'),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 12),
              const Divider(color: Colors.white24),
              const SizedBox(height: 12),

              // 4. Aksi Navigasi Cepat
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildActionButton(
                    icon: Icons.refresh,
                    label: 'Reload',
                    onTap: () {
                      onClose();
                      getController().reload();
                    },
                  ),
                  _buildActionButton(
                    icon: Icons.arrow_back,
                    label: 'Back',
                    onTap: () async {
                      onClose();
                      if (await getController().canGoBack()) {
                        getController().goBack();
                      }
                    },
                  ),
                  _buildActionButton(
                    icon: Icons.arrow_forward,
                    label: 'Forward',
                    onTap: () async {
                      onClose();
                      if (await getController().canGoForward()) {
                        getController().goForward();
                      }
                    },
                  ),
                  _buildActionButton(
                    icon: Icons.sync,
                    label: 'Check Updates',
                    onTap: () {
                      onClose();
                      onOpenSettings();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScaleButton(TvRemoteController controller, double scale, String label) {
    final isSelected = (controller.textScaleNotifier.value - scale).abs() < 0.05;
    return Expanded(
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: isSelected ? Colors.blueAccent : Colors.transparent,
          foregroundColor: isSelected ? Colors.white : Colors.white70,
          side: BorderSide(
            color: isSelected ? Colors.blueAccent : Colors.white30,
          ),
          padding: const EdgeInsets.symmetric(vertical: 8),
        ),
        onPressed: () => controller.setZoom(scale),
        child: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
