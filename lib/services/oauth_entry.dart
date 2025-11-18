// lib/services/oauth_entry.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode;

class OAuthEntry {
  OAuthEntry._();
  static bool _inFlight = false;

  static const String _mobileRedirect = 'cc.swaply.app://login-callback';
  static const String _webRedirect = 'https://swaply.cc/auth/callback';

  /// 全项目唯一 OAuth 发起入口
  static Future<void> signIn(
      OAuthProvider provider, {
        String? scopes,
        Map<String, String>? queryParams,
      }) async {
    if (_inFlight) return; // 全局防重入
    _inFlight = true;

    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        provider,
        redirectTo: kIsWeb ? _webRedirect : _mobileRedirect,
        authScreenLaunchMode: LaunchMode.externalApplication,
        scopes: scopes,
        queryParams: queryParams,
      );
      // 导航交给 onAuthStateChange，不在此处额外跳转
    } finally {
      _inFlight = false;
    }
  }
}
