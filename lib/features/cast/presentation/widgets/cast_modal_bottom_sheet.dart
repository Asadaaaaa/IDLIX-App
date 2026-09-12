import 'package:dart_cast/dart_cast.dart';
import 'package:flutter/material.dart';
import 'package:webview_domain_lock/features/cast/models/detected_subtitle.dart';
import 'package:webview_domain_lock/features/cast/models/detected_video.dart';
import 'package:webview_domain_lock/features/cast/services/cast_manager.dart';
import 'package:webview_domain_lock/features/cast/services/video_detector_service.dart';

class CastModalBottomSheet extends StatefulWidget {
  final VideoDetectorService videoDetectorService;
  final CastManager castManager;

  const CastModalBottomSheet({
    super.key,
    required this.videoDetectorService,
    required this.castManager,
  });

  static Future<void> show({
    required BuildContext context,
    required VideoDetectorService videoDetectorService,
    required CastManager castManager,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CastModalBottomSheet(
        videoDetectorService: videoDetectorService,
        castManager: castManager,
      ),
    );
  }

  @override
  State<CastModalBottomSheet> createState() => _CastModalBottomSheetState();
}

class _CastModalBottomSheetState extends State<CastModalBottomSheet> {
  DetectedVideo? _selectedVideo;
  DetectedSubtitle? _selectedSubtitle;
  bool _isNoneSubtitle = false;

  static const Color _bgDark = Color(0xFF10131A);
  static const Color _cardDark = Color(0xFF181C26);
  static const Color _cardBorder = Color(0xFF262E3E);
  static const Color _idlixRed = Color(0xFFE50914);

  @override
  void initState() {
    super.initState();
    final videos = widget.videoDetectorService.detectedVideos;
    if (videos.isNotEmpty) {
      _selectedVideo = widget.castManager.activeVideoNotifier.value ?? videos.first;
      _initDefaultSubtitle(_selectedVideo!);
    }
    widget.castManager.startDiscovery();
  }

  void _initDefaultSubtitle(DetectedVideo video) {
    if (video.subtitles.isNotEmpty) {
      final idSub = video.subtitles.firstWhere(
        (s) =>
            s.lang.toLowerCase() == 'id' ||
            s.label.toLowerCase().contains('indonesia') ||
            s.url.toLowerCase().contains('indonesia'),
        orElse: () => video.subtitles.first,
      );
      _selectedSubtitle = idSub;
      _isNoneSubtitle = false;
    } else {
      _selectedSubtitle = null;
      _isNoneSubtitle = true;
    }
  }

  void _showManualInputDialog() {
    final videoUrlController = TextEditingController();
    final subUrlController = TextEditingController();
    final titleController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _cardBorder),
        ),
        title: const Text(
          'Add Stream URL Manually',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Video Title (Optional)',
                  labelStyle: const TextStyle(color: Colors.white70),
                  hintText: 'Moana 2',
                  hintStyle: const TextStyle(color: Colors.white30),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: _cardBorder),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: _idlixRed),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: videoUrlController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Video Stream URL (*.m3u8 / *.mp4)',
                  labelStyle: const TextStyle(color: Colors.white70),
                  hintText: 'https://.../master.m3u8',
                  hintStyle: const TextStyle(color: Colors.white30),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: _cardBorder),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: _idlixRed),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: subUrlController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Subtitle URL (*.vtt / *.srt)',
                  labelStyle: const TextStyle(color: Colors.white70),
                  hintText: 'https://.../indonesian.vtt',
                  hintStyle: const TextStyle(color: Colors.white30),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: _cardBorder),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: _idlixRed),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _idlixRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final vUrl = videoUrlController.text.trim();
              if (vUrl.isNotEmpty) {
                final sUrl = subUrlController.text.trim();
                widget.videoDetectorService.addManualVideo(
                  url: vUrl,
                  title: titleController.text.trim().isNotEmpty
                      ? titleController.text.trim()
                      : 'Manual Stream',
                  subtitleUrl: sUrl.isNotEmpty ? sUrl : null,
                  subtitleLabel: sUrl.isNotEmpty ? 'Subtitle' : null,
                );
                final updated = widget.videoDetectorService.detectedVideos;
                if (updated.isNotEmpty) {
                  setState(() {
                    _selectedVideo = updated.last;
                    _initDefaultSubtitle(_selectedVideo!);
                  });
                }
                Navigator.of(context).pop();
              }
            },
            child: const Text('Add Stream'),
          ),
        ],
      ),
    );
  }

  Future<void> _startCast(CastDevice device) async {
    if (_selectedVideo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a video stream first')),
      );
      return;
    }

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connecting to ${device.name}...'),
          duration: const Duration(seconds: 2),
        ),
      );

      final subToUse = _isNoneSubtitle ? null : _selectedSubtitle;

      await widget.castManager.castVideo(
        video: _selectedVideo!,
        subtitle: subToUse,
        targetDevice: device,
      );

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Playing on ${device.name} ${subToUse != null ? "with Subtitle (${subToUse.label})" : ""}',
            ),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to cast: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    return Container(
      height: mediaQuery.size.height * 0.88,
      decoration: const BoxDecoration(
        color: _bgDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag Handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),

          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _idlixRed.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.cast_rounded, color: _idlixRed, size: 22),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cast Video & Subtitles',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Stream to Smart TV or Chromecast',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(color: _cardBorder, height: 1),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 1. Active Cast Controls (if currently casting)
                _buildActiveCastController(),

                // 2. Detected Video Streams
                _buildVideoSelectionSection(),
                const SizedBox(height: 16),

                // 3. Subtitles
                if (_selectedVideo != null) ...[
                  _buildSubtitleSelectionSection(),
                  const SizedBox(height: 16),
                ],

                // 4. Cast Devices
                _buildDeviceDiscoverySection(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveCastController() {
    return ValueListenableBuilder<CastDevice?>(
      valueListenable: widget.castManager.activeDeviceNotifier,
      builder: (context, activeDevice, _) {
        if (activeDevice == null) return const SizedBox.shrink();

        return ValueListenableBuilder<SessionState>(
          valueListenable: widget.castManager.sessionStateNotifier,
          builder: (context, state, _) {
            if (state == SessionState.disconnected) {
              return const SizedBox.shrink();
            }

            final isPlaying = state == SessionState.playing;

            return Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _cardDark,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _idlixRed.withValues(alpha: 0.5)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.tv_rounded, color: _idlixRed, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Casting to: ${activeDevice.name}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isPlaying ? Colors.green.shade800 : Colors.orange.shade900,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          state.name.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Progress Bar & Duration
                  ValueListenableBuilder<Duration>(
                    valueListenable: widget.castManager.positionNotifier,
                    builder: (context, pos, _) {
                      return ValueListenableBuilder<Duration>(
                        valueListenable: widget.castManager.durationNotifier,
                        builder: (context, dur, _) {
                          final maxSec = dur.inSeconds > 0 ? dur.inSeconds.toDouble() : 100.0;
                          final curSec = pos.inSeconds.toDouble().clamp(0.0, maxSec);

                          return Column(
                            children: [
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  activeTrackColor: _idlixRed,
                                  inactiveTrackColor: Colors.white12,
                                  thumbColor: _idlixRed,
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                ),
                                child: Slider(
                                  value: curSec,
                                  min: 0.0,
                                  max: maxSec,
                                  onChanged: (newSec) {
                                    widget.castManager.seek(Duration(seconds: newSec.toInt()));
                                  },
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _formatDuration(pos),
                                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                                    ),
                                    Text(
                                      _formatDuration(dur),
                                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),

                  const SizedBox(height: 12),

                  // Playback Controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.replay_10, color: Colors.white),
                        tooltip: 'Rewind 10s',
                        onPressed: () {
                          final cur = widget.castManager.positionNotifier.value;
                          final newPos = cur - const Duration(seconds: 10);
                          widget.castManager.seek(newPos.isNegative ? Duration.zero : newPos);
                        },
                      ),
                      const SizedBox(width: 12),
                      Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: _idlixRed,
                        ),
                        child: IconButton(
                          icon: Icon(
                            isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.white,
                            size: 28,
                          ),
                          onPressed: () {
                            if (isPlaying) {
                              widget.castManager.pause();
                            } else {
                              widget.castManager.play();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.forward_10, color: Colors.white),
                        tooltip: 'Forward 10s',
                        onPressed: () {
                          final cur = widget.castManager.positionNotifier.value;
                          widget.castManager.seek(cur + const Duration(seconds: 10));
                        },
                      ),
                    ],
                  ),

                  // Volume & Disconnect
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.volume_up, color: Colors.white54, size: 18),
                      Expanded(
                        child: ValueListenableBuilder<double>(
                          valueListenable: widget.castManager.volumeNotifier,
                          builder: (context, vol, _) {
                            return SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: Colors.white70,
                                inactiveTrackColor: Colors.white12,
                                thumbColor: Colors.white,
                                trackHeight: 2,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                              ),
                              child: Slider(
                                value: vol,
                                min: 0.0,
                                max: 1.0,
                                onChanged: (newVol) => widget.castManager.setVolume(newVol),
                              ),
                            );
                          },
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => widget.castManager.disconnect(),
                        icon: const Icon(Icons.stop_circle_outlined, color: Colors.redAccent, size: 16),
                        label: const Text('Disconnect', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildVideoSelectionSection() {
    return ValueListenableBuilder<List<DetectedVideo>>(
      valueListenable: widget.videoDetectorService.detectedVideosNotifier,
      builder: (context, videos, _) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _cardDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.video_library_rounded, color: _idlixRed, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Detected Streams (${videos.length})',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  TextButton.icon(
                    onPressed: _showManualInputDialog,
                    icon: const Icon(Icons.add_link, size: 16, color: _idlixRed),
                    label: const Text('Add URL', style: TextStyle(fontSize: 12, color: _idlixRed)),
                  ),
                ],
              ),
              const Divider(color: _cardBorder),
              if (videos.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.ondemand_video_rounded, size: 36, color: Colors.white24),
                        SizedBox(height: 8),
                        Text(
                          'No streams detected on this page yet.\nStart playing a video on the website or add a URL.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Column(
                  children: videos.map((v) {
                    final isSelected = _selectedVideo?.url == v.url;
                    final isHls = v.isHls;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? _idlixRed.withValues(alpha: 0.12) : const Color(0xFF131720),
                        border: Border.all(
                          color: isSelected ? _idlixRed : _cardBorder,
                          width: isSelected ? 1.5 : 1.0,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListTile(
                        onTap: () {
                          setState(() {
                            _selectedVideo = v;
                            _initDefaultSubtitle(v);
                          });
                        },
                        leading: Icon(
                          isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                          color: isSelected ? _idlixRed : Colors.white38,
                        ),
                        title: Text(
                          v.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white70,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              v.url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white38, fontSize: 11),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isHls ? Colors.purple.shade900 : Colors.teal.shade900,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    isHls ? 'HLS (.m3u8)' : 'MP4 Video',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (v.subtitles.isNotEmpty)
                                  Text(
                                    '${v.subtitles.length} Subtitles available',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.greenAccent,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSubtitleSelectionSection() {
    final video = _selectedVideo!;
    final subs = video.subtitles;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.subtitles_rounded, color: _idlixRed, size: 20),
              const SizedBox(width: 8),
              Text(
                'Subtitles (${subs.length} detected)',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const Divider(color: _cardBorder),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('No Subtitle'),
                labelStyle: TextStyle(
                  color: _isNoneSubtitle ? Colors.white : Colors.white70,
                  fontSize: 12,
                ),
                selected: _isNoneSubtitle,
                backgroundColor: const Color(0xFF131720),
                selectedColor: _idlixRed,
                side: BorderSide(color: _isNoneSubtitle ? _idlixRed : _cardBorder),
                onSelected: (selected) {
                  setState(() {
                    _isNoneSubtitle = true;
                    _selectedSubtitle = null;
                  });
                  if (widget.castManager.isCasting) {
                    widget.castManager.setSubtitle(null);
                  }
                },
              ),
              ...subs.map((s) {
                final isSelected = !_isNoneSubtitle && _selectedSubtitle?.url == s.url;
                final isIndo = s.label.toLowerCase().contains('indo') || s.lang.toLowerCase() == 'id';

                return ChoiceChip(
                  avatar: isIndo ? const Text('🇮🇩', style: TextStyle(fontSize: 12)) : null,
                  label: Text('${s.label} (${s.url.endsWith(".vtt") ? "VTT" : "SRT"})'),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 12,
                  ),
                  selected: isSelected,
                  backgroundColor: const Color(0xFF131720),
                  selectedColor: _idlixRed,
                  side: BorderSide(color: isSelected ? _idlixRed : _cardBorder),
                  onSelected: (selected) {
                    setState(() {
                      _selectedSubtitle = s;
                      _isNoneSubtitle = false;
                    });
                    if (widget.castManager.isCasting) {
                      widget.castManager.setSubtitle(s);
                    }
                  },
                );
              }),
            ],
          ),
          if (subs.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'No subtitle tracks automatically detected for this stream.',
                style: TextStyle(fontSize: 12, color: Colors.white38),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDeviceDiscoverySection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.devices_rounded, color: _idlixRed, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Select Smart TV / Cast Device',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              ValueListenableBuilder<bool>(
                valueListenable: widget.castManager.isScanningNotifier,
                builder: (context, isScanning, _) {
                  if (isScanning) {
                    return const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(_idlixRed),
                      ),
                    );
                  }
                  return IconButton(
                    icon: const Icon(Icons.refresh, size: 20, color: Colors.white70),
                    tooltip: 'Rescan',
                    onPressed: () => widget.castManager.startDiscovery(),
                  );
                },
              ),
            ],
          ),
          const Divider(color: _cardBorder),
          ValueListenableBuilder<List<CastDevice>>(
            valueListenable: widget.castManager.devicesNotifier,
            builder: (context, devices, _) {
              if (devices.isEmpty) {
                return ValueListenableBuilder<bool>(
                  valueListenable: widget.castManager.isScanningNotifier,
                  builder: (context, isScanning, _) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Column(
                          children: [
                            const Icon(Icons.wifi_find_rounded, size: 38, color: Colors.white24),
                            const SizedBox(height: 10),
                            Text(
                              isScanning
                                  ? 'Searching for Chromecast and Smart TV (DLNA) on this Wi-Fi...'
                                  : 'No devices found on this Wi-Fi network.\nPlease verify both TV and phone are on the same Wi-Fi.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12, color: Colors.white54),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              }

              return Column(
                children: devices.map((d) {
                  final isChromecast = d.protocol == CastProtocol.chromecast;
                  final isDlna = d.protocol == CastProtocol.dlna;
                  final activeDevice = widget.castManager.activeDeviceNotifier.value;
                  final isCurrentDevice = activeDevice?.id == d.id;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: isCurrentDevice ? _idlixRed.withValues(alpha: 0.12) : const Color(0xFF131720),
                      border: Border.all(
                        color: isCurrentDevice ? _idlixRed : _cardBorder,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isChromecast
                            ? Colors.blue.withValues(alpha: 0.2)
                            : Colors.orange.withValues(alpha: 0.2),
                        child: Icon(
                          isChromecast ? Icons.cast : Icons.tv,
                          color: isChromecast ? Colors.blueAccent : Colors.orangeAccent,
                        ),
                      ),
                      title: Text(
                        d.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isChromecast ? 'Google Cast' : (isDlna ? 'Smart TV (DLNA)' : 'AirPlay'),
                              style: const TextStyle(color: Colors.white70, fontSize: 10),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            d.address.address,
                            style: const TextStyle(fontSize: 11, color: Colors.white38),
                          ),
                        ],
                      ),
                      trailing: ElevatedButton.icon(
                        onPressed: () => _startCast(d),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isCurrentDevice ? Colors.green.shade700 : _idlixRed,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: Icon(
                          isCurrentDevice ? Icons.check : Icons.play_arrow,
                          size: 16,
                        ),
                        label: Text(
                          isCurrentDevice ? 'Casting' : 'Cast',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
