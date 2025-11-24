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
import 'package:flutter/foundation.dart' show kIsWeb;
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
import 'package:swaply/pages/main_navigation_page.dart'; // ✅ 兜底路由所需

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _booted = false;
  bool _welcomeScheduled = false;

  // 确保 DeepLinkService.bootstrap() 全局只运行一次
  bool _dlBooted = false;

  @override
  void initState() {
    super.initState();

    // 启动全局认证流观察 —— 唯一导航源
    AuthFlowObserver.I.start();

    // 深链：必须在首帧之后启动，否则会导致 iOS 黑屏
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _dlBooted) return;
      _dlBooted = true;

      if (!kIsWeb) {
        await DeepLinkService.instance.bootstrap();
      }

      _booted = true;
    });
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
            title: 'Swaply ZW',
            debugShowCheckedModeBanner: false,
            navigatorKey: rootNavKey, // Global Navigator（唯一）
            onGenerateRoute: AppRouter.onGenerateRoute,
            onUnknownRoute: (settings) =>
                MaterialPageRoute(builder: (_) => const MainNavigationPage()), // ✅ 兜底，防黑屏
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
