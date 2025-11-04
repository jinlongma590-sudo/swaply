// lib/services/oauth_service.dart
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:swaply/config.dart'; // 读取 AppConfig.authRedirectUri

class OAuthService {
  /// 统一 Deep Link 回调，来自 AppConfig
  static String get _redirectUri => AppConfig.authRedirectUri;

  /// Facebook 登录
  static Future<void> signInWithFacebook() async {
    await Supabase.instance.client.auth.signInWithOAuth(
      OAuthProvider.facebook,
      // Web 端让 Supabase 用 Dashboard 配置；移动端显式传 deep link
      redirectTo: kIsWeb ? null : _redirectUri,
      authScreenLaunchMode:
      kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
    );
  }

  /// Google 登录
  static Future<void> signInWithGoogle() async {
    await Supabase.instance.client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? null : _redirectUri,
      // 方便切换账号
      queryParams: const {'prompt': 'select_account'},
      authScreenLaunchMode:
      kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
    );
  }

  /// Apple 登录（iOS 使用；Android 端 UI 隐藏即可）
  static Future<void> signInWithApple() async {
    await Supabase.instance.client.auth.signInWithOAuth(
      OAuthProvider.apple,
      redirectTo: kIsWeb ? null : _redirectUri,
      authScreenLaunchMode:
      kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
    );
  }
}
