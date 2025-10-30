import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 根据平台返回回调地址：Web 用 Dashboard 的 callback，移动端用自定义 scheme
String _redirectUrl() {
  if (kIsWeb) {
    // 你项目的固定回调
    return 'https://rhckybselarzglkmlyqs.supabase.co/auth/v1/callback';
  }
  // Android/iOS 自定义回调（已在 Manifest/Info.plist 配置）
  return 'swaply://login-callback';
}

/// Google 登录
Future<void> signInWithGoogle(BuildContext context) async {
  final client = Supabase.instance.client;

  try {
    final redirectUrl = _redirectUrl();

    await client.auth.signInWithOAuth(
      OAuthProvider.google,                // ✅ 关键：用 OAuthProvider.google
      scopes: 'openid email profile',
      redirectTo: redirectUrl,
    );

    debugPrint('[Google Sign-In] launched, redirect=$redirectUrl');
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
    await Supabase.instance.client.auth.signOut();
  } catch (e) {
    debugPrint('[Google Sign-Out] error: $e');
  }
}

/// 是否已登录
bool isLoggedIn() => Supabase.instance.client.auth.currentUser != null;
