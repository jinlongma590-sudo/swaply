// lib/debug/recovery_probe.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RecoveryProbe {
  static StreamSubscription<Uri>? _sub;

  static Future<void> attach() async {
    final appLinks = AppLinks();

    // 初始深链
    final initial = await appLinks.getInitialLink();
    if (initial != null) {
      _handle(initial, source: 'initial');
    }

    // 运行期深链
    await _sub?.cancel();
    _sub = appLinks.uriLinkStream.listen(
          (uri) => _handle(uri, source: 'stream'),
      onError: (e) => debugPrint('[RECOVERY.PROBE] stream error: $e'),
    );
  }

  static Future<void> _handle(Uri uri, {required String source}) async {
    final qType = uri.queryParameters['type'] ?? '';
    final fragHasRecovery = uri.fragment.contains('type=recovery');
    final isRecovery = qType == 'recovery' || fragHasRecovery;

    debugPrint('[RECOVERY.PROBE] $source deeplink: $uri');
    debugPrint('[RECOVERY.PROBE] query.type=$qType | fragmentHasRecovery=$fragHasRecovery');

    // ✅ 不再主动调用 SupabaseAuth.onDeepLink(uri)
    // supabase_flutter 自己会处理深链并触发 onAuthStateChange

    // 看一眼当前会话（仅用于观察）
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
