// lib/core/navigation/app_router.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:swaply/pages/main_navigation_page.dart';
import 'package:swaply/auth/welcome_screen.dart';
import 'package:swaply/auth/login_screen.dart';
import 'package:swaply/auth/register_screen.dart';
import 'package:swaply/pages/coupon_management_page.dart';
import 'package:swaply/auth/forgot_password_screen.dart';
import 'package:swaply/pages/product_detail_page.dart';
import 'package:swaply/pages/sell_form_page.dart';

class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final name = settings.name ?? '/';
    final hasSession = Supabase.instance.client.auth.currentSession != null;

    switch (name) {
      case '/':
        return _fade(hasSession ? const MainNavigationPage()
            : const WelcomeScreen(), name);

      case '/home':
        return _fade(const MainNavigationPage(), name);

      case '/welcome':
        return _fade(const WelcomeScreen(), name);

      case '/login':
        return _fade(const LoginScreen(), name);

    // 新增：注册页
      case '/register':
        return _fade(const RegisterScreen(), name);

    // 新增：忘记/重置密码（两个路径都指向同页，兼容外部入口）
      case '/forgot-password':
      case '/reset-password':
        return _fade(const ForgotPasswordScreen(), name);

      case '/coupons':
        return _fade(const CouponManagementPage(), name);

    // 新增：发布表单页（SellPage 内部会 navPush('/sell-form')）
      case '/sell-form':
        return _fade(const SellFormPage(), name);

    // 详情页：支持 String id 或 Map {id: ...}
      case '/listing': {
        final args = settings.arguments;
        String productId = '';
        if (args is String) {
          productId = args;
        } else if (args is Map && args['id'] != null) {
          productId = '${args['id']}';
        }
        return _fade(ProductDetailPage(productId: productId), name);
      }

    // 未命中时回首页，避免抛异常
      default:
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
