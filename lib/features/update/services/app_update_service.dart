import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:webview_domain_lock/core/services/remote_config_service.dart';
import 'package:webview_domain_lock/features/update/models/app_update_info.dart';

class AppUpdateService {
  static const String currentVersion = '1.6.0';
  static const int currentVersionCode = 16;

  static const MethodChannel _channel = MethodChannel('com.idlix.app/installer');
  final HttpClient _httpClient;

  AppUpdateService({HttpClient? httpClient})
      : _httpClient = httpClient ?? (HttpClient()..connectionTimeout = const Duration(seconds: 10));

  /// Memeriksa ke file config.json di GitHub apakah ada versi baru
  Future<AppUpdateInfo?> checkForUpdate() async {
    for (final endpoint in RemoteConfigService.configEndpoints) {
      try {
        final uri = Uri.parse(endpoint);
        final request = await _httpClient.getUrl(uri);
        request.headers.set('User-Agent', 'IDLIX-App/$currentVersion');
        request.headers.set('Cache-Control', 'no-cache');

        final response = await request.close().timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join();
          final data = jsonDecode(body) as Map<String, dynamic>;

          final info = AppUpdateInfo.fromJson(data);
          if (info.versionCode > currentVersionCode ||
              (info.version.isNotEmpty && info.version != currentVersion && _isNewerVersion(info.version, currentVersion))) {
            return info;
          }
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  bool _isNewerVersion(String remote, String current) {
    try {
      final rParts = remote.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final cParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      for (int i = 0; i < rParts.length && i < cParts.length; i++) {
        if (rParts[i] > cParts[i]) return true;
        if (rParts[i] < cParts[i]) return false;
      }
      return rParts.length > cParts.length;
    } catch (_) {
      return false;
    }
  }

  /// Mengunduh APK dari GitHub Releases secara in-app dengan progress callback
  Future<String> downloadApk({
    required String downloadUrl,
    required Function(double progress, int receivedBytes, int totalBytes) onProgress,
  }) async {
    final cacheDir = await _channel.invokeMethod<String>('getCacheDir') ?? '/data/user/0/com.idlix.app/cache';
    final targetFile = File('$cacheDir/idlix_update.apk');
    if (await targetFile.exists()) {
      await targetFile.delete();
    }

    final request = await _httpClient.getUrl(Uri.parse(downloadUrl));
    request.headers.set('User-Agent', 'IDLIX-App/$currentVersion');
    final response = await request.close();

    if (response.statusCode != 200 && response.statusCode != 302) {
      throw HttpException('Failed to download APK: status ${response.statusCode}');
    }

    // Tangani redirect GitHub releases (302)
    HttpClientResponse finalResponse = response;
    if (response.statusCode == 302 || response.statusCode == 301) {
      final redirectUrl = response.headers.value(HttpHeaders.locationHeader);
      if (redirectUrl != null) {
        final redirReq = await _httpClient.getUrl(Uri.parse(redirectUrl));
        finalResponse = await redirReq.close();
      }
    }

    final totalBytes = finalResponse.contentLength;
    int receivedBytes = 0;
    final sink = targetFile.openWrite();

    await for (final chunk in finalResponse) {
      sink.add(chunk);
      receivedBytes += chunk.length;
      final progress = totalBytes > 0 ? (receivedBytes / totalBytes) : 0.0;
      onProgress(progress, receivedBytes, totalBytes);
    }

    await sink.flush();
    await sink.close();

    return targetFile.path;
  }

  /// Memanggil intent installer native Android
  Future<bool> installApk(String filePath) async {
    try {
      final result = await _channel.invokeMethod<bool>('installApk', {'filePath': filePath});
      return result ?? false;
    } catch (e) {
      return false;
    }
  }
}
