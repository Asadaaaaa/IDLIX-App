import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:webview_domain_lock/features/remote_sync/models/remote_command.dart';
import 'package:webview_domain_lock/features/remote_sync/services/tv_receiver_service.dart';

class DiscoveredTvDevice {
  final String ip;
  final int port;
  final String name;

  const DiscoveredTvDevice({
    required this.ip,
    required this.port,
    this.name = 'IDLIX Android TV',
  });

  String get baseUrl => 'http://$ip:$port';
}

/// Service di aplikasi Mobile untuk mendeteksi dan mengirim perintah ke TV
class MobileRemoteService {
  final ValueNotifier<DiscoveredTvDevice?> connectedTvNotifier =
      ValueNotifier<DiscoveredTvDevice?>(null);

  final ValueNotifier<bool> isSearchingNotifier = ValueNotifier<bool>(false);

  RawDatagramSocket? _udpSocket;
  Timer? _searchTimer;
  final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 3);

  DiscoveredTvDevice? get connectedTv => connectedTvNotifier.value;
  bool get isTvConnected => connectedTvNotifier.value != null;

  void startAutoDiscovery() {
    searchForTv();
    _searchTimer?.cancel();
    // Re-check periodically every 15 seconds if not connected
    _searchTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!isTvConnected) {
        searchForTv();
      }
    });
  }

  Future<void> searchForTv() async {
    if (isSearchingNotifier.value) return;
    isSearchingNotifier.value = true;

    try {
      if (_udpSocket == null) {
        _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        _udpSocket!.broadcastEnabled = true;

        _udpSocket!.listen((event) {
          if (event == RawSocketEvent.read && _udpSocket != null) {
            final datagram = _udpSocket!.receive();
            if (datagram == null) return;

            final message = utf8.decode(datagram.data).trim();
            if (message.startsWith(TvReceiverService.discoveryResponsePrefix)) {
              final portStr = message.replaceFirst(
                  TvReceiverService.discoveryResponsePrefix, '');
              final port = int.tryParse(portStr) ?? TvReceiverService.httpPort;
              final tvDevice = DiscoveredTvDevice(
                ip: datagram.address.address,
                port: port,
              );
              connectedTvNotifier.value = tvDevice;
              isSearchingNotifier.value = false;
            }
          }
        });
      }

      // Send probe to broadcast address
      final probeData = utf8.encode(TvReceiverService.discoveryProbe);
      _udpSocket!.send(
        probeData,
        InternetAddress('255.255.255.255'),
        TvReceiverService.udpPort,
      );

      // Timeout search state
      Future.delayed(const Duration(seconds: 4), () {
        if (isSearchingNotifier.value) {
          isSearchingNotifier.value = false;
        }
      });
    } catch (e) {
      debugPrint('MobileRemoteService discovery error: $e');
      isSearchingNotifier.value = false;
    }
  }

  /// Membuka link film di TV dengan auto-play otomatis
  Future<bool> playOnTv(String url, {String? title}) async {
    return sendCommand(
      RemoteCommand(
        action: RemoteAction.navigate,
        url: url,
        title: title,
        autoPlay: true,
      ),
    );
  }

  /// Mengirimkan pergerakan kursor mouse trackpad secara realtime via UDP berlatensi rendah (< 1ms)
  void sendCursorMove(double dx, double dy) {
    final tv = connectedTv;
    if (tv == null || _udpSocket == null) return;

    try {
      final cmd = RemoteCommand(
        action: RemoteAction.cursorMove,
        dx: dx,
        dy: dy,
      );
      final data = utf8.encode(cmd.toJsonString());
      _udpSocket!.send(
        data,
        InternetAddress(tv.ip),
        TvReceiverService.udpPort,
      );
    } catch (_) {}
  }

  /// Mengirimkan event klik kursor virtual via UDP dan HTTP
  void sendCursorClick() {
    final tv = connectedTv;
    if (tv == null) return;

    const cmd = RemoteCommand(action: RemoteAction.cursorClick);
    if (_udpSocket != null) {
      try {
        final data = utf8.encode(cmd.toJsonString());
        _udpSocket!.send(
          data,
          InternetAddress(tv.ip),
          TvReceiverService.udpPort,
        );
      } catch (_) {}
    }
    // Kirim juga via HTTP untuk keandalan maksimal
    sendCommand(cmd);
  }

  /// Mengirimkan event scroll vertikal via UDP
  void sendScroll(double dy) {
    final tv = connectedTv;
    if (tv == null || _udpSocket == null) return;

    try {
      final cmd = RemoteCommand(
        action: RemoteAction.scroll,
        dy: dy,
      );
      final data = utf8.encode(cmd.toJsonString());
      _udpSocket!.send(
        data,
        InternetAddress(tv.ip),
        TvReceiverService.udpPort,
      );
    } catch (_) {}
  }

  /// Mengirimkan perintah remote (fullscreen, play/pause, seek, dsb) via HTTP
  Future<bool> sendCommand(RemoteCommand command) async {
    final tv = connectedTv;
    if (tv == null) return false;

    try {
      final uri = Uri.parse('${tv.baseUrl}/command');
      final request = await _httpClient.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(command.toJsonString());

      final response = await request.close().timeout(const Duration(seconds: 4));
      return response.statusCode == HttpStatus.ok;
    } catch (e) {
      debugPrint('Error sending remote command to TV: $e');
      searchForTv();
      return false;
    }
  }

  void disconnect() {
    connectedTvNotifier.value = null;
  }

  void dispose() {
    _searchTimer?.cancel();
    _udpSocket?.close();
    _httpClient.close(force: true);
  }
}
