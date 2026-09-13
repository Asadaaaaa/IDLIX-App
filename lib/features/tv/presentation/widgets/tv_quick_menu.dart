import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_domain_lock/features/remote_sync/services/tv_receiver_service.dart';
import 'package:webview_domain_lock/features/tv/services/tv_remote_controller.dart';

class TvQuickMenu extends StatelessWidget {
  final TvRemoteController remoteController;
  final WebViewController Function() getController;
  final TvReceiverService? tvReceiverService;
  final VoidCallback onOpenSettings;
  final VoidCallback onClose;

  const TvQuickMenu({
    super.key,
    required this.remoteController,
    required this.getController,
    this.tvReceiverService,
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
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 1. LAN Companion Status
              if (tvReceiverService != null)
                ValueListenableBuilder<String?>(
                  valueListenable: tvReceiverService!.localIpNotifier,
                  builder: (context, ip, _) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.wifi_tethering_rounded, color: Colors.greenAccent, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'LAN Remote Receiver: Aktif',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  ip != null
                                      ? 'Buka IDLIX di HP (1 WiFi) untuk kontrol & putar film langsung (IP: $ip)'
                                      : 'Menunggu koneksi Wi-Fi lokal...',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
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
                              'Display Zoom / Text Scale',
                              style: TextStyle(color: Colors.white, fontSize: 14),
                            ),
                            Text(
                              '${(currentScale * 100).toInt()}%',
                              style: const TextStyle(
                                color: Colors.blueAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  final newScale = (currentScale - 0.1).clamp(0.8, 2.0);
                                  remoteController.textScaleNotifier.value = newScale;
                                  getController().runJavaScript(
                                    "document.body.style.zoom = '$newScale';",
                                  );
                                },
                                icon: const Icon(Icons.zoom_out, size: 16),
                                label: const Text('Smaller'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white10,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  final newScale = (currentScale + 0.1).clamp(0.8, 2.0);
                                  remoteController.textScaleNotifier.value = newScale;
                                  getController().runJavaScript(
                                    "document.body.style.zoom = '$newScale';",
                                  );
                                },
                                icon: const Icon(Icons.zoom_in, size: 16),
                                label: const Text('Larger'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white10,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),

              const Divider(color: Colors.white12, height: 24),

              // 4. Quick Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      onClose();
                      getController().reload();
                    },
                    icon: const Icon(Icons.refresh, color: Colors.white70),
                    label: const Text('Reload Page', style: TextStyle(color: Colors.white70)),
                  ),
                  ElevatedButton.icon(
                    onPressed: onClose,
                    icon: const Icon(Icons.check),
                    label: const Text('Done'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE50914),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
