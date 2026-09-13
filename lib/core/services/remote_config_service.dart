import 'dart:convert';
import 'dart:io';
import 'package:webview_domain_lock/core/services/storage_service.dart';
import 'package:webview_domain_lock/core/utils/domain_utils.dart';
import 'package:webview_domain_lock/core/utils/url_utils.dart';
import 'package:webview_domain_lock/features/webview/models/webview_config.dart';

class RemoteConfigService {
  static const List<String> configEndpoints = [
    'https://raw.githubusercontent.com/Asadaaaaa/IDLIX-App/main/config.json',
    'https://cdn.jsdelivr.net/gh/Asadaaaaa/IDLIX-App@main/config.json',
  ];

  static const String defaultFallbackUrl = 'https://z2.idlixku.com';
  static const String defaultFallbackHost = 'idlixku.com';

  final StorageService storageService;
  final HttpClient _httpClient;

  RemoteConfigService(this.storageService, {HttpClient? httpClient})
      : _httpClient = httpClient ??
            (HttpClient()..connectionTimeout = const Duration(seconds: 8));

  /// Mendapatkan konfigurasi dari cache storage jika ada, atau menggunakan default fallback.
  WebViewConfig getCachedOrDefaultConfig() {
    if (storageService.hasSavedConfig()) {
      final url = storageService.getMainUrl()!;
      final host = storageService.getAllowedHost()!;
      return WebViewConfig(
        mainUrl: UrlUtils.normalizeUrl(url),
        allowedHost: host,
      );
    }
    return const WebViewConfig(
      mainUrl: defaultFallbackUrl,
      allowedHost: defaultFallbackHost,
    );
  }

  /// Mengambil konfigurasi JSON terbaru dari GitHub raw.
  /// Menyimpan konfigurasi baru ke storage jika berhasil dan mengembalikan WebViewConfig.
  Future<WebViewConfig> fetchLatestConfig() async {
    for (final endpoint in configEndpoints) {
      try {
        final cacheBuster = DateTime.now().millisecondsSinceEpoch;
        final separator = endpoint.contains('?') ? '&' : '?';
        final uri = Uri.parse('$endpoint${separator}_t=$cacheBuster');
        final request = await _httpClient.getUrl(uri);
        request.headers.set('User-Agent', 'IDLIX-App/2.1.0');
        request.headers.set('Cache-Control', 'no-cache, no-store, must-revalidate');
        request.headers.set('Pragma', 'no-cache');

        final response = await request.close().timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join();
          final data = jsonDecode(body) as Map<String, dynamic>;

          final rawUrl = (data['url'] ?? data['main_url'])?.toString().trim();
          if (rawUrl != null && rawUrl.isNotEmpty && UrlUtils.isValidUrl(rawUrl)) {
            final normalizedUrl = UrlUtils.normalizeUrl(rawUrl);

            // Jika allowed_host ditentukan di JSON, gunakan itu; jika tidak, ekstrak dari domain URL
            String allowedHost = (data['allowed_host'] ?? data['host'])?.toString().trim() ?? '';
            if (allowedHost.isEmpty) {
              final extracted = DomainUtils.extractHost(normalizedUrl);
              if (extracted != null) {
                // Jika domain memiliki subdomain (cth z2.idlixku.com), ambil root domain (idlixku.com) jika mungkin
                final parts = extracted.split('.');
                if (parts.length >= 2) {
                  allowedHost = '${parts[parts.length - 2]}.${parts[parts.length - 1]}';
                } else {
                  allowedHost = extracted;
                }
              } else {
                allowedHost = defaultFallbackHost;
              }
            }

            final config = WebViewConfig(
              mainUrl: normalizedUrl,
              allowedHost: allowedHost.toLowerCase(),
            );

            // Simpan ke storage lokal
            await storageService.saveConfig(
              mainUrl: config.mainUrl,
              allowedHost: config.allowedHost,
            );

            return config;
          }
        }
      } catch (_) {
        // Coba endpoint cadangan berikutnya
        continue;
      }
    }

    // Jika gagal terhubung ke semua endpoint GitHub, gunakan cache atau fallback
    return getCachedOrDefaultConfig();
  }
}
