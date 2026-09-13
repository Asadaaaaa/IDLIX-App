import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:webview_domain_lock/features/remote_sync/models/remote_command.dart';

/// Service penerima perintah di aplikasi IDLIX TV.
/// - Membuka local HTTP server (port 39871)
/// - Menanggapi UDP Broadcast discovery (port 39872)
class TvReceiverService {
  static const int httpPort = 39871;
  static const int udpPort = 39872;
  static const String discoveryProbe = 'DISCOVER_IDLIX_TV';
  static const String discoveryResponsePrefix = 'IDLIX_TV_DEVICE:';

  HttpServer? _httpServer;
  RawDatagramSocket? _udpSocket;

  final void Function(RemoteCommand command) onCommandReceived;

  final ValueNotifier<String?> localIpNotifier = ValueNotifier<String?>(null);
  final ValueNotifier<bool> isRunningNotifier = ValueNotifier<bool>(false);

  TvReceiverService({required this.onCommandReceived});

  Future<void> start() async {
    if (isRunningNotifier.value) return;

    try {
      // 1. Dapatkan IP LAN lokal
      final ip = await _findLocalIpAddress();
      localIpNotifier.value = ip;

      // 2. Start HTTP Server
      _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, httpPort);
      _httpServer!.listen(_handleHttpRequest);

      // 3. Start UDP Broadcast Responder
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, udpPort);
      _udpSocket!.broadcastEnabled = true;
      _udpSocket!.listen(_handleUdpEvent);

      isRunningNotifier.value = true;
      debugPrint('TvReceiverService started on $ip:$httpPort (UDP: $udpPort)');
    } catch (e) {
      debugPrint('TvReceiverService failed to start: $e');
    }
  }

  void _handleHttpRequest(HttpRequest request) async {
    // Enable CORS for flexibility
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'POST, GET, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    if (request.uri.path == '/status') {
      request.response
        ..headers.contentType = ContentType.json
        ..statusCode = HttpStatus.ok
        ..write(jsonEncode({
          'status': 'online',
          'name': 'IDLIX Android TV',
          'ip': localIpNotifier.value,
          'httpPort': httpPort,
        }));
      await request.response.close();
      return;
    }

    if (request.method == 'POST' && request.uri.path == '/command') {
      try {
        final body = await utf8.decoder.bind(request).join();
        final cmd = RemoteCommand.fromJsonString(body);
        onCommandReceived(cmd);

        request.response
          ..headers.contentType = ContentType.json
          ..statusCode = HttpStatus.ok
          ..write(jsonEncode({'success': true}));
      } catch (e) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..write(jsonEncode({'error': e.toString()}));
      }
      await request.response.close();
      return;
    }

    request.response
      ..statusCode = HttpStatus.notFound
      ..write('Not found');
    await request.response.close();
  }

  void _handleUdpEvent(RawSocketEvent event) {
    if (event == RawSocketEvent.read && _udpSocket != null) {
      final datagram = _udpSocket!.receive();
      if (datagram == null) return;

      final message = utf8.decode(datagram.data).trim();
      if (message == discoveryProbe) {
        final responseData = utf8.encode('$discoveryResponsePrefix$httpPort');
        _udpSocket!.send(responseData, datagram.address, datagram.port);
      } else if (message.startsWith('{') && message.endsWith('}')) {
        try {
          final cmd = RemoteCommand.fromJsonString(message);
          onCommandReceived(cmd);
        } catch (_) {}
      }
    }
  }

  Future<String?> _findLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (!address.isLoopback && address.type == InternetAddressType.IPv4) {
            return address.address;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  void dispose() {
    isRunningNotifier.value = false;
    _httpServer?.close(force: true);
    _httpServer = null;
    _udpSocket?.close();
    _udpSocket = null;
  }
}
