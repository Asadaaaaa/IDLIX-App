import 'package:flutter/material.dart';
import 'package:webview_domain_lock/features/remote_sync/presentation/widgets/mobile_tv_remote_sheet.dart';
import 'package:webview_domain_lock/features/remote_sync/services/mobile_remote_service.dart';

/// Tombol floating di aplikasi HP untuk membuka Remote TV / Play on TV
class DraggableTvRemoteButton extends StatefulWidget {
  final MobileRemoteService remoteService;
  final String Function() getCurrentUrl;
  final String Function() getCurrentTitle;
  final VoidCallback? onCheckUpdate;

  const DraggableTvRemoteButton({
    super.key,
    required this.remoteService,
    required this.getCurrentUrl,
    required this.getCurrentTitle,
    this.onCheckUpdate,
  });

  @override
  State<DraggableTvRemoteButton> createState() => _DraggableTvRemoteButtonState();
}

class _DraggableTvRemoteButtonState extends State<DraggableTvRemoteButton> {
  Offset _position = const Offset(20, 120);

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Positioned(
      left: _position.dx.clamp(12.0, (screenSize.width - 64).clamp(12.0, double.infinity)),
      top: _position.dy.clamp(40.0, (screenSize.height - 110).clamp(40.0, double.infinity)),
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _position += details.delta;
          });
        },
        child: ValueListenableBuilder(
          valueListenable: widget.remoteService.connectedTvNotifier,
          builder: (context, tv, _) {
            final isConnected = tv != null;

            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  MobileTvRemoteSheet.show(
                    context: context,
                    remoteService: widget.remoteService,
                    currentUrl: widget.getCurrentUrl(),
                    currentTitle: widget.getCurrentTitle(),
                    onCheckUpdate: widget.onCheckUpdate,
                  );
                },
                borderRadius: BorderRadius.circular(30),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E2430).withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: isConnected ? Colors.greenAccent : Colors.white24,
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                      if (isConnected)
                        BoxShadow(
                          color: Colors.greenAccent.withValues(alpha: 0.25),
                          blurRadius: 12,
                        ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.tv_rounded,
                        color: isConnected ? Colors.greenAccent : Colors.white70,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isConnected ? 'TV Connected' : 'Remote TV',
                        style: TextStyle(
                          color: isConnected ? Colors.white : Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
