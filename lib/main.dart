// lib/main.dart
import 'dart:async';
import 'dart:ui'; // PlatformDispatcher
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ✅ 1. 引入 Native Splash
import 'package:flutter_native_splash/flutter_native_splash.dart';

// 本地通知 & 深链处理
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:swaply/services/deep_link_service.dart';

// 引入你的 App 入口 (对应下一步修改 core/app.dart)
import 'package:swaply/core/app.dart';

final FlutterLocalNotificationsPlugin _localNotifications =
FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse details) {
  final payload = details.payload;
  if (payload != null && payload.isNotEmpty) {
    DeepLinkService.instance.handle(payload);
  }
}

Future<void> _initLocalNotifications() async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

  final iosInit = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
    onDidReceiveLocalNotification:
        (int id, String? title, String? body, String? payload) async {
      DeepLinkService.instance.handle(payload);
    },
  );

  final initSettings =
  InitializationSettings(android: androidInit, iOS: iosInit);

  await _localNotifications.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (details) {
      final payload = details.payload;
      if (payload != null && payload.isNotEmpty) {
        DeepLinkService.instance.handle(payload);
      }
    },
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
  );
}

Future<void> main() async {
  // ✅ 2. 确保绑定初始化
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // ✅ 3. 【关键】告诉 iOS：“别动启动图！等我代码通知你再消失”
  // 这行代码能物理屏蔽掉引擎初始化时的黑屏
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  runZonedGuarded(() async {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('[GlobalFlutterError] ${details.exceptionAsString()}');
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('[GlobalUncaughtError] $error\n$stack');
      return true;
    };

    await _initLocalNotifications();

    // 你的 Supabase 初始化 (保持原值)
    await Supabase.initialize(
      url: 'https://rhckybselarzglkmlyqs.supabase.co',
      anonKey:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6...',
    );

    // 设置状态栏样式
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarBrightness: Brightness.light,
      statusBarIconBrightness: Brightness.light,
      statusBarColor: Colors.transparent,
    ));

    // 强制竖屏 (推荐加上，防止启动旋转黑屏)
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    // ❗ 启动 UI (注意：这里改为了 SwaplyApp，请确保下一步修改 core/app.dart)
    runApp(const SwaplyApp());

    // ❌ 【重要】删除了这里的 remove() 和 bootstrap
    // 原因：如果在这里移除启动图，UI 还没画出来，用户就会看到黑屏。
    // 我们将在 WelcomeScreen 的 initState 里移除它。

  }, (error, stack) {
    debugPrint('[GlobalZoneError] $error\n$stack');
  });
}