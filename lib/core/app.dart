// lib/core/app.dart
//
// 全局唯一 App 入口（唯一 MaterialApp）
// ● 挂 rootNavKey
// ● 深链 DeepLinkService 单例集中 bootstrap（首帧后启动）
// ● 登录后调用 ensureWelcomeForCurrentUser（写 pending flag）
// ● HomePage / MainNavigationPage 只负责 UI，不负责全局逻辑
// ● 全工程只有这一个 MaterialApp —— 根本解决黑屏 / GlobalKey 冲突
//

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // ✅ 新增：Web 目标跳过 app_links
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import 'package:swaply/router/root_nav.dart';
import 'package:swaply/core/navigation/app_router.dart';
import 'package:swaply/services/deep_link_service.dart';
import 'package:swaply/services/welcome_dialog_service.dart';
import 'package:swaply/services/reward_service.dart';
import 'package:swaply/providers/language_provider.dart';
import 'package:swaply/services/auth_flow_observer.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _booted = false;
  bool _welcomeScheduled = false;
  bool _dlBooted = false; // ✅ 新增：深链只启动一次的守卫

  @override
  void initState() {
    super.initState();

    // ✅ 启动全局认证流观察与导航（唯一监听者集中在这里）
    AuthFlowObserver.I.start();

    // ✅ 深链监听放到首帧后，且全局只启动一次（Web 目标跳过）
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _dlBooted) return;
      _dlBooted = true;
      _booted = true; // 保留原有语义
      if (!kIsWeb) {
        await DeepLinkService.instance.bootstrap();
      }
    });

    // ⛔ 移除这里的全局 onAuthStateChange 监听（并发源）
    // （原先写 pending 位与调度欢迎弹窗的逻辑，已收敛到 AuthFlowObserver）
  }

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      builder: (_, __) {
        return ChangeNotifierProvider(
          create: (_) => LanguageProvider(),
          child: MaterialApp(
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
          ),
        );
      },
    );
  }
}
