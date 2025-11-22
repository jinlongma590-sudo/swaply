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
/// ✔ 支持 reset-password / listing / welcome / login / home
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
    final path = uri.path.toLowerCase();

    if (kDebugMode) debugPrint('[DeepLink] navigate -> $uri');

    // ----------- 1) Supabase Magic Link：reset-password ----------
    if (path.contains('reset-password')) {
      final token = uri.queryParameters['token'] ??
          uri.queryParameters['access_token'] ??
          uri.queryParameters['token_hash'];

      navReplaceAll('/forgot-password', arguments: {'token': token});
      return;
    }

    // ----------- 2) Listing 深链：/listing?id=xxx ---------------
    if (path.contains('/listing')) {
      final id = uri.queryParameters['id'];
      if (id != null && id.isNotEmpty) {
        Future.delayed(Duration.zero,
                () => navPush('/listing', arguments: {'id': id}));
        return;
      }
    }

    // ----------- 3) welcome / login / home --------------------
    if (path == '/welcome') {
      Future.delayed(Duration.zero, () => navReplaceAll('/welcome'));
      return;
    }

    if (path == '/login') {
      Future.delayed(Duration.zero, () => navReplaceAll('/login'));
      return;
    }

    if (path == '/home') {
      Future.delayed(Duration.zero, () => navReplaceAll('/home'));
      return;
    }

    // ----------- 4) 所有未匹配的路径 → Home --------------------
    Future.delayed(Duration.zero, () => navReplaceAll('/home'));
  }
}
