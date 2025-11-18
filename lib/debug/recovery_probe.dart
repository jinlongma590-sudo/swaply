// lib/debug/recovery_probe.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RecoveryProbe {
  static StreamSubscription<Uri>? _sub;

  /// 判断是否为 Supabase 的认证回调，必须让 Supabase 自己处理
  static bool _isSupabaseAuthCallback(Uri uri) {
    if (uri.pathSegments.isEmpty) return false;

    final first = uri.pathSegments.first;
    final isLoginCallback = first == 'login-callback';

    // 自定义 scheme：cc.swaply.app://login-callback?code=...
    final isOurScheme = uri.scheme == 'cc.swaply.app';

    // Android App Links / iOS Associated Domains（https 形式）
    // 这里同时容忍 cc.swaply.app / swaply.cc / www.swaply.cc 三种 host
    final isOurHttpsHost = uri.scheme == 'https' &&
        (uri.host == 'cc.swaply.app' ||
            uri.host == 'swaply.cc' ||
            uri.host == 'www.swaply.cc');

    // 一些场景会走 https://swaply.cc/auth/callback?type=...（重置密码等）
    final isAuthCallbackHttps = isOurHttpsHost &&
        first == 'auth' &&
        uri.pathSegments.length >= 2 &&
        uri.pathSegments[1] == 'callback';

    // 需要跳过的两类：
    // 1) 自定义 scheme 的 login-callback
    // 2) https 的 /auth/callback（交由 supabase_flutter 处理）
    return (isLoginCallback && (isOurScheme || isOurHttpsHost)) || isAuthCallbackHttps;
  }

  static Future<void> attach() async {
    final appLinks = AppLinks();

    // 冷启动深链
    final initial = await appLinks.getInitialLink();
    if (initial != null) {
      if (_isSupabaseAuthCallback(initial)) {
        debugPrint('[RECOVERY.PROBE] skip initial auth-callback (handled by Supabase)');
      } else {
        _handle(initial, source: 'initial');
      }
    }

    // 运行期深链
    await _sub?.cancel();
    _sub = appLinks.uriLinkStream.listen(
          (uri) {
        if (_isSupabaseAuthCallback(uri)) {
          debugPrint('[RECOVERY.PROBE] skip login/auth callback (handled by Supabase)');
          return; // ← 关键：不要拦截 Supabase 的认证回调
        }
        _handle(uri, source: 'stream');
      },
      onError: (e) => debugPrint('[RECOVERY.PROBE] stream error: $e'),
    );
  }

  static Future<void> _handle(Uri uri, {required String source}) async {
    final qType = uri.queryParameters['type'] ?? '';
    final fragHasRecovery = uri.fragment.contains('type=recovery');
    final isRecovery = qType == 'recovery' || fragHasRecovery;

    debugPrint('[RECOVERY.PROBE] $source deeplink: $uri');
    debugPrint('[RECOVERY.PROBE] query.type=$qType | fragmentHasRecovery=$fragHasRecovery');

    // ✅ 不主动调用 SupabaseAuth.onDeepLink(uri)
    // 交由 supabase_flutter 内部处理并通过 onAuthStateChange 通知

    // 仅观察当前会话（便于调试）
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final s = Supabase.instance.client.auth.currentSession;
    debugPrint('[RECOVERY.PROBE] post-handoff sessionUser=${s?.user.id}');

    if (isRecovery) {
      debugPrint('[RECOVERY.PROBE] >>> 识别为恢复流程 (type=recovery)，交给 onAuthStateChange 跳转重置页');
    }
  }

  static Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}
