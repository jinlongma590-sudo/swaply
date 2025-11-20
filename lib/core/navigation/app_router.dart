// lib/core/navigation/app_router.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:swaply/pages/main_navigation_page.dart';
import 'package:swaply/auth/welcome_screen.dart';
import 'package:swaply/auth/login_screen.dart';
import 'package:swaply/pages/coupon_management_page.dart';
// 如果你的重置密码页不在 pages/ 而在 auth/，请把下一行改成 auth/reset_password_page.dart
import 'package:swaply/auth/forgot_password_screen.dart';
import 'package:swaply/pages/product_detail_page.dart';

class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final name = settings.name ?? '/';
    final hasSession =
        Supabase.instance.client.auth.currentSession != null;

    switch (name) {
      case '/':
        return _fade(
          hasSession ? const MainNavigationPage() : const WelcomeScreen(),
          name,
        );
      case '/home':
        return _fade(const MainNavigationPage(), name);
      case '/welcome':
        return _fade(const WelcomeScreen(), name);
      case '/login':
        return _fade(const LoginScreen(), name);
      case '/coupons':
        return _fade(const CouponManagementPage(), name);
      case '/reset-password':
        return _fade(const ForgotPasswordScreen(), name);
      case '/listing':
        final id = settings.arguments as String? ?? '';
        return _fade(ProductDetailPage(productId: id), name);
      default:
      // 未命中时回首页，避免异常
        return _fade(const MainNavigationPage(), '/home');
    }
  }

  static PageRoute _fade(Widget page, String name) {
    return PageRouteBuilder(
      settings: RouteSettings(name: name),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
      transitionDuration: const Duration(milliseconds: 180),
    );
  }
}
