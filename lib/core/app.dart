// lib/core/app.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'package:swaply/core/navigation/app_router.dart';
import 'package:swaply/router/root_nav.dart';

import 'package:swaply/core/l10n/app_localizations.dart';

// LanguageProvider 已从 services 迁到 providers
import 'package:swaply/providers/language_provider.dart';

// 仅用于 Provider 初始化时需要的类型引用；页面路由由 AppRouter 统一处理

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        // 其他 Provider 保持不变，后续步骤再迁移/收口
      ],
      child: Builder(
        builder: (ctx) {
          final locale = ctx.watch<LanguageProvider>().currentLocale;

          return MaterialApp(
            title: 'Swaply',
            debugShowCheckedModeBanner: false,
            navigatorKey: rootNavKey,                 // ✅ 绑定全局 navigatorKey
            onGenerateRoute: AppRouter.onGenerateRoute, // ✅ 接入集中路由
            initialRoute: '/',                        // ✅ 冷启动统一走 AppRouter("/")
            locale: locale,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: const [
              Locale('en'),
              // 如有多语言，后续在这里追加
            ],
            theme: ThemeData(
              useMaterial3: false,
              colorScheme:
              ColorScheme.fromSeed(seedColor: const Color(0xFF1877F2)),
            ),
            // ❌ 不再使用本地 routes / onUnknownRoute / home，入口统一交给 AppRouter
          );
        },
      ),
    );
  }
}
