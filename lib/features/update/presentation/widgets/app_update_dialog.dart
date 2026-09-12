import 'package:flutter/material.dart';
import 'package:webview_domain_lock/features/update/models/app_update_info.dart';
import 'package:webview_domain_lock/features/update/services/app_update_service.dart';

class AppUpdateDialog extends StatefulWidget {
  final AppUpdateInfo updateInfo;
  final bool isTv;
  final AppUpdateService updateService;

  const AppUpdateDialog({
    super.key,
    required this.updateInfo,
    required this.isTv,
    required this.updateService,
  });

  static Future<void> show({
    required BuildContext context,
    required AppUpdateInfo updateInfo,
    required bool isTv,
    required AppUpdateService updateService,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AppUpdateDialog(
        updateInfo: updateInfo,
        isTv: isTv,
        updateService: updateService,
      ),
    );
  }

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  String? _errorMessage;

  Future<void> _startUpdate() async {
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
      _progress = 0.0;
    });

    final downloadUrl = widget.isTv
        ? widget.updateInfo.tvApkUrl
        : widget.updateInfo.mobileApkUrl;

    try {
      final filePath = await widget.updateService.downloadApk(
        downloadUrl: downloadUrl,
        onProgress: (prog, rec, tot) {
          if (mounted) {
            setState(() {
              _progress = prog;
              _receivedBytes = rec;
              _totalBytes = tot;
            });
          }
        },
      );

      if (mounted) {
        final success = await widget.updateService.installApk(filePath);
        if (!success && mounted) {
          setState(() {
            _isDownloading = false;
            _errorMessage = 'Failed to open Android package installer.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = 'Failed to download update: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeRed = const Color(0xFFE50914);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 460,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF161A22),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: themeRed.withValues(alpha: 0.5), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.8),
              blurRadius: 25,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Icon & Title
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: themeRed.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: themeRed, width: 1.5),
                  ),
                  child: Icon(
                    Icons.system_update_alt_rounded,
                    color: themeRed,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Update Available!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Version ${widget.updateInfo.version} (${widget.isTv ? "IDLIX TV" : "IDLIX"})',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),
            const Divider(color: Colors.white24, height: 1),
            const SizedBox(height: 14),

            // Release Notes Box
            const Text(
              'What\'s New:',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 120),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F1218),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: SingleChildScrollView(
                child: Text(
                  widget.updateInfo.releaseNotes,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Progress or Error
            if (_isDownloading) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation<Color>(themeRed),
                  minHeight: 10,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Downloading... ${(_progress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  if (_totalBytes > 0)
                    Text(
                      '${(_receivedBytes / 1048576).toStringAsFixed(1)} MB / ${(_totalBytes / 1048576).toStringAsFixed(1)} MB',
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!_isDownloading)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Later',
                      style: TextStyle(color: Colors.white60),
                    ),
                  ),
                const SizedBox(width: 10),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeRed,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  onPressed: _isDownloading ? null : _startUpdate,
                  child: Text(
                    _isDownloading ? 'Downloading...' : 'Update Now',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
