// lib/core/app.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import 'package:swaply/core/navigation/app_router.dart'; // 主路由
import 'package:swaply/router/root_nav.dart';

import 'package:swaply/core/l10n/app_localizations.dart';
import 'package:swaply/providers/language_provider.dart';

// === 兜底直连的三个页面 ===
import 'package:swaply/pages/sell_form_page.dart';
import 'package:swaply/pages/product_detail_page.dart';
import 'package:swaply/auth/welcome_screen.dart';

// === 新增：登录页 & 首页（用于 /login /home 命名路由） ===
import 'package:swaply/auth/login_screen.dart';
import 'package:swaply/pages/home_page.dart';

// === 全局鉴权观察者 + 深链探针 ===
import 'package:swaply/services/auth_flow_observer.dart';
import 'package:swaply/debug/recovery_probe.dart';
import 'package:swaply/services/deep_link_service.dart'; // ✅ 深链服务（注意新增）

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const _AppBoot();
  }
}

class _AppBoot extends StatefulWidget {
  const _AppBoot({super.key});

  @override
  State<_AppBoot> createState() => _AppBootState();
}

class _AppBootState extends State<_AppBoot> {
  @override
  void initState() {
    super.initState();
    // 启动全局鉴权观察者 & 深链探针
    AuthFlowObserver.I.start();
    RecoveryProbe.attach();

    // ✅ 正确启动深链：首帧后再启动（DeepLinkService 对外方法是 bootstrap）
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await DeepLinkService.instance.bootstrap();
      // 轻微延时，确保路由树可用后再处理任何潜在队列（可选）
      Future.delayed(const Duration(milliseconds: 100), () {
        DeepLinkService.instance.flushQueue();
      });
    });
  }

  @override
  void dispose() {
    // 最小改动：不再调用 stop()（该方法不存在）
    try {
      RecoveryProbe.dispose();
    } catch (_) {}

    // 可选：如果你需要在应用生命周期内彻底释放深链监听
    //（一般不必，除非你在热重启/切换Profile等场景手动控制）
    // DeepLinkService.instance.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
      ],
      child: Builder(
        builder: (ctx) {
          final locale = ctx.watch<LanguageProvider>().currentLocale;

          return ScreenUtilInit(
            designSize: const Size(390, 844),
            minTextAdapt: true,
            splitScreenMode: true,
            builder: (_, __) {
              return MaterialApp(
                title: 'Swaply',
                debugShowCheckedModeBanner: false,

                // 与 root 导航保持一致
                navigatorKey: rootNavKey,

                // ✅ 命名路由（给 navReplaceAll('/login' | '/home') 用）
                routes: {
                  '/login': (_) => const LoginScreen(),
                  '/welcome': (_) => const WelcomeScreen(),
                },

                // 其余未在 routes 中的命名路由，走 AppRouter 或内联兜底
                onGenerateRoute: (RouteSettings settings) {
                  switch (settings.name) {
                    case '/sell-form':
                      return MaterialPageRoute(
                        builder: (_) => const SellFormPage(),
                        settings: settings,
                      );
                    case '/listing':
                    // 约定：navPush('/listing', arguments: {'id': <listingId>});
                      final args = settings.arguments as Map<String, dynamic>?;
                      final id = args?['id']?.toString();
                      return MaterialPageRoute(
                        builder: (_) => ProductDetailPage(productId: id),
                        settings: settings,
                      );
                  }
                  return AppRouter.onGenerateRoute(settings);
                },

                // ✅ 方案A：首屏进入登录页（已登录会由 AuthFlowObserver 立刻跳 /home）
                initialRoute: '/login',

                // 多语言
                locale: locale,
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                ],
                supportedLocales: const [
                  Locale('en'),
                ],

                // 主题
                theme: ThemeData(
                  useMaterial3: false,
                  colorScheme: ColorScheme.fromSeed(
                    seedColor: const Color(0xFF1877F2),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
