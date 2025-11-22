// lib/services/deep_link_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_links/app_links.dart';

import 'package:swaply/router/root_nav.dart';

/// =============================================================
/// DeepLinkService （最终完整版，适配新版 app_links API）
///
/// ✔ 支持 Universal Links / App Links / Supabase Magic Link
/// ✔ 支持 reset-password / listing / welcome / login / home / offer
/// ✔ 冷启动 + 前台 deep link 全支持
/// ✔ getInitialLink()（新版 API）
/// =============================================================
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  final AppLinks _appLinks = AppLinks();

  final List<Uri> _pending = [];

  bool _bootstrapped = false;
  bool _flushing = false;

  /// 初始化，AppBoot initState -> addPostFrameCallback 调用
  Future<void> bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;

    // ------------ 前台深链（APP 打开状态点击链接） ------------
    _appLinks.uriLinkStream.listen((uri) {
      if (kDebugMode) debugPrint('[DeepLink] uriLinkStream -> $uri');
      _handle(uri);
    }, onError: (err) {
      if (kDebugMode) debugPrint('[DeepLink] stream error: $err');
    });

    // ------------ 冷启动深链（APP 未打开 → 点击链接启动） ------------
    try {
      // !!! 新 API：getInitialLink() !!!
      final initial = await _appLinks.getInitialLink();

      if (initial != null) {
        if (kDebugMode) {
          debugPrint('[DeepLink] getInitialLink -> $initial');
        }
        _handle(initial, isInitial: true);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[DeepLink] initial link error: $e');
    }
  }

  // ========= ✅ 对外统一入口（给通知点击、手动触发等用） =========
  /// 支持传入字符串 payload（如 'swaply://offer?offer_id=xxx&listing_id=yyy'）
  void handle(String? payload) {
    if (payload == null || payload.trim().isEmpty) return;
    try {
      final uri = Uri.parse(payload.trim());
      if (kDebugMode) debugPrint('[DeepLink] handle(payload) -> $uri');
      _handle(uri);
      // 如果当时还未就绪，确保稍后能 flush
      flushQueue();
    } catch (e) {
      if (kDebugMode) debugPrint('[DeepLink] handle(payload) parse error: $e');
    }
  }

  /// 所有深链 handler 统一入口
  void _handle(Uri uri, {bool isInitial = false}) {
    if (!_isReadyToNavigate()) {
      _pending.add(uri);
      return;
    }
    _navigate(uri);
  }

  /// App 是否已经可以安全导航
  bool _isReadyToNavigate() {
    return rootNavKey.currentState != null;
  }

  /// 刷新队列（在 AppBoot postFrame 后自动调用）
  void flushQueue() {
    if (_flushing) return;
    _flushing = true;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      Future.microtask(() {
        for (final u in List<Uri>.from(_pending)) {
          _navigate(u);
        }
        _pending.clear();
        _flushing = false;
      });
    });
  }

  // ============================================================
  // 深链路由解析
  // ============================================================
  void _navigate(Uri uri) {
    final scheme = (uri.scheme).toLowerCase();
    final host = (uri.host).toLowerCase();
    final path = (uri.path).toLowerCase();

    if (kDebugMode) {
      debugPrint('[DeepLink] navigate -> scheme=$scheme host=$host path=$path | $uri');
    }

    // 0) ✅ 忽略 Supabase 的登录回调（让 Supabase 自己处理）
    if (scheme == 'cc.swaply.app' && host == 'login-callback') {
      if (kDebugMode) debugPrint('[DeepLink] skip supabase login-callback');
      return;
    }

    // ----------- 1) Supabase Magic Link：reset-password ----------
    // 兼容：cc.swaply.app://reset-password?token=...（host 方式）
    // 以及：https://swaply.cc/reset-password?token=...（path 方式）
    final isResetByHost = host == 'reset-password';
    final isResetByPath = path.contains('reset-password');
    if (isResetByHost || isResetByPath) {
      final token = uri.queryParameters['token'] ??
          uri.queryParameters['access_token'] ??
          uri.queryParameters['token_hash'];

      Future.delayed(Duration.zero, () {
        navReplaceAll('/forgot-password', arguments: {'token': token});
      });
      return;
    }

    // ----------- 2) Offer 深链：swaply://offer?offer_id=xxx&listing_id=yyy ----------
    // 也兼容：https://swaply.cc/offer?offer_id=xxx...
    final isOfferByHost = host == 'offer';
    final isOfferByPath = path.contains('/offer');
    if (isOfferByHost || isOfferByPath) {
      final offerId = uri.queryParameters['offer_id'] ?? uri.queryParameters['id'];
      final listingId = uri.queryParameters['listing_id'] ??
          uri.queryParameters['listingid'] ??
          uri.queryParameters['listing'];
      if (offerId != null && offerId.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('DeepLink → OfferDetailPage: offer_id=$offerId listing_id=${listingId ?? "-"}');
        }
        Future.delayed(Duration.zero, () {
          navPush('/offer-detail', arguments: {
            'offer_id': offerId,
            if (listingId != null && listingId.isNotEmpty) 'listing_id': listingId,
          });
        });
        return;
      }
    }

    // ----------- 3) Listing 深链：swaply://listing?listing_id=xxx ----------
    // 兼容历史：/listing?id=xxx 以及 https://swaply.cc/listing?id=xxx
    final isListingByHost = host == 'listing';
    final isListingByPath = path.contains('/listing');
    if (isListingByHost || isListingByPath) {
      final listingId = uri.queryParameters['listing_id'] ?? uri.queryParameters['id'];
      if (listingId != null && listingId.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('DeepLink → ProductDetailPage: listing_id=$listingId');
        }
        Future.delayed(Duration.zero, () {
          navPush('/product-detail', arguments: {'id': listingId});
        });
        return;
      }
    }

    // ----------- 4) welcome / login / home --------------------
    // 兼容 host 风格（swaply://welcome）与 path 风格（/welcome）
    final isWelcome = host == 'welcome' || path == '/welcome';
    if (isWelcome) {
      Future.delayed(Duration.zero, () => navReplaceAll('/welcome'));
      return;
    }

    final isLogin = host == 'login' || path == '/login';
    if (isLogin) {
      Future.delayed(Duration.zero, () => navReplaceAll('/login'));
      return;
    }

    final isHome = host == 'home' || path == '/home';
    if (isHome) {
      Future.delayed(Duration.zero, () => navReplaceAll('/home'));
      return;
    }

    // ----------- 5) 默认：不再强制回首页（避免吃掉未知链接、避免循环重建） ----------
    if (kDebugMode) debugPrint('[DeepLink] unmatched -> ignore: $uri');
  }
}
