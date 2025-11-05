import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// --- 新增 Import ---
import 'package:swaply/services/oauth_service.dart';
// -----------------

/// 根据平台返回回调地址：Web 用 Dashboard 的 callback，移动端用自定义 scheme
// --- 已删除：不再需要此方法，逻辑统一到 OAuthService ---
// String _redirectUrl() { ... }

/// Google 登录
Future<void> signInWithGoogle(BuildContext context) async {
  // final client = Supabase.instance.client; // 已移至 OAuthService

  try {
    // --- 修改：调用统一的 Service ---
    // final redirectUrl = _redirectUrl();
    // await client.auth.signInWithOAuth(
    //   OAuthProvider.google,
    //   scopes: 'openid email profile',
    //   redirectTo: redirectUrl,
    // );
    // debugPrint('[Google Sign-In] launched, redirect=$redirectUrl');
    await OAuthService.signInWithGoogle();
    debugPrint('[Google Sign-In] launched via OAuthService.');
    // --- 结束 ---
  } catch (e, st) {
    debugPrint('[Google Sign-In] error: $e\n$st');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Google 登录启动失败，请稍后再试')),
    );
  }
}

/// 退出登录
Future<void> signOutGoogle() async {
  try {
    // 这个方法保持不变是安全的
    await Supabase.instance.client.auth.signOut();
  } catch (e) {
    debugPrint('[Google Sign-Out] error: $e');
  }
}

/// 是否已登录
bool isLoggedIn() => Supabase.instance.client.auth.currentUser != null;