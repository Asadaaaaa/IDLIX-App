import 'package:flutter/material.dart';
import 'package:webview_domain_lock/features/remote_sync/models/remote_command.dart';
import 'package:webview_domain_lock/features/remote_sync/services/mobile_remote_service.dart';

class MobileTvRemoteSheet extends StatelessWidget {
  final MobileRemoteService remoteService;
  final String currentUrl;
  final String currentTitle;

  const MobileTvRemoteSheet({
    super.key,
    required this.remoteService,
    required this.currentUrl,
    required this.currentTitle,
  });

  static void show({
    required BuildContext context,
    required MobileRemoteService remoteService,
    required String currentUrl,
    required String currentTitle,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => MobileTvRemoteSheet(
        remoteService: remoteService,
        currentUrl: currentUrl,
        currentTitle: currentTitle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF181A20),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: ValueListenableBuilder<DiscoveredTvDevice?>(
        valueListenable: remoteService.connectedTvNotifier,
        builder: (context, tv, _) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              // Title & Status
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: tv != null ? Colors.green.withValues(alpha: 0.15) : Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.tv_rounded,
                      color: tv != null ? Colors.greenAccent : Colors.redAccent,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tv != null ? tv.name : 'Mencari IDLIX TV...',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          tv != null
                              ? 'Terhubung (${tv.ip})'
                              : 'Pastikan TV & HP dalam 1 jaringan Wi-Fi',
                          style: TextStyle(
                            color: tv != null ? Colors.greenAccent.shade200 : Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => remoteService.searchForTv(),
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
                    tooltip: 'Cari Ulang TV',
                  ),
                ],
              ),
              const SizedBox(height: 20),

              if (tv != null) ...[
                // Action: Putar Halaman Ini di TV
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE50914),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 4,
                    ),
                    onPressed: () async {
                      final ok = await remoteService.playOnTv(currentUrl, title: currentTitle);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(ok ? 'Membuka film di TV...' : 'Gagal mengirim ke TV'),
                            duration: const Duration(seconds: 2),
                            backgroundColor: ok ? Colors.green.shade800 : Colors.red.shade800,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.play_circle_filled_rounded, size: 22),
                    label: const Text(
                      'Putar Film Ini di TV',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                const Divider(color: Colors.white12),
                const SizedBox(height: 12),

                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Kontrol Remote TV',
                    style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 12),

                // Controls Grid
                Row(
                  children: [
                    Expanded(
                      child: _RemoteButton(
                        icon: Icons.fullscreen_rounded,
                        label: 'Layar Penuh',
                        color: Colors.amberAccent,
                        onTap: () => remoteService.sendCommand(
                          const RemoteCommand(action: RemoteAction.fullscreen),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _RemoteButton(
                        icon: Icons.play_arrow_rounded,
                        label: 'Play / Pause',
                        color: Colors.blueAccent,
                        onTap: () => remoteService.sendCommand(
                          const RemoteCommand(action: RemoteAction.playPause),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _RemoteButton(
                        icon: Icons.replay_10_rounded,
                        label: 'Mundur 10s',
                        color: Colors.white70,
                        onTap: () => remoteService.sendCommand(
                          const RemoteCommand(action: RemoteAction.seekRewind),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _RemoteButton(
                        icon: Icons.forward_10_rounded,
                        label: 'Maju 10s',
                        color: Colors.white70,
                        onTap: () => remoteService.sendCommand(
                          const RemoteCommand(action: RemoteAction.seekForward),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _RemoteButton(
                        icon: Icons.refresh_rounded,
                        label: 'Reload TV',
                        color: Colors.white70,
                        onTap: () => remoteService.sendCommand(
                          const RemoteCommand(action: RemoteAction.reload),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _RemoteButton(
                        icon: Icons.arrow_back_rounded,
                        label: 'Kembali di TV',
                        color: Colors.white70,
                        onTap: () => remoteService.sendCommand(
                          const RemoteCommand(action: RemoteAction.goBack),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    children: const [
                      Icon(Icons.wifi_find_rounded, color: Colors.amberAccent, size: 36),
                      SizedBox(height: 10),
                      Text(
                        'Aplikasi IDLIX TV Belum Terdeteksi',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 6),
                      Text(
                        '1. Buka aplikasi IDLIX TV di Smart TV / STB Anda.\n2. Pastikan HP dan TV tersambung ke jaringan Wi-Fi yang sama.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ValueListenableBuilder<bool>(
                  valueListenable: remoteService.isSearchingNotifier,
                  builder: (context, searching, _) {
                    return SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white12,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: searching ? null : () => remoteService.searchForTv(),
                        icon: searching
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.search_rounded),
                        label: Text(searching ? 'Sedang Memindai...' : 'Pindai Ulang Jaringan'),
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 12),
            ],
          );
        },
      ),
    );
  }
}

class _RemoteButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _RemoteButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
