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
        color: Color(0xFF16181F),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: ValueListenableBuilder<DiscoveredTvDevice?>(
        valueListenable: remoteService.connectedTvNotifier,
        builder: (context, tv, _) {
          return SingleChildScrollView(
            child: Column(
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
                const SizedBox(height: 12),

                // Title & Status
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: tv != null
                            ? Colors.green.withValues(alpha: 0.15)
                            : Colors.red.withValues(alpha: 0.15),
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
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            tv != null
                                ? 'Terhubung (${tv.ip})'
                                : 'Pastikan TV & HP dalam 1 jaringan Wi-Fi',
                            style: TextStyle(
                              color: tv != null
                                  ? Colors.greenAccent.shade200
                                  : Colors.white54,
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
                const SizedBox(height: 14),

                if (tv != null) ...[
                  // Action Utama: Putar Film Ini di TV + Auto Play
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE50914),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 4,
                      ),
                      onPressed: () async {
                        final ok = await remoteService.playOnTv(
                          currentUrl,
                          title: currentTitle,
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(ok
                                  ? 'Membuka film & memutar di TV...'
                                  : 'Gagal mengirim ke TV'),
                              duration: const Duration(seconds: 2),
                              backgroundColor:
                                  ok ? Colors.green.shade800 : Colors.red.shade800,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.play_circle_filled_rounded, size: 22),
                      label: const Text(
                        'Putar Film Ini di TV (Auto-Play)',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Touchpad / Trackpad Area
                  _TvTrackpad(remoteService: remoteService),
                  const SizedBox(height: 12),

                  // Quick Action Buttons Grid (Fullscreen, Play/Pause, Seek)
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
                      const SizedBox(width: 8),
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
                      const SizedBox(width: 8),
                      Expanded(
                        child: _RemoteButton(
                          icon: Icons.play_circle_outline_rounded,
                          label: 'Force Play',
                          color: Colors.greenAccent,
                          onTap: () => remoteService.sendCommand(
                            const RemoteCommand(action: RemoteAction.autoPlay),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
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
                      const SizedBox(width: 8),
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
                      const SizedBox(width: 8),
                      Expanded(
                        child: _RemoteButton(
                          icon: Icons.arrow_back_rounded,
                          label: 'Kembali',
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
                        Icon(Icons.wifi_find_rounded,
                            color: Colors.amberAccent, size: 36),
                        SizedBox(height: 10),
                        Text(
                          'Aplikasi IDLIX TV Belum Terdeteksi',
                          style: TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
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
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: searching
                              ? null
                              : () => remoteService.searchForTv(),
                          icon: searching
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.search_rounded),
                          label: Text(searching
                              ? 'Sedang Memindai...'
                              : 'Pindai Ulang Jaringan'),
                        ),
                      );
                    },
                  ),
                ],
                const SizedBox(height: 12),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Area Touchpad / Trackpad Interaktif untuk mengontrol kursor mouse TV
class _TvTrackpad extends StatelessWidget {
  final MobileRemoteService remoteService;

  const _TvTrackpad({required this.remoteService});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF101216),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Row(
            children: [
              // Main Touchpad Area
              Expanded(
                child: GestureDetector(
                  onPanUpdate: (details) {
                    // Kalibrasi sensitivitas kursor mouse TV
                    const sensitivity = 1.6;
                    remoteService.sendCursorMove(
                      details.delta.dx * sensitivity,
                      details.delta.dy * sensitivity,
                    );
                  },
                  onTap: () {
                    remoteService.sendCursorClick();
                  },
                  child: Container(
                    height: 170,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.touch_app_rounded,
                            color: Colors.white38,
                            size: 36,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Trackpad Kursor TV',
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Geser untuk gerakkan • Ketuk untuk klik',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Scroll Strip Vertikal
              GestureDetector(
                onVerticalDragUpdate: (details) {
                  // Invert scroll delta agar natural (drag ke atas scroll halaman ke bawah)
                  remoteService.sendScroll(-details.delta.dy * 3.5);
                },
                child: Container(
                  width: 44,
                  height: 170,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Icon(Icons.arrow_drop_up_rounded,
                            color: Colors.white54, size: 22),
                      ),
                      RotatedBox(
                        quarterTurns: 3,
                        child: Text(
                          'SCROLL',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 10,
                            letterSpacing: 2,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Icon(Icons.arrow_drop_down_rounded,
                            color: Colors.white54, size: 22),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Tombol Klik Kiri Touchpad
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.09),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Colors.white12),
                ),
                elevation: 0,
              ),
              onPressed: () {
                remoteService.sendCursorClick();
              },
              icon: const Icon(Icons.mouse_rounded, size: 18, color: Colors.blueAccent),
              label: const Text(
                'Klik Kursor (Select)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
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
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
