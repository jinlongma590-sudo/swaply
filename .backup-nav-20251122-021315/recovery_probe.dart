// lib/debug/recovery_probe.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ✅ 新增：识别到认证回调时立刻结束 OAuth 防重入
import 'package:swaply/services/oauth_entry.dart';

class RecoveryProbe {
  static StreamSubscription<Uri>? _sub;

  /// 统一判断：是否是 Supabase 的认证回调（必须让 supabase_flutter 自己处理）
  static bool _isSupabaseAuthCallback(Uri uri) {
    // 1) 自定义 scheme：cc.swaply.app://login-callback?code=...
    //    注意：此时 login-callback 在 host 中，不在 path 里
    final isOurScheme = uri.scheme == 'cc.swaply.app';
    final host = (uri.host).toLowerCase();
    final isLoginHost = host == 'login-callback';
    final isResetHost = host == 'reset-password'; // 有些恢复流程会走这个 host
    final schemeAuth = isOurScheme && (isLoginHost || isResetHost);

    // 2) App/Universal Links（https）
    final isHttps = uri.scheme == 'https';
    final isOurHttpsHost = isHttps &&
        (uri.host == 'swaply.cc' ||
            uri.host == 'www.swaply.cc' ||
            uri.host == 'cc.swaply.app');

    //    - https://swaply.cc/auth/callback?...   ← supabase 官方回调
    //    - （兜底）https://swaply.cc/login-callback?... 也视为回调，防止误拦截
    final segments = uri.pathSegments;
    final first = segments.isNotEmpty ? segments.first : '';
    final second = segments.length >= 2 ? segments[1] : '';

    final isAuthCallbackHttps =
        isOurHttpsHost && first == 'auth' && second == 'callback';
    final isLoginCallbackHttps =
        isOurHttpsHost && first == 'login-callback';

    return schemeAuth || isAuthCallbackHttps || isLoginCallbackHttps;
  }

  static Future<void> attach() async {
    final appLinks = AppLinks();

    // 冷启动深链
    final initial = await appLinks.getInitialLink();
    if (initial != null) {
      if (_isSupabaseAuthCallback(initial)) {
        // ✅ 识别为认证回调：交给 supabase_flutter 处理，并立刻结束 OAuth 防重入
        debugPrint('[RECOVERY.PROBE] skip initial auth-callback (handled by Supabase): $initial');
        try {
          OAuthEntry.finish(); // 立刻解锁，防止按钮在返回 App 后短暂失效
        } catch (_) {}
      } else {
        _handle(initial, source: 'initial');
      }
    }

    // 运行期深链
    await _sub?.cancel();
    _sub = appLinks.uriLinkStream.listen(
          (uri) {
        if (_isSupabaseAuthCallback(uri)) {
          // ✅ 识别为认证回调：交给 supabase_flutter 处理，并立刻结束 OAuth 防重入
          debugPrint('[RECOVERY.PROBE] skip login/auth callback (handled by Supabase): $uri');
          try {
            OAuthEntry.finish(); // 立刻解锁
          } catch (_) {}
          return; // 不拦截 supabase 的认证回调
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
