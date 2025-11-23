// lib/main.dart
import 'dart:async';
import 'dart:ui'; // ✅ for PlatformDispatcher
import 'package:flutter/foundation.dart'; // ✅ for FlutterError
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ✅ 本地通知 & 深链处理
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:swaply/services/deep_link_service.dart';

import 'package:swaply/core/app.dart'; // ← 全局唯一入口

// 全局通知实例
final FlutterLocalNotificationsPlugin _localNotifications =
FlutterLocalNotificationsPlugin();

// 后台点击通知的回调（必须是顶层方法）
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse details) {
  final payload = details.payload;
  if (payload != null && payload.isNotEmpty) {
    // 统一交给 DeepLinkService 解析（会排队，待导航就绪后再跳转）
    DeepLinkService.instance.handle(payload);
  }
}

// 本地通知初始化（最小改动：只注入点击回调）
Future<void> _initLocalNotifications() async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

  final iosInit = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
    // iOS 10- 的兜底回调
    onDidReceiveLocalNotification:
        (int id, String? title, String? body, String? payload) async {
      DeepLinkService.instance.handle(payload);
    },
  );

  final initSettings =
  InitializationSettings(android: androidInit, iOS: iosInit);

  await _localNotifications.initialize(
    initSettings,
    // ✅ 核心：点击通知 → 把 payload 交给 DeepLinkService
    onDidReceiveNotificationResponse: (NotificationResponse details) {
      final payload = details.payload;
      if (payload != null && payload.isNotEmpty) {
        DeepLinkService.instance.handle(payload);
      }
    },
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // === Global error guard (iOS 黑屏止血) ===
  runZonedGuarded(() async {
    // 捕获 Flutter 框架内异常
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('[GlobalFlutterError] ${details.exceptionAsString()}');
    };

    // 捕获未处理的异步异常（TestFlight/Release 关键）
    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('[GlobalUncaughtError] $error\n$stack');
      return true; // 避免应用崩溃/黑屏
    };

    // ✅ 初始化本地通知（用于“点击通知 → 解析 swaply://...”）
    await _initLocalNotifications();

    // 初始化 Supabase（必须在 runApp 前）
    await Supabase.initialize(
      url: 'https://rhckybselarzglkmlyqs.supabase.co',
      anonKey:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJoY2t5YnNlbGFyemdsa21seXFzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTUwMTM0NTgsImV4cCI6MjA3MDU4OTQ1OH0.3I0T2DidiF-q9l2tWeHOjB31QogXHDqRtEjDn0RfVbU',
    );

    // iOS 状态栏透明 & 浅色图标（不会造成审核黑屏）
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarBrightness: Brightness.light,
      statusBarIconBrightness: Brightness.light,
      statusBarColor: Colors.transparent,
    ));

    // 启动真正的 App（MaterialApp 在 core/app.dart 定义）
    runApp(const MyApp());

    // ✅ 补充：首帧建立后再启动深链服务，避免竞态
    DeepLinkService.instance.bootstrap();
  }, (error, stack) {
    // Zone 兜底
    debugPrint('[GlobalZoneError] $error\n$stack');
  });
}