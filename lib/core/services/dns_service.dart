import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class DnsService {
  static const String primaryDnsOverHttps = 'https://1.1.1.1/dns-query';
  static const String fallbackDnsOverHttps = 'https://cloudflare-dns.com/dns-query';
  static const String secondaryDnsIp = '1.0.0.1';

  final HttpClient _httpClient;

  DnsService({HttpClient? httpClient})
      : _httpClient = httpClient ??
            (HttpClient()..connectionTimeout = const Duration(seconds: 6));

  /// Resolve hostname using Cloudflare 1.1.1.1 DNS over HTTPS (DoH)
  /// Returns list of resolved IP addresses (A / AAAA records)
  Future<List<String>> resolveHost(String host) async {
    final cleanHost = Uri.parse(host.contains('://') ? host : 'https://$host').host;
    if (cleanHost.isEmpty) return [];

    final endpoints = [primaryDnsOverHttps, fallbackDnsOverHttps];

    for (final endpoint in endpoints) {
      try {
        final uri = Uri.parse('$endpoint?name=$cleanHost&type=A');
        final request = await _httpClient.getUrl(uri);
        request.headers.set('Accept', 'application/dns-json');
        request.headers.set('User-Agent', 'IDLIX-App/1.6.0');

        final response = await request.close().timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join();
          final data = jsonDecode(body) as Map<String, dynamic>;
          final answers = data['Answer'] as List<dynamic>?;

          if (answers != null && answers.isNotEmpty) {
            final ips = <String>[];
            for (final ans in answers) {
              if (ans is Map<String, dynamic> && ans['data'] != null) {
                ips.add(ans['data'].toString());
              }
            }
            if (ips.isNotEmpty) {
              debugPrint('DnsService: Resolved $cleanHost via 1.1.1.1 -> $ips');
              return ips;
            }
          }
        }
      } catch (e) {
        debugPrint('DnsService: Failed to resolve via $endpoint: $e');
        continue;
      }
    }

    // Standard system fallback if DoH unreachable
    try {
      final lookup = await InternetAddress.lookup(cleanHost);
      return lookup.map((e) => e.address).toList();
    } catch (_) {
      return [];
    }
  }

  /// Verifies if host resolves to an authentic IP address rather than ISP block pages
  Future<bool> verifyHostReachability(String url) async {
    try {
      final uri = Uri.parse(url);
      final resolved = await resolveHost(uri.host);
      if (resolved.isEmpty) return false;

      // Check against known Indonesian ISP redirect / Internet Baik block IPs
      const knownIspBlockIps = [
        '36.86.63.185',
        '36.86.63.182',
        '180.250.247.3',
        '118.98.96.67',
        '10.10.10.10',
        '127.0.0.1',
        '0.0.0.0',
      ];

      return !resolved.any((ip) => knownIspBlockIps.contains(ip));
    } catch (_) {
      return true;
    }
  }
}
