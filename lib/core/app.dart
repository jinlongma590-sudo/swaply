// lib/core/app.dart
//
// 全局唯一 App 入口（唯一 MaterialApp）
// ● 挂 rootNavKey（来自 SafeNavigator）
// ● 深链 DeepLinkService 单例集中 bootstrap
// ● 登录后调用 ensureWelcomeForCurrentUser（写 pending flag）
// ● HomePage / MainNavigationPage 只负责 UI，不负责全局逻辑
// ● 全工程只有这一个 MaterialApp —— 根本解决黑屏 / GlobalKey 冲突
//

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swaply/router/root_nav.dart';
import 'package:swaply/router/safe_navigator.dart';
import 'package:swaply/core/navigation/app_router.dart';
import 'package:swaply/services/deep_link_service.dart';
import 'package:swaply/services/welcome_dialog_service.dart';
import 'package:swaply/services/reward_service.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _booted = false;
  bool _welcomeScheduled = false;

  @override
  void initState() {
    super.initState();

    // 登录后写 pending 位
    Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      final session = event.session;

      if (session != null && session.user != null) {
        final uid = session.user!.id;

        // 写 pending 位（首次登录用户）
        RewardService.ensureWelcomeForCurrentUser().then((result) async {
          if (!mounted) return;

          if (result.shouldPopup) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool(
              'new_user_welcome_pending_$uid',
              true,
            );
          }
        });

        // 登录后触发欢迎弹窗
        if (!_welcomeScheduled) {
          _welcomeScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            WelcomeDialogService.scheduleCheck(context);
          });
        }
      }
    });

    // 深链监听
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_booted) {
        _booted = true;
        await DeepLinkService.instance.bootstrap();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      builder: (_, __) {
        return MaterialApp(
          title: 'Swaply',
          debugShowCheckedModeBanner: false,
          navigatorKey: rootNavKey, // 全 app 唯一 navigator
          onGenerateRoute: AppRouter.onGenerateRoute,
          initialRoute: '/',
          theme: ThemeData(
            primaryColor: const Color(0xFF1877F2),
            useMaterial3: false,
            scaffoldBackgroundColor: Colors.white,
          ),
        );
      },
    );
  }
}
