// lib/main.dart
import 'dart:async';
import 'dart:ui'; // PlatformDispatcher
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// 本地通知 & 深链处理
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:swaply/services/deep_link_service.dart';

import 'package:swaply/core/app.dart'; // ← 全局唯一入口

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
  WidgetsFlutterBinding.ensureInitialized();

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

    await Supabase.initialize(
      url: 'https://rhckybselarzglkmlyqs.supabase.co',
      anonKey:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6...',
    );

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarBrightness: Brightness.light,
      statusBarIconBrightness: Brightness.light,
      statusBarColor: Colors.transparent,
    ));

    // ❗ 启动 UI
    runApp(const MyApp());

    // ❗❗ 删除 bootstrap，不要在这里启动 deep link（会黑屏）
    // DeepLinkService.instance.bootstrap();
  }, (error, stack) {
    debugPrint('[GlobalZoneError] $error\n$stack');
  });
}