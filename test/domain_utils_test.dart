import 'package:flutter_test/flutter_test.dart';
import 'package:webview_domain_lock/core/utils/domain_utils.dart';
import 'package:webview_domain_lock/core/utils/url_utils.dart';
import 'package:webview_domain_lock/features/webview/services/webview_navigation_service.dart';

void main() {
  group('UrlUtils Tests', () {
    test('normalizeUrl should prepend https:// if missing', () {
      expect(UrlUtils.normalizeUrl('example.com'), 'https://example.com');
      expect(UrlUtils.normalizeUrl('www.example.com'), 'https://www.example.com');
      expect(UrlUtils.normalizeUrl('http://example.com'), 'http://example.com');
      expect(UrlUtils.normalizeUrl('https://example.com'), 'https://example.com');
      expect(UrlUtils.normalizeUrl('whatsapp://send?phone=123'), 'whatsapp://send?phone=123');
    });

    test('isValidUrl should validate standard URLs', () {
      expect(UrlUtils.isValidUrl('https://example.com'), isTrue);
      expect(UrlUtils.isValidUrl('http://example.com'), isTrue);
      expect(UrlUtils.isValidUrl('https://www.example.com/path?query=1'), isTrue);
      expect(UrlUtils.isValidUrl('example.com'), isTrue); // normalizes to https://
      expect(UrlUtils.isValidUrl(''), isFalse);
      expect(UrlUtils.isValidUrl('not a url'), isFalse);
      expect(UrlUtils.isValidUrl('whatsapp://send'), isFalse);
      expect(UrlUtils.isValidUrl('intent://something'), isFalse);
    });

    test('isAllowedScheme should only allow http and https', () {
      expect(UrlUtils.isAllowedScheme('https://example.com'), isTrue);
      expect(UrlUtils.isAllowedScheme('http://example.com'), isTrue);
      expect(UrlUtils.isAllowedScheme('intent://scan'), isFalse);
      expect(UrlUtils.isAllowedScheme('market://details?id=com.app'), isFalse);
      expect(UrlUtils.isAllowedScheme('whatsapp://send?phone=123'), isFalse);
      expect(UrlUtils.isAllowedScheme('tg://resolve'), isFalse);
      expect(UrlUtils.isAllowedScheme('mailto:test@example.com'), isFalse);
      expect(UrlUtils.isAllowedScheme('tel:123456'), isFalse);
    });
  });

  group('DomainUtils Tests', () {
    test('extractHost extracts lowercase host correctly', () {
      expect(DomainUtils.extractHost('https://Example.COM/test'), 'example.com');
      expect(DomainUtils.extractHost('sub.domain.org/path'), 'sub.domain.org');
    });

    test('isAllowedDomain allows exact host and subdomains', () {
      const allowed = 'example.com';
      expect(DomainUtils.isAllowedDomain('https://example.com', allowed), isTrue);
      expect(DomainUtils.isAllowedDomain('https://example.com/article', allowed), isTrue);
      expect(DomainUtils.isAllowedDomain('https://example.com/login', allowed), isTrue);
      expect(DomainUtils.isAllowedDomain('https://www.example.com', allowed), isTrue);
      expect(DomainUtils.isAllowedDomain('https://api.example.com/data', allowed), isTrue);
      expect(DomainUtils.isAllowedDomain('https://cdn.example.com', allowed), isTrue);
    });

    test('isAllowedDomain prevents evil domain bypasses (Planning.md Section 6 & 21)', () {
      const allowed = 'example.com';
      // Bypass attempts that contain example.com but belong to another domain
      expect(DomainUtils.isAllowedDomain('https://example.com.evil.com', allowed), isFalse);
      expect(DomainUtils.isAllowedDomain('https://example.com.evilsite.com', allowed), isFalse);
      expect(DomainUtils.isAllowedDomain('https://example-other.com', allowed), isFalse);
      expect(DomainUtils.isAllowedDomain('https://google.com', allowed), isFalse);
      expect(DomainUtils.isAllowedDomain('https://youtube.com', allowed), isFalse);
    });

    test('isBlockedAdDomain identifies ad domains and subdomains', () {
      expect(DomainUtils.isBlockedAdDomain('https://doubleclick.net/ad.js'), isTrue);
      expect(DomainUtils.isBlockedAdDomain('https://securepubads.g.doubleclick.net/gpt.js'), isTrue);
      expect(DomainUtils.isBlockedAdDomain('https://googlesyndication.com/banner'), isTrue);
      expect(DomainUtils.isBlockedAdDomain('https://taboola.com/widget'), isTrue);
      expect(DomainUtils.isBlockedAdDomain('https://asia9sports.com/video/ad.mp4'), isTrue);
      expect(DomainUtils.isBlockedAdDomain('https://cdn.asia9sports.com/sponsor.mp4'), isTrue);
      expect(DomainUtils.isBlockedAdDomain('https://sbobet.com/banner'), isTrue);
      expect(DomainUtils.isBlockedAdDomain('https://mposport.com/promo'), isTrue);
      expect(DomainUtils.isBlockedAdDomain('https://monetag.com/tag'), isTrue);
      expect(DomainUtils.isBlockedAdDomain('https://example.com/script.js'), isFalse);
    });
  });

  group('WebViewNavigationService Priority Tests', () {
    final navService = WebViewNavigationService();
    const allowed = 'example.com';

    test('Priority 1: Blocks invalid or external schemes', () {
      expect(
        navService.evaluateNavigation('whatsapp://send?phone=123', allowed),
        NavigationResult.blockedInvalidScheme,
      );
      expect(
        navService.evaluateNavigation('intent://something', allowed),
        NavigationResult.blockedInvalidScheme,
      );
      expect(
        navService.evaluateNavigation('mailto:admin@example.com', allowed),
        NavigationResult.blockedInvalidScheme,
      );
    });

    test('Priority 2: Blocks ad domains', () {
      expect(
        navService.evaluateNavigation('https://securepubads.g.doubleclick.net/tag.js', allowed),
        NavigationResult.blockedAdDomain,
      );
      expect(
        navService.evaluateNavigation('https://ads.google.com/click', allowed),
        // ads.google.com is not allowed domain or could be ad domain
        anyOf(NavigationResult.blockedAdDomain, NavigationResult.blockedExternalDomain),
      );
    });

    test('Priority 3: Blocks external domains and allows whitelist', () {
      expect(
        navService.evaluateNavigation('https://google.com', allowed),
        NavigationResult.blockedExternalDomain,
      );
      expect(
        navService.evaluateNavigation('https://example.com/dashboard', allowed),
        NavigationResult.allowed,
      );
      expect(
        navService.evaluateNavigation('https://app.example.com/settings', allowed),
        NavigationResult.allowed,
      );
    });
  });
}
