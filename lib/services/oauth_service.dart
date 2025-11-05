// lib/services/oauth_service.dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode;
import 'package:swaply/config/auth_config.dart';

/// 统一封装三方登录（Google / Facebook / Apple）
/// - 使用 PKCE（在 `Supabase.initialize` 已设置）
/// - 移动端优先用 **inAppBrowserView**（Android 的 Chrome Custom Tabs、iOS 的 SFSafariViewController），
///   这是 Google 允许的授权容器；设备不支持时由 url_launcher 自动回落到系统浏览器。
/// - redirectTo 全部统一走 `swaply://login-callback`
class OAuthService {
  static SupabaseClient get _sb => Supabase.instance.client;

  /// 移动端优先走 CustomTabs / SFSafariVC；Web 保持默认。
  static LaunchMode get _launchMode =>
      kIsWeb ? LaunchMode.platformDefault : LaunchMode.inAppBrowserView;

  /// Google 登录
  static Future<void> signInWithGoogle() {
    return _sb.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? null : kAuthRedirectUri,
      // Google 推荐的基本作用域
      scopes: 'openid email profile',
      // 让用户每次可选择账号
      queryParams: const {'prompt': 'select_account'},
      authScreenLaunchMode: _launchMode,
    );
  }

  /// Facebook 登录
  static Future<void> signInWithFacebook() {
    return _sb.auth.signInWithOAuth(
      OAuthProvider.facebook,
      redirectTo: kIsWeb ? null : kAuthRedirectUri,
      // 明确声明 email（public_profile 默认就有，这里补上 email）
      scopes: 'public_profile,email',
      authScreenLaunchMode: _launchMode,
    );
  }

  /// Apple 登录
  static Future<void> signInWithApple() {
    return _sb.auth.signInWithOAuth(
      OAuthProvider.apple,
      redirectTo: kIsWeb ? null : kAuthRedirectUri,
      // Apple 要求用空格分隔
      scopes: 'name email',
      authScreenLaunchMode: _launchMode,
    );
  }
}
