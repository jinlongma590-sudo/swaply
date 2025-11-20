// lib/main.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:swaply/router/root_nav.dart'; // rootNavKey / navPush
import 'package:swaply/pages/main_navigation_page.dart';
import 'package:swaply/pages/product_detail_page.dart';
import 'package:swaply/auth/login_screen.dart'; // 测试/跳转需要

// 你项目主色（先内联，等以后统一到 theme 文件）
const Color _PRIMARY_BLUE = Color(0xFF1877F2);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 状态栏/导航条基础样式（可按需调整）
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarBrightness: Brightness.light,
    statusBarIconBrightness: Brightness.light,
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  runZonedGuarded(() {
    runApp(const MyApp());
  }, (e, st) {
    if (kDebugMode) {
      // 开发期打印异常
      // ignore: avoid_print
      print('[Uncaught] $e\n$st');
    }
  });
}

/// 测试文件会找这个类，所以保留该名字
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavKey, // ✅ 全局唯一 navigator
      title: 'Swaply',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _PRIMARY_BLUE),
        primaryColor: _PRIMARY_BLUE,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
      ),
      // 只保留一个入口：你的主导航页
      home: const MainNavigationPage(),

      // 简单命名路由（可按需扩展）
      routes: {
        '/login': (_) => const LoginScreen(),
      },

      // 统一用 onGenerateRoute 处理需要参数的页面
      onGenerateRoute: (settings) {
        if (settings.name == '/listing') {
          final arg = settings.arguments;
          // 支持直接传 String/num，或 { productId: xxx }
          dynamic productId;
          if (arg is Map && arg.containsKey('productId')) {
            productId = arg['productId'];
          } else {
            productId = arg;
          }
          return MaterialPageRoute(
            builder: (_) => ProductDetailPage(productId: productId),
            settings: settings,
          );
        }
        return null;
      },
    );
  }
}
