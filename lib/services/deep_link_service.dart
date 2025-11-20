// lib/services/deep_link_service.dart
import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:swaply/router/safe_navigator.dart';

/// 深链服务（单例）
/// - 只在首帧后启动一次（幂等）
/// - 解析 listing 链接并跳转到 /listing
/// - 使用 SafeNavigator，避免 context 依赖
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  AppLinks? _links;
  StreamSubscription<Uri>? _sub;
  String? _lastSig;        // 最近一次处理的签名（去重）
  bool _booted = false;    // 是否已经启动

  /// 启动深链监听（可多次调用，但只会初始化一次）
  Future<void> bootstrap() async {
    if (_booted) return;
    _booted = true;

    _links ??= AppLinks();

    // 1) 首次启动时的 initial link
    try {
      final initial = await _links!.getInitialLink();
      if (initial != null) _dispatch(initial);
    } catch (e) {
      debugPrint('[DeepLink] getInitialLink error: $e');
    }

    // 2) 运行期的 link 流（只订阅一次）
    _sub ??= _links!.uriLinkStream.listen(
          (uri) => _dispatch(uri),
      onError: (e, st) => debugPrint('[DeepLink] stream error: $e'),
      cancelOnError: false,
    );
  }

  /// 预留接口：若需要“二次触发”或补偿策略，可从 main.dart 的 100ms 延时里调用
  void flushQueue() {
    // 目前无需处理；保留以便未来扩展
  }

  /// 释放（通常不需要调用）
  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _links = null;
    _booted = false;
    _lastSig = null;
  }

  // ---------------- 内部实现 ----------------

  void _dispatch(Uri uri) {
    final id = _extractListingId(uri);
    if (id == null) return;

    // 去重：同一 listing 连续触发只响应一次
    final sig = 'listing:$id';
    if (_lastSig == sig) {
      debugPrint('[DeepLink] skip duplicated $sig');
      return;
    }
    _lastSig = sig;

    // 双延迟：确保 rootNav 可用 & 避免与首屏构建竞争
    Future.microtask(() {});
    Future.delayed(const Duration(milliseconds: 100), () {
      SafeNavigator.pushNamed('/listing', args: id);
    });
  }

  /// 解析：
  /// - swaply://listing/123
  /// - https://swaply.cc/listing/123
  /// - 或 ?listing_id=123 / ?id=123
  String? _extractListingId(Uri uri) {
    try {
      final segments = uri.pathSegments;
      if (segments.isNotEmpty) {
        final idx = segments.indexOf('listing');
        if (idx >= 0 && idx + 1 < segments.length) {
          final id = segments[idx + 1];
          if (id.isNotEmpty) return id;
        }
      }

      final q = uri.queryParameters['listing_id'] ?? uri.queryParameters['id'];
      if (q != null && q.isNotEmpty) return q;

      return null;
    } catch (_) {
      return null;
    }
  }
}
