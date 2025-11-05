// lib/services/oauth_service.dart
//
// 统一的 OAuth 登录封装（Google / Facebook / Apple）
// - 返回类型统一 Future<void>（兼容旧版返回 bool、新版返回 AuthResponse）
// - redirectTo：Web 传 null；移动端传 swaply://login-callback（见 auth_config.dart）
//
// 不影响 Android；iOS 依赖 Info.plist 里的 URL Schemes 已就绪。

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart' as sf;
import 'package:swaply/config/auth_config.dart'; // kAuthRedirectUri = 'swaply://login-callback'

class OAuthService {
  OAuthService._();

  static sf.SupabaseClient get _sb => sf.Supabase.instance.client;

  /// Google 登录
  static Future<void> signInWithGoogle() async {
    await _sb.auth.signInWithOAuth(
      sf.OAuthProvider.google,
      redirectTo: kIsWeb ? null : kAuthRedirectUri,
      queryParams: const {'prompt': 'select_account'},
    );
  }

  /// Facebook 登录
  static Future<void> signInWithFacebook() async {
    await _sb.auth.signInWithOAuth(
      sf.OAuthProvider.facebook,
      redirectTo: kIsWeb ? null : kAuthRedirectUri,
    );
  }

  /// Apple 登录（仅 iOS 显示按钮）
  static Future<void> signInWithApple() async {
    await _sb.auth.signInWithOAuth(
      sf.OAuthProvider.apple,
      redirectTo: kIsWeb ? null : kAuthRedirectUri,
    );
  }
}
