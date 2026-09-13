import 'package:webview_domain_lock/core/constants/ad_blocklist.dart';
import 'package:webview_domain_lock/core/utils/url_utils.dart';

class DomainUtils {
  /// Mengekstrak hostname dari string URL secara aman.
  static String? extractHost(String urlString) {
    if (urlString.trim().isEmpty) return null;
    final normalized = UrlUtils.normalizeUrl(urlString);
    final uri = Uri.tryParse(normalized);
    if (uri == null || uri.host.isEmpty) return null;
    return uri.host.toLowerCase().trim();
  }

  /// Memeriksa apakah URL tujuan berada dalam domain yang diizinkan (termasuk subdomain).
  /// Sesuai aturan Bagian 6 di Planning.md:
  /// uri.host == allowedHost atau uri.host.endsWith('.$allowedHost')
  static bool isAllowedDomain(String targetUrl, String allowedHost) {
    if (targetUrl.trim().isEmpty || allowedHost.trim().isEmpty) return false;

    // Pastikan skema hanya HTTP atau HTTPS
    if (!UrlUtils.isAllowedScheme(targetUrl)) {
      return false;
    }

    final uri = Uri.tryParse(targetUrl);
    if (uri == null || uri.host.isEmpty) return false;

    final targetHost = uri.host.toLowerCase().trim();
    final cleanAllowedHost = allowedHost.toLowerCase().trim();

    // Cek host utama
    if (targetHost == cleanAllowedHost) {
      return true;
    }

    // Cek subdomain (misal: sub.example.com diizinkan jika allowedHost adalah example.com)
    // Hindari bypass seperti example.com.evil.com
    if (targetHost.endsWith('.$cleanAllowedHost')) {
      return true;
    }

    return false;
  }

  /// Memeriksa apakah suatu domain/URL termasuk dalam daftar domain iklan (ad blocklist).
  /// Mendukung subdomain (misal securepubads.g.doubleclick.net -> doubleclick.net).
  static bool isBlockedAdDomain(String targetUrl) {
    if (targetUrl.trim().isEmpty) return false;

    final uri = Uri.tryParse(targetUrl);
    final host = uri?.host.toLowerCase().trim();
    if (host == null || host.isEmpty) return false;

    // Cek kata kunci domain sponsor judi / taruhan / ad network streaming
    if (host.contains('asia9') ||
        host.contains('sbobet') ||
        host.contains('mposport') ||
        host.contains('adsterra') ||
        host.contains('monetag') ||
        host.contains('highcpm') ||
        host.contains('popads') ||
        host.contains('propeller') ||
        host.contains('doubleclick') ||
        host.contains('judionline')) {
      return true;
    }

    for (final adDomain in adBlockedDomains) {
      final cleanAd = adDomain.toLowerCase().trim();
      if (host == cleanAd || host.endsWith('.$cleanAd')) {
        return true;
      }
    }

    return false;
  }
}
