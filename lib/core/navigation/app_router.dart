// lib/core/navigation/app_router.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:swaply/pages/main_navigation_page.dart';
import 'package:swaply/auth/welcome_screen.dart';
import 'package:swaply/auth/login_screen.dart';
import 'package:swaply/auth/register_screen.dart';
import 'package:swaply/auth/forgot_password_screen.dart';

import 'package:swaply/pages/coupon_management_page.dart';
import 'package:swaply/pages/product_detail_page.dart';
import 'package:swaply/pages/sell_form_page.dart';

/// ===============================================================
/// AppRouter (A 方案)
/// ---------------------------------------------------------------
/// ✔ 与 AuthFlowObserver 完全对齐
/// ✔ '/' 交由 AuthFlowObserver 决定去 /home 或 /welcome
/// ✔ 保留 fade 动画
/// ✔ 修复所有路由冲突：/home /welcome /login /sell-form /listing
/// ✔ 未命中路由统一 fallback → MainNavigationPage
/// ===============================================================
class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final String name = settings.name ?? '/';
    final bool hasSession =
        Supabase.instance.client.auth.currentSession != null;

    switch (name) {
    /* ============================================================
       * 顶层入口路由（交由 AuthFlowObserver 控制）
       * ============================================================ */
      case '/':
        return _fade(
          hasSession
              ? const MainNavigationPage()
              : const WelcomeScreen(), // 无会话：欢迎页
          '/',
        );

    /* ------------------ 主导航页面 ------------------ */
      case '/home':
        return _fade(const MainNavigationPage(), '/home');

    /* ------------------ 权限/登录流程 ------------------ */
      case '/welcome':
        return _fade(const WelcomeScreen(), '/welcome');

      case '/login':
        return _fade(const LoginScreen(), '/login');

      case '/register':
        return _fade(const RegisterScreen(), '/register');

      case '/forgot-password':
      case '/reset-password':
        return _fade(const ForgotPasswordScreen(), '/forgot-password');

    /* ------------------ 我的优惠券 ------------------ */
      case '/coupons':
        return _fade(const CouponManagementPage(), '/coupons');

    /* ------------------ 发布页面 ------------------ */
      case '/sell-form':
        return _fade(const SellFormPage(), '/sell-form');

    /* ============================================================
       * 商品详情页
       * - 支持：navPush('/listing', arguments: {'id': xxx})
       * - 支持：navPush('/listing', arguments: 'xxx')
       * ============================================================ */
      case '/listing': {
        final args = settings.arguments;
        String productId = '';

        if (args is String) {
          productId = args;
        } else if (args is Map && args['id'] != null) {
          productId = '${args['id']}';
        }

        return _fade(
          ProductDetailPage(productId: productId),
          '/listing',
        );
      }

    /* ============================================================
       * Fallback：未匹配路由 → Home
       * ============================================================ */
      default:
        return _fade(const MainNavigationPage(), '/home');
    }
  }

  /* ============================================================
   * fade 动画封装
   * ============================================================ */
  static PageRoute _fade(Widget page, String name) {
    return PageRouteBuilder(
      settings: RouteSettings(name: name),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, anim, __, child) {
        return FadeTransition(
          opacity: anim,
          child: child,
        );
      },
    );
  }
}
