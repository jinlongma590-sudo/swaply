// lib/main.dart
import 'dart:async';
import 'dart:io';
import 'package:swaply/core/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator; // ✅ 退出 App 支持
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:swaply/pages/profile_page.dart';

// ====== 项目内的依赖 ======
import 'package:swaply/auth/login_screen.dart';
import 'package:swaply/auth/welcome_screen.dart';
import 'package:swaply/auth/reset_password_page.dart'; // ✅ Reset Password
import 'package:swaply/models/coupon.dart';
import 'package:swaply/models/listing_store.dart';
import 'package:swaply/models/verification_types.dart' as vt;
import 'package:swaply/pages/account_settings_page.dart';
import 'package:swaply/pages/coupon_management_page.dart';
import 'package:swaply/pages/home_page.dart' as swaply;
import 'package:swaply/pages/invite_friends_page.dart';
import 'package:swaply/pages/my_listings_page.dart';
import 'package:swaply/pages/offer_detail_page.dart';
import 'package:swaply/pages/product_detail_page.dart';
import 'package:swaply/pages/sell_form_page.dart';
import 'package:swaply/pages/task_management_page.dart';
import 'package:swaply/pages/verification_page.dart';
import 'package:swaply/services/auth_service.dart';
import 'package:swaply/services/coupon_service.dart';
import 'package:swaply/services/dual_favorites_service.dart';
import 'package:swaply/services/email_verification_service.dart';
import 'package:swaply/services/favorites_update_service.dart';
import 'package:swaply/services/listing_service.dart';
import 'package:swaply/services/notification_service.dart';
import 'package:swaply/services/profile_service.dart';
import 'package:swaply/services/reward_service.dart';
import 'package:swaply/services/deep_link_service.dart'; // ✅ DeepLinkService
import 'package:swaply/router/root_nav.dart'; // ✅ 全局 rootNavKey
import 'package:swaply/router/safe_navigator.dart';
import 'package:swaply/utils/verification_utils.dart' as vutils;
import 'package:swaply/widgets/my_rewards_tile.dart';
import 'package:swaply/widgets/verified_avatar.dart';
import 'package:swaply/widgets/verification_badge.dart' as vb;
import 'package:swaply/widgets/verification_badge_mini.dart';
// ✅ iOS 安全区域
import 'package:swaply/widgets/ios_insets_guard.dart';
import 'startup_screen.dart';

// ========= 全局 Auth 事件监听（只注册一次）=========
bool _authHookWired = false;
StreamSubscription<AuthState>? _globalAuthSub;
// ✅ 新增：通知订阅桥是否已挂载（避免重复）
bool _notifBridgeWired = false;
class LanguageProvider extends ChangeNotifier {
  Locale _current = const Locale('en');
  Locale get currentLocale => _current;
  bool get isEnglish => true;

  void changeLanguage([Locale? locale]) {
    _current = const Locale('en');
    notifyListeners();
  }

  void toggleLanguage() {
    _current = const Locale('en');
    notifyListeners();
  }
}

// ========= 全局 Auth 处理（带欢迎弹窗：一次性）=========
void wireAuthHook() {
  if (_authHookWired) return;
  _authHookWired = true;

  final auth = Supabase.instance.client.auth;
  _globalAuthSub?.cancel();
  _globalAuthSub = auth.onAuthStateChange.listen((data) async {
    final event = data.event;

    if (event == AuthChangeEvent.tokenRefreshed ||
        event == AuthChangeEvent.userUpdated) {
      debugPrint('[Auth] $event - skipping business logic');
      return;
    }

    debugPrint('[Auth] Event: $event');

    if (event == AuthChangeEvent.signedIn ||
        event == AuthChangeEvent.initialSession) {
      final u = auth.currentUser;
      if (u != null) {
        // ❌ 这里不再做 NotificationService 订阅（交给统一订阅桥）
        // ✅ 欢迎礼一次性逻辑
        try {
          final res = await RewardService.ensureWelcomeForCurrentUser();
          if (res.shouldPopup) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('new_user_welcome_pending_${u.id}', true);
          }
        } catch (e) {
          debugPrint('[Auth] ensureWelcomeForCurrentUser error: $e');
        }

        final ctx = rootNavKey.currentContext;
        if (ctx != null) {
          // ✅ 冷启动(initialSession)不再导航，避免二次 push；
          // 仅在真正登录(signedIn)且当前不在 /home 时导航到首页
          if (event == AuthChangeEvent.signedIn) {
            final current = ModalRoute.of(ctx)?.settings.name;
            if (current != '/home') {
              SafeNavigator.pushNamedAndRemoveUntil('/home', (route) => false);
            }
          }
        }
      }
    }

    if (event == AuthChangeEvent.signedOut) {
      // ❌ 取消订阅同样交给统一订阅桥处理
      CouponService.clearCache();
      DualFavoritesService.clearCache();
      RewardService.clearCache();

      final ctx = rootNavKey.currentContext;
      if (ctx != null) {
        SafeNavigator.pushNamedAndRemoveUntil('/home', (route) => false);
      }
    }
  });
}

// —— 简单 UTF-8 乱码修复（把“芒”“脙”等还原）——
String _fixUtf8Mojibake(String? raw) {
  if (raw == null || raw.isEmpty) return raw ?? '';
  var s = raw;

  if (!s.contains('冒') && !s.contains('脙') && !s.contains('芒')) return s;

  const map = <String, String>{};

  map.forEach((k, v) => s = s.replaceAll(k, v));
  return s;
}

// 简单的“欢迎礼包”弹窗
void _showWelcomeGiftDialog() {
  final ctx = rootNavKey.currentContext;
  if (ctx == null) return;

  showDialog(
    context: ctx,
    barrierDismissible: true,
    builder: (dCtx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.w)),
      contentPadding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 12.h),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60.w,
            height: 60.w,
            decoration: BoxDecoration(
              color: const Color(0xFF2196F3).withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.card_giftcard,
                size: 30.w, color: const Color(0xFF2196F3)),
          ),
          SizedBox(height: 12.h),
          Text(
            _fixUtf8Mojibake('Welcome gift 🎁'),
            style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 6.h),
          Text(
            _fixUtf8Mojibake(
              'A Welcome Coupon has been added to your account.\n'
                  'You can find it in My Coupons or My Rewards → Coupons tab.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.sp, color: Colors.black87),
          ),
          SizedBox(height: 14.h),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.emoji_events_outlined),
                  onPressed: () {
                    Navigator.of(dCtx).pop();
                    rootNavKey.currentState?.push(
                      MaterialPageRoute(builder: (_) => TaskManagementPage()),
                    );
                  },
                  label: Text(_fixUtf8Mojibake('My Rewards')),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.card_giftcard),
                  onPressed: () {
                    Navigator.of(dCtx).pop();
                    rootNavKey.currentState?.push(
                      MaterialPageRoute(
                        builder: (_) => CouponManagementPage(),
                      ),
                    );
                  },
                  label: Text(_fixUtf8Mojibake('My Coupons')),
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(),
            child: Text(_fixUtf8Mojibake('Later')),
          ),
        ],
      ),
    ),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // === 屏蔽 Supabase refresh session 噪音日志（仅开发期）===
      {
    final _orig = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null &&
          message.contains('supabase.auth: INFO: Refresh session')) {
        return; // 忽略这一条
      }
      _orig(message, wrapWidth: wrapWidth);
    };
  }
  // =====================================================

  // ========= 全局错误兜底 =========
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
  };
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: const Color(0xFFF5F5F5),
      child: Center(
        child: Container(
          margin: EdgeInsets.all(20.w),
          padding: EdgeInsets.all(12.w),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8.w),
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8.w)],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, color: Colors.red, size: 28.w),
                SizedBox(height: 6.h),
                Text(
                  'Something went wrong',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14.sp,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  details.exceptionAsString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54, fontSize: 12.sp),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  };

  // ✅ 启用 PKCE OAuth（移动端必须）
  await Supabase.initialize(
    url: 'https://rhckybselarzglkmlyqs.supabase.co',
    anonKey:
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJoY2t5YnNlbGFyemdsa21seXFzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTUwMTM0NTgsImV4cCI6MjA3MDU4OTQ1OH0.3I0T2DidiF-q9l2tWeHOjB31QogXHDqRtEjDn0RfVbU',
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      autoRefreshToken: true,
    ),
  );

  // ✅ Supabase 初始化后，runApp 前挂全局 Auth 监听（保留导航/欢迎礼逻辑）
  wireAuthHook();

  // === 统一的通知订阅桥（只在登录时订一次；退出时统一取消） ===
  if (!_notifBridgeWired) {
    _notifBridgeWired = true;

    final auth = Supabase.instance.client.auth;
    auth.onAuthStateChange.listen((data) async {
      final event = data.event;
      final user = auth.currentUser;

      if (event == AuthChangeEvent.signedIn && user != null) {
        await NotificationService.subscribeUser(user.id);
      }

      if (event == AuthChangeEvent.signedOut ||
          event == AuthChangeEvent.userDeleted) {
        await NotificationService.unsubscribe();
      }
    });
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => LanguageProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  bool _deepLinkStarted = false; // ✅ 防止 DeepLink 重复初始化

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 首帧渲染完成后启动深链（只一次）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _deepLinkStarted) return;
      _deepLinkStarted = true;

      // ✅ 新版 DeepLinkService：bootstrap + 100ms 后 flushQueue
      DeepLinkService.instance.bootstrap();
      Future.delayed(const Duration(milliseconds: 100), () {
        DeepLinkService.instance.flushQueue();
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        debugPrint('App resumed');
        break;
      case AppLifecycleState.paused:
        debugPrint('App paused');
        break;
      case AppLifecycleState.detached:
        debugPrint('App detached');
        break;
      case AppLifecycleState.inactive:
        debugPrint('App inactive');
        break;
      case AppLifecycleState.hidden:
        debugPrint('App hidden');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LanguageProvider>(
      builder: (context, languageProvider, child) {
        return ScreenUtilInit(
          designSize: const Size(375, 812),
          minTextAdapt: true,
          splitScreenMode: true,
          builder: (_, __) {
            return MaterialApp(
              title: 'Swaply',
              debugShowCheckedModeBanner: false,
              navigatorKey: rootNavKey, // ✅ 全局路由控制
              initialRoute: '/', // ✅ 统一走 '/'
              onGenerateRoute: _onGenerateRoute, // ✅ 路由工厂（在文件后半部分）
              locale: languageProvider.currentLocale,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('en')],
              builder: (context, widget) {
                return MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: const TextScaler.linear(1.0),
                  ),
                  child: widget!,
                );
              },
              theme: ThemeData(
                useMaterial3: true,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF2196F3),
                  primary: const Color(0xFF2196F3),
                ),
                appBarTheme: const AppBarTheme(
                  backgroundColor: Color(0xFF2196F3),
                  foregroundColor: Colors.white,
                  elevation: 0,
                ),
                elevatedButtonTheme: ElevatedButtonThemeData(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2196F3),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------- MainNavigationPage ----------------

class MainNavigationPage extends StatefulWidget {
  final bool isGuest;
  const MainNavigationPage({Key? key, this.isGuest = false}) : super(key: key);
  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

// 统一的 Primary Blue - 首页的深蓝
const Color _PRIMARY_BLUE = Color(0xFF1877F2);
// 统一标题高度，确保 SafeArea + 16dp 上边距
const double _CUSTOM_HEADER_HEIGHT = 110.0;

class _MainNavigationPageState extends State<MainNavigationPage>
    with TickerProviderStateMixin {
  int _selectedIndex = 0;
  int _notificationCount = 0;
  late AnimationController _sellButtonController;
  late Animation<double> _sellButtonAnimation;

  static bool _welcomeGiftChecked = false;

  @override
  void initState() {
    super.initState();
    _loadNotificationCount();

    _sellButtonController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _sellButtonAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _sellButtonController, curve: Curves.easeInOut),
    );

    final isGuest =
        Supabase.instance.client.auth.currentSession == null; // 当前访客态
    if (!isGuest) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) {
            _checkAndShowWelcomeGift();
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _sellButtonController.dispose();
    super.dispose();
  }

  Future<void> _checkAndShowWelcomeGift() async {
    if (_welcomeGiftChecked) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingKey = 'new_user_welcome_pending_${user.id}';
      final shownKey = 'welcome_gift_shown_${user.id}';

      final pending = prefs.getBool(pendingKey) ?? false;
      if (!pending) {
        _welcomeGiftChecked = true;
        return;
      }

      Map<String, dynamic>? row;
      try {
        final rows = await Supabase.instance.client
            .from('coupons')
            .select('id, code, title, description, expires_at, created_at')
            .eq('user_id', user.id)
            .eq('type', 'welcome')
            .eq('status', 'active')
            .order('created_at', ascending: false)
            .limit(1);
        if (rows is List && rows.isNotEmpty) {
          row = rows.first as Map<String, dynamic>;
        }
      } catch (_) {}

      _welcomeGiftChecked = true;
      await prefs.setBool(shownKey, true);
      await prefs.remove(pendingKey);

      if (!mounted) return;
      if (row != null) {
        _showLocalWelcomeDialog(row);
      } else {
        _showWelcomeGiftDialog();
      }
    } catch (e) {
      if (kDebugMode) {}
    }
  }

  void _showLocalWelcomeDialog(Map<String, dynamic> couponData) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dCtx) => AlertDialog(
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.w)),
        contentPadding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 12.h),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60.w,
              height: 60.w,
              decoration: BoxDecoration(
                color: const Color(0xFF2196F3).withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.card_giftcard,
                  size: 30.w, color: const Color(0xFF2196F3)),
            ),
            SizedBox(height: 12.h),
            Text(
              _fixUtf8Mojibake('Welcome gift 🎁'),
              style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 6.h),
            Text(
              _fixUtf8Mojibake(
                "Coupon Code: ${couponData['code']?.toString() ?? ''}\n\n"
                    "${couponData['description'] ?? 'Welcome to Swaply! Pin your item for free in any category.'}",
              ),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.sp, color: Colors.black87),
            ),
            SizedBox(height: 14.h),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.emoji_events_outlined),
                    onPressed: () {
                      Navigator.of(dCtx).pop();
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => TaskManagementPage()),
                      );
                    },
                    label: Text(_fixUtf8Mojibake('My Rewards')),
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.card_giftcard),
                    onPressed: () {
                      Navigator.of(dCtx).pop();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => CouponManagementPage()),
                      );
                    },
                    label: Text(_fixUtf8Mojibake('My Coupons')),
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: () => Navigator.of(dCtx).pop(),
              child: Text(_fixUtf8Mojibake('Later')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadNotificationCount() async {
    final isGuest =
        Supabase.instance.client.auth.currentSession == null; // 当前访客态
    if (!isGuest) {
      try {
        final count = await NotificationService.getUnreadNotificationsCount();
        if (mounted) {
          setState(() => _notificationCount = count);
        }
      } catch (e) {
        if (kDebugMode) {}
      }
    }
  }

  // ✅ 替换后的：物理返回键逻辑（Tab 内回退 -> 切回首页 -> 确认退出）
  void _onPopInvokedWithResult(bool didPop, Object? result) async {
    if (didPop) return;

    // 若不在首页，先切回首页
    if (_selectedIndex != 0) {
      if (mounted) setState(() => _selectedIndex = 0);
      return;
    }

    // 已在首页：Android 弹确认退出；iOS 不做强退
    if (Platform.isAndroid) {
      final ok = await _confirmExit(context);
      if (ok == true) {
        SystemNavigator.pop(); // 优雅退出到后台
      }
    }
  }

  // ✅ 新增：确认退出对话框
  Future<bool> _confirmExit(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.w),
          ),
          title: Text(
            'Exit Swaply?',
            style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700),
          ),
          content: Text(
            'Press Exit to close the app.',
            style: TextStyle(fontSize: 13.sp, height: 1.35),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).maybePop(false),
              child: Text(
                'Stay',
                style: TextStyle(fontSize: 13.sp, color: Colors.grey[700]),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogCtx).maybePop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _PRIMARY_BLUE,
                foregroundColor: Colors.white,
              ),
              child: Text('Exit', style: TextStyle(fontSize: 13.sp)),
            ),
          ],
        );
      },
    ) ??
        false;
  }

  void _clearNotifications() {
    setState(() => _notificationCount = 0);
  }

  void _showLoginRequired(String feature, BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.w)),
          title: Text(
            l10n.loginRequired,
            style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
          ),
          content: Text(
            l10n.loginRequiredMessage(feature),
            style: TextStyle(fontSize: 13.sp, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                l10n.cancel,
                style: TextStyle(fontSize: 13.sp, color: Colors.grey[600]),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2196F3), Color(0xFF1E88E5)],
                ),
                borderRadius: BorderRadius.circular(6.w),
              ),
              child: TextButton(
                onPressed: () {
                  SafeNavigator.pushNamedAndRemoveUntil('/welcome', (route) => false);
                },

                child: Text(
                  l10n.login,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTabNavigator(
      Widget root,
      LanguageProvider languageProvider,
      ) {
    return ChangeNotifierProvider<LanguageProvider>.value(
      value: languageProvider,
      child: root,
    );
  }

  void _navigateToHome() {
    setState(() => _selectedIndex = 0);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final languageProvider = Provider.of<LanguageProvider>(context);

    // ✅ 首页包一层 IosInsetsGuard
    final List<Widget> _pages = [
      _buildTabNavigator(
        IosInsetsGuard(child: const _HomeRoot()),
        languageProvider,
      ),
      _buildTabNavigator(
        _SavedRoot(
          isGuest:
          Supabase.instance.client.auth.currentSession == null, // guest态
          onNavigateToHome: _navigateToHome,
        ),
        languageProvider,
      ),
      _buildTabNavigator(
        _SellRoot(
          isGuest: Supabase.instance.client.auth.currentSession == null,
        ),
        languageProvider,
      ),
      _buildTabNavigator(
        _NotifRoot(
          onClearBadge: _clearNotifications,
          isGuest: Supabase.instance.client.auth.currentSession == null,
          onNotificationCountChanged: (count) {
            if (mounted) {
              setState(() => _notificationCount = count);
            }
          },
        ),
        languageProvider,
      ),
      _buildTabNavigator(
        _ProfileRoot(
          isGuest: Supabase.instance.client.auth.currentSession == null,
        ),
        languageProvider,
      ),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onPopInvokedWithResult,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: IndexedStack(
          index: _selectedIndex,
          children: _pages,
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 10.h,
                offset: Offset(0, -2.h),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              8.w,
              8.h,
              8.w,
              (Theme.of(context).platform == TargetPlatform.iOS &&
                  MediaQuery.of(context).padding.bottom > 0)
                  ? 10.0.h
                  : 8.0.h,
            ),
            child: SizedBox(
              height: 56.h,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildCompactNavItem(
                    icon: Icons.home_outlined,
                    activeIcon: Icons.home_rounded,
                    label: l10n.home,
                    index: 0,
                    context: context,
                  ),
                  _buildCompactNavItem(
                    icon: Icons.bookmark_outline_rounded,
                    activeIcon: Icons.bookmark_rounded,
                    label: l10n.saved,
                    index: 1,
                    context: context,
                  ),
                  _buildCentralSellButton(context),
                  _buildCompactNavItemWithBadge(
                    icon: Icons.notifications_outlined,
                    activeIcon: Icons.notifications_rounded,
                    label: l10n.notifications,
                    index: 3,
                    badgeCount: _notificationCount,
                    context: context,
                  ),
                  _buildCompactNavItem(
                    icon: Icons.person_outline_rounded,
                    activeIcon: Icons.person_rounded,
                    label: l10n.profile,
                    index: 4,
                    context: context,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactNavItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int index,
    required BuildContext context,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final bool isSelected = _selectedIndex == index;

    return GestureDetector(
      onTap: () {
        if (Supabase.instance.client.auth.currentSession == null &&
            (index == 1)) {
          _showLoginRequired(l10n.saveItems, context);
          return;
        }
        setState(() => _selectedIndex = index);
      },
      child: SizedBox(
        width: 60.w,
        height: 52.h,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 4.h),
          decoration: BoxDecoration(
            color:
            isSelected ? _PRIMARY_BLUE.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(14.w),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: Icon(
                  isSelected ? activeIcon : icon,
                  key: ValueKey('${index}_${isSelected}'),
                  color: isSelected ? _PRIMARY_BLUE : Colors.grey[600],
                  size: 22.w,
                ),
              ),
              SizedBox(height: 2.h),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 150),
                style: TextStyle(
                  color: isSelected ? _PRIMARY_BLUE : Colors.grey[600],
                  fontSize: 8.5.sp,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactNavItemWithBadge({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int index,
    required int badgeCount,
    required BuildContext context,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final bool isSelected = _selectedIndex == index;

    return GestureDetector(
      onTap: () {
        if (Supabase.instance.client.auth.currentSession == null) {
          _showLoginRequired(l10n.receiveNotifications, context);
          return;
        }
        setState(() {
          _selectedIndex = index;
          if (index == 3) _loadNotificationCount();
        });
      },
      child: SizedBox(
        width: 60.w,
        height: 52.h,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 4.h),
          decoration: BoxDecoration(
            color:
            isSelected ? _PRIMARY_BLUE.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(14.w),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    child: Icon(
                      isSelected ? activeIcon : icon,
                      key: ValueKey('${index}_${isSelected}'),
                      color: isSelected ? _PRIMARY_BLUE : Colors.grey[600],
                      size: 22.w,
                    ),
                  ),
                  if (badgeCount > 0 &&
                      Supabase.instance.client.auth.currentSession != null)
                    Positioned(
                      right: -6.w,
                      top: -4.h,
                      child: AnimatedScale(
                        scale: badgeCount > 0 ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          width: badgeCount > 9 ? 20.w : 16.w,
                          height: 16.h,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFF4757), Color(0xFFFF3742)],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                            borderRadius: BorderRadius.circular(8.w),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withOpacity(0.3),
                                blurRadius: 3.w,
                                offset: Offset(0, 1.h),
                              ),
                            ],
                            border: Border.all(
                              color: Colors.white,
                              width: 1.w,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              badgeCount > 99 ? '99+' : '$badgeCount',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 8.sp,
                                fontWeight: FontWeight.w800,
                                height: 1.0,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: 2.h),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 150),
                style: TextStyle(
                  color: isSelected ? _PRIMARY_BLUE : Colors.grey[600],
                  fontSize: 8.5.sp,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCentralSellButton(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bool isSelected = _selectedIndex == 2;

    return GestureDetector(
      onTapDown: (_) => _sellButtonController.forward(),
      onTapUp: (_) => _sellButtonController.reverse(),
      onTapCancel: () => _sellButtonController.reverse(),
      onTap: () {
        if (Supabase.instance.client.auth.currentSession == null) {
          _showLoginRequired(l10n.postListings, context);
        } else {
          setState(() => _selectedIndex = 2);
        }
      },
      child: AnimatedBuilder(
        animation: _sellButtonAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _sellButtonAnimation.value,
            child: Container(
              width: 56.w,
              height: 46.h,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isSelected
                      ? [
                    const Color(0xFF1565C0),
                    _PRIMARY_BLUE,
                    const Color(0xFF42A5F5),
                  ]
                      : [
                    _PRIMARY_BLUE,
                    const Color(0xFF1E88E5),
                    const Color(0xFF1976D2),
                  ],
                ),
                borderRadius: BorderRadius.circular(28.w),
                boxShadow: [
                  BoxShadow(
                    color: _PRIMARY_BLUE.withOpacity(0.4),
                    blurRadius: isSelected ? 12.h : 10.h,
                    offset: Offset(0, isSelected ? 4.h : 3.h),
                    spreadRadius: isSelected ? 2.w : 1.w,
                  ),
                  BoxShadow(
                    color: _PRIMARY_BLUE.withOpacity(0.2),
                    blurRadius: 6.h,
                    offset: Offset(0, 2.h),
                  ),
                ],
                border: Border.all(
                  color: Colors.white,
                  width: 3.w,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedRotation(
                    turns: isSelected ? 0.125 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.add_rounded,
                      color: Colors.white,
                      size: 22.h,
                    ),
                  ),
                  SizedBox(height: 0.5.h),
                  Text(
                    l10n.sell,
                    textHeightBehavior: const TextHeightBehavior(
                      applyHeightToFirstAscent: false,
                      applyHeightToLastDescent: false,
                    ),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 7.5.sp,
                      height: 1.0,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                      shadows: [
                        Shadow(
                          color: Colors.black.withOpacity(0.3),
                          offset: Offset(0, 0.5.h),
                          blurRadius: 1.w,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/* ------------------------------------------------ */
/* =========== TOP-LEVEL WIDGETS START HERE =========== */
/* ------------------------------------------------ */

class _HomeRoot extends StatelessWidget {
  const _HomeRoot();
  @override
  Widget build(BuildContext context) => const swaply.HomePage();
}

class _SavedRoot extends StatelessWidget {
  final bool isGuest;
  final VoidCallback? onNavigateToHome;
  const _SavedRoot({this.isGuest = false, this.onNavigateToHome});
  @override
  Widget build(BuildContext context) => SavedPage(
    isGuest: isGuest,
    onNavigateToHome: onNavigateToHome,
  );
}

class _SellRoot extends StatelessWidget {
  final bool isGuest;
  const _SellRoot({this.isGuest = false});
  @override
  Widget build(BuildContext context) => SellPage(isGuest: isGuest);
}

class _NotifRoot extends StatelessWidget {
  final VoidCallback onClearBadge;
  final bool isGuest;
  final Function(int)? onNotificationCountChanged;

  const _NotifRoot({
    required this.onClearBadge,
    this.isGuest = false,
    this.onNotificationCountChanged,
  });

  @override
  Widget build(BuildContext context) => NotificationPage(
    onClearBadge: onClearBadge,
    isGuest: isGuest,
    onNotificationCountChanged: onNotificationCountChanged,
  );
}

class _ProfileRoot extends StatelessWidget {
  final bool isGuest;
  const _ProfileRoot({this.isGuest = false});
  @override
  Widget build(BuildContext context) => ProfilePage(isGuest: isGuest);
}

/// ===== 路由工厂（阶段 3 新增）=====
Route<dynamic> _onGenerateRoute(RouteSettings settings) {
  final String name = settings.name ?? '/';
  final bool hasSession = Supabase.instance.client.auth.currentSession != null;

  Widget page;

  switch (name) {
  // 统一入口：根据会话态决定落到哪
    case '/':
      page = hasSession
          ? MainNavigationPage(isGuest: false)
          : const WelcomeScreen();
      return _fade(page, name);

  // 显式首页
    case '/home':
      page = MainNavigationPage(isGuest: !hasSession);
      return _fade(page, name);

  // 显式欢迎/登录
    case '/welcome':
      page = const WelcomeScreen();
      return _fade(page, name);

    case '/login':
      page = const LoginScreen();
      return _fade(page, name);

  // 优惠券管理
    case '/coupons':
      page = CouponManagementPage();
      return _fade(page, name);

  // 重置密码（你已 import 了）
    case '/reset-password':
      page = const ResetPasswordPage();
      return _fade(page, name);

  // ✅ 新增：Listing 详情
    case '/listing':
      final id = settings.arguments as String;
      page = ProductDetailPage(productId: id);
      return _fade(page, name);

  // 兜底：任何未知路由都回首页（按当前会话态）
    default:
      page = MainNavigationPage(isGuest: !hasSession);
      return _fade(page, '/home');
  }
}

// 统一淡入转场（如你已有同名函数，可用这版覆盖）
PageRoute _fade(Widget page, String name) {
  return PageRouteBuilder(
    settings: RouteSettings(name: name),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
    transitionDuration: const Duration(milliseconds: 180),
  );
}
/* ---------------- Saved Page (收藏页) START ---------------- */

class SavedPage extends StatefulWidget {
  final bool isGuest;
  final VoidCallback? onNavigateToHome;
  const SavedPage({Key? key, this.isGuest = false, this.onNavigateToHome})
      : super(key: key);

  @override
  State<SavedPage> createState() => _SavedPageState();
}

class _SavedPageState extends State<SavedPage> with WidgetsBindingObserver {
  List<Map<String, dynamic>> _favoriteItems = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;
  Timer? _autoRefreshTimer;
  StreamSubscription<FavoriteUpdateEvent>? _favoritesSubscription;

  // 自定义头部组件，用于统一蓝色、大标题和间距
  Widget _buildCustomHeader(String title, {bool hasMenu = true}) {
    return Container(
      color: _PRIMARY_BLUE, // 统一的深蓝
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 16.h), // 标题距安全区顶部约 16dp
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24.sp, // 统一字体大小
                        fontWeight: FontWeight.w600, // SemiBold
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (hasMenu && _favoriteItems.isNotEmpty && !_isLoading)
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert_rounded,
                          color: Colors.white, size: 16.w),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.w)),
                      onSelected: (value) {
                        if (value == 'clear_all') {
                          _showClearAllDialog();
                        }
                      },
                      itemBuilder: (BuildContext context) => [
                        PopupMenuItem(
                          value: 'clear_all',
                          child: Row(
                            children: [
                              Icon(Icons.clear_all_rounded,
                                  color: Colors.red, size: 12.w),
                              SizedBox(width: 8.w),
                              Text('Clear All',
                                  style: TextStyle(fontSize: 11.sp)),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            SizedBox(height: 16.h),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (!widget.isGuest) {
      _loadFavorites();
      // 氓聬炉氓艩篓猫鈥÷ヅ犅ニ喡访︹€撀懊ヂ∶︹€斅睹モ劉篓茂录藛忙炉聫30莽搂鈥櫭βｂ偓忙鸥楼盲赂鈧β∶尖€?
      _startAutoRefresh();
      // 猫庐戮莽陆庐忙鈥澛睹ㄢ€斅徝︹€郝疵︹€撀懊р€衡€樏ヂ惵?
      _setupFavoritesListener();
    } else {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoRefreshTimer?.cancel();
    _favoritesSubscription?.cancel();
    super.dispose();
  }

  // 芒艙鈥?盲驴庐氓陇聧茂录拧猫驴鈩⒚┾€∨捗ヂ衡€澝ッλ溌р€澟该モ€樎矫モ€樎ε撆该モ€号久捌捗寂捗ㄢ偓艗盲赂聧忙藴炉猫路炉莽鈥澛泵β澛∶р€郝?
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !widget.isGuest) {
      // 氓潞鈥澝р€澛┾€÷嵜︹€撀懊β库偓忙麓禄忙鈥斅睹ニ喡访︹€撀懊︹€⒙懊β嵚?
      _loadFavorites();
    }
  }

  /// 猫庐戮莽陆庐忙鈥澛睹ㄢ€斅徝︹€郝疵︹€撀懊р€衡€樏ヂ惵?
  void _setupFavoritesListener() {
    _favoritesSubscription = FavoritesUpdateService().favoritesStream.listen(
          (event) {
        if (!mounted || widget.isGuest) return;

        if (kDebugMode) {}

        if (event.isAdded && event.listingData != null) {
          // 忙路禄氓艩 氓藛掳忙鈥澛睹ㄢ€斅徝寂∶€姑ヂ嵚趁β仿幻ヅ?氓藛掳忙艙卢氓艙掳氓藛鈥斆÷?
          _addToLocalFavorites(event.listingData!);
        } else if (!event.isAdded) {
          // 盲禄沤忙鈥澛睹ㄢ€斅徝幻┾劉陇茂录拧莽芦鈥姑ヂ嵚趁ぢ慌矫ε撀ヅ撀懊ニ嗏€斆÷幻┾劉陇
          _removeFromLocalFavorites(event.listingId);
        }
      },
      onError: (error) {
        if (kDebugMode) print('Error in favorites stream: $error');
      },
    );
  }

  /// 莽芦鈥姑ヂ嵚趁β仿幻ヅ?氓藛掳忙艙卢氓艙掳忙鈥澛睹ㄢ€斅徝ニ嗏€斆÷?
  void _addToLocalFavorites(Map<String, dynamic> listingData) {
    try {
      // 忙拢鈧ε嘎ッλ溌ヂ惵γヂ仿裁ヂ溍ヅ撀?
      final listingId = listingData['id']?.toString();
      if (listingId == null) return;

      final exists = _favoriteItems.any((item) =>
      item['listing_id']?.toString() == listingId ||
          item['listing']?['id']?.toString() == listingId);

      if (!exists) {
        // 忙啪鈥灻┾偓 莽卢娄氓聬藛忙鈥澛睹ㄢ€斅徝?录氓录聫莽拧鈥灻︹€⒙懊β嵚?
        final favoriteItem = {
          'listing_id': listingId,
          'listing': _safeMapConvert(listingData),
          'created_at': DateTime.now().toIso8601String(),
        };

        setState(() {
          _favoriteItems.insert(0, favoriteItem); // 忙聫鈥櫭モ€βッニ喡懊ニ嗏€斆÷ヂ尖偓氓陇麓
        });

        if (kDebugMode) {}
      }
    } catch (e) {
      if (kDebugMode) print('Error adding to local favorites: $e');
    }
  }

  /// 莽芦鈥姑ヂ嵚趁ぢ慌矫ε撀ヅ撀懊︹€澛睹ㄢ€斅徝ニ嗏€斆÷幻┾劉陇
  void _removeFromLocalFavorites(String listingId) {
    try {
      final initialLength = _favoriteItems.length;

      setState(() {
        _favoriteItems.removeWhere((item) =>
        item['listing_id']?.toString() == listingId ||
            item['listing']?['id']?.toString() == listingId);
      });

      if (_favoriteItems.length < initialLength) {
        if (kDebugMode) {}
      }
    } catch (e) {
      if (kDebugMode) print('Error removing from local favorites: $e');
    }
  }

  /// 氓聬炉氓艩篓猫鈥÷ヅ犅ニ喡访︹€撀懊ヂ∶︹€斅睹モ劉篓
  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!widget.isGuest && mounted && !_isRefreshing) {
        if (kDebugMode) print('猫鈥÷ヅ犅ニ喡访︹€撀懊︹€澛睹ㄢ€斅徝ニ嗏€斆÷?..');
        _loadFavorites();
      }
    });
  }

  /// 氓庐鈥懊モ€β♀€灻甭幻ヅ锯€姑铰β嵚⒚︹€撀姑β斥€?
  Map<String, dynamic> _safeMapConvert(dynamic input) {
    if (input == null) return <String, dynamic>{};

    if (input is Map<String, dynamic>) {
      return input;
    } else if (input is Map) {
      try {
        return Map<String, dynamic>.from(input);
      } catch (e) {
        if (kDebugMode) print('莽卤禄氓啪鈥姑铰β嵚⒚ヂぢ泵绰? $e');
        return <String, dynamic>{};
      }
    }

    return <String, dynamic>{};
  }

  /// 氓庐鈥懊モ€βㄅ铰访ヂ忊€撁ヂ€斆γぢ嘎裁モ偓录
  String _safeGetString(Map<String, dynamic> map, String key,
      {String defaultValue = ''}) {
    try {
      return map[key]?.toString() ?? defaultValue;
    } catch (e) {
      if (kDebugMode) print('Error getting string for key $key: $e');
      return defaultValue;
    }
  }

  /// 氓艩 猫陆陆忙鈥澛睹ㄢ€斅徝ニ嗏€斆÷?- 盲驴庐氓陇聧茂录拧盲陆驴莽鈥澛?DualFavoritesService
  Future<void> _loadFavorites() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Please login to view your favorites';
      });
      return;
    }

    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      if (kDebugMode) {}

      // 盲驴庐氓陇聧茂录拧盲陆驴莽鈥澛?DualFavoritesService 猫沤路氓聫鈥撁︹€澛睹ㄢ€斅徝ニ嗏€斆÷妓喢ぢ慌?favorites 猫隆篓茂录鈥?
      final rawItems = await DualFavoritesService.getUserFavorites(
        userId: user.id,
        limit: 100,
      );

      if (mounted) {
        // 氓庐鈥懊モ€β铰β嵚⒚︹€⒙懊β嵚?
        final safeItems = <Map<String, dynamic>>[];
        for (final item in rawItems) {
          final safeItem = _safeMapConvert(item);
          if (safeItem.isNotEmpty) {
            // 莽隆庐盲驴聺 listing 忙鈥⒙懊β嵚ぢ古该λ溌ヂ€懊モ€β铰β嵚⒚♀€?
            if (safeItem.containsKey('listing')) {
              safeItem['listing'] = _safeMapConvert(safeItem['listing']);
            }
            safeItems.add(safeItem);
          }
        }

        setState(() {
          _favoriteItems = safeItems;
          _isLoading = false;
        });

        if (kDebugMode) {}
      }
    } catch (e) {
      if (kDebugMode) {}

      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load favorites. Please try again.';
        });
      }
    }
  }

  /// 氓藛路忙鈥撀懊︹€澛睹ㄢ€斅徝ニ嗏€斆÷?
  Future<void> _refreshFavorites() async {
    setState(() => _isRefreshing = true);
    await _loadFavorites();
    setState(() => _isRefreshing = false);
  }

  /// 盲禄沤忙鈥澛睹ㄢ€斅徝ヂぢ姑幻┾劉陇氓鈥⑩€犆モ€溌?- 盲驴庐氓陇聧茂录拧盲陆驴莽鈥澛?DualFavoritesService
  Future<void> _removeFromFavorites(String listingId, int index) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      // 盲驴庐氓陇聧茂录拧盲陆驴莽鈥澛?DualFavoritesService 氓聬艗忙颅楼莽搂禄茅鈩⒙?
      final success = await DualFavoritesService.removeFromFavorites(
        userId: user.id,
        listingId: listingId,
      );

      if (success && mounted) {
        setState(() {
          _favoriteItems.removeAt(index);
        });

        // 氓聫鈥樏┾偓聛氓庐啪忙鈥斅睹︹€郝疵︹€撀懊┾偓拧莽鸥楼
        FavoritesUpdateService().notifyFavoriteChanged(
          listingId: listingId,
          isAdded: false,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 12.w),
                SizedBox(width: 4.w),
                const Text('Removed from favorites and wishlist'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6.w)),
            margin: EdgeInsets.all(8.w),
          ),
        );
      } else {
        throw Exception('Failed to remove from favorites');
      }
    } catch (e) {
      if (kDebugMode) {}

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline_rounded,
                  color: Colors.white, size: 12.w),
              SizedBox(width: 4.w),
              const Text('Failed to remove item. Please try again.'),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.w)),
          margin: EdgeInsets.all(8.w),
        ),
      );
    }
  }

  /// 猫沤路氓聫鈥撁モ€⑩€犆モ€溌伱モ€郝久р€扳€?- 氓庐鈥懊モ€βр€八喢ε撀?
  String _getListingImage(Map<String, dynamic> listing) {
    try {
      final images = listing['images'] ?? listing['image_urls'];
      if (images is List && images.isNotEmpty) {
        return images.first.toString();
      }
    } catch (e) {
      if (kDebugMode) print('Error getting listing image: $e');
    }
    return 'assets/images/placeholder.jpg';
  }

  /// 忙 录氓录聫氓艗鈥撁ぢ宦访?录 - 氓庐鈥懊モ€βр€八喢ε撀?
  String _formatPrice(dynamic price) {
    if (price == null) return 'Price not available';

    try {
      final priceStr = price.toString();
      if (priceStr.startsWith('\$')) return priceStr;

      final numPrice = double.tryParse(priceStr);
      if (numPrice != null) {
        return '\$${numPrice.toStringAsFixed(0)}';
      }

      return priceStr.isNotEmpty ? priceStr : 'Price not available';
    } catch (e) {
      if (kDebugMode) print('Error formatting price: $e');
      return 'Price not available';
    }
  }

  /// 忙啪鈥灻ヂ宦好モ€⑩€犆モ€溌伱ヂ嵚∶р€扳€?- 盲驴庐氓陇聧莽鈥八喢ε撀?
  Widget _buildFavoriteCard(Map<String, dynamic> item, int index) {
    try {
      // 氓庐鈥懊モ€β♀€灻甭幻ヅ锯€姑铰β嵚?- 莽禄鸥盲赂鈧ぢ铰棵р€澛?'listing' 茅鈥澛?
      final safeListing = _safeMapConvert(item['listing'] ?? {});
      final safeItem = _safeMapConvert(item);

      final listingId = _safeGetString(safeItem, 'listing_id');
      if (listingId.isEmpty) {
        if (kDebugMode)
          print('Warning: Empty listing ID for item at index $index');
        return const SizedBox.shrink();
      }

      final title =
      _safeGetString(safeListing, 'title', defaultValue: 'Unknown Item');
      final price = _formatPrice(safeListing['price']);
      final city = _safeGetString(safeListing, 'city');
      final imageUrl = _getListingImage(safeListing);
      final createdAt = _safeGetString(safeItem, 'created_at');

      // 忙 录氓录聫氓艗鈥撁︹€澛睹ㄢ€斅徝︹€斅睹┾€斅?
      final timeAdded = DualFavoritesService.formatSavedTime(createdAt);

      return Card(
        margin: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.w)),
        color: Colors.white,
        child: InkWell(
          onTap: () {
            if (listingId.isNotEmpty) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProductDetailPage(
                    productId: listingId,
                    productData: safeListing,
                  ),
                ),
              ).then((_) {
                // 盲禄沤氓鈥⑩€犆モ€溌伱γζ掆€γ┞÷得库€澝モ€号久ヂ恻矫ニ喡访︹€撀懊ニ嗏€斆÷?
                _loadFavorites();
              });
            }
          },
          borderRadius: BorderRadius.circular(8.w),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8.w),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 4.w,
                  offset: Offset(0, 1.h),
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.all(8.w),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 氓鈥⑩€犆モ€溌伱モ€郝久р€扳€?- 莽录漏氓掳聫
                  Hero(
                    tag: 'favorite_image_$listingId',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6.w),
                      child: Container(
                        width: 50.w,
                        height: 50.w,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(6.w),
                        ),
                        child: imageUrl.startsWith('http')
                            ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          loadingBuilder:
                              (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Center(
                              child: SizedBox(
                                width: 12.w,
                                height: 12.w,
                                child: CircularProgressIndicator(
                                  value: loadingProgress
                                      .expectedTotalBytes !=
                                      null
                                      ? loadingProgress
                                      .cumulativeBytesLoaded /
                                      loadingProgress
                                          .expectedTotalBytes!
                                      : null,
                                  strokeWidth: 1.w,
                                  valueColor:
                                  const AlwaysStoppedAnimation<Color>(
                                      Color(0xFF2196F3)),
                                ),
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(6.w),
                              ),
                              child: Icon(
                                Icons.image_not_supported_rounded,
                                color: Colors.grey[400],
                                size: 18.w,
                              ),
                            );
                          },
                        )
                            : Container(
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(6.w),
                          ),
                          child: Icon(
                            Icons.image_not_supported_rounded,
                            color: Colors.grey[400],
                            size: 18.w,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 8.w),

                  // 氓鈥⑩€犆モ€溌伱ぢ柯∶β伮?- 莽录漏氓掳聫氓颅鈥斆ぢ解€溍モ€櫯捗┾€斅疵仿?
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 2.h),
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 4.w, vertical: 1.h),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2196F3).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4.w),
                          ),
                          child: Text(
                            price,
                            style: TextStyle(
                              fontSize: 11.sp,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF2196F3),
                            ),
                          ),
                        ),
                        SizedBox(height: 3.h),
                        if (city.isNotEmpty)
                          Row(
                            children: [
                              Icon(
                                Icons.location_on_rounded,
                                size: 8.w,
                                color: Colors.grey[500],
                              ),
                              SizedBox(width: 2.w),
                              Expanded(
                                child: Text(
                                  city,
                                  style: TextStyle(
                                    fontSize: 9.sp,
                                    color: Colors.grey[600],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        SizedBox(height: 2.h),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time_rounded,
                              size: 8.w,
                              color: Colors.grey[400],
                            ),
                            SizedBox(width: 2.w),
                            Text(
                              'Saved $timeAdded',
                              style: TextStyle(
                                fontSize: 8.sp,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // 莽搂禄茅鈩⒙っε掆€懊┾€櫬?- 莽录漏氓掳聫
                  Container(
                    margin: EdgeInsets.only(left: 4.w),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2196F3).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6.w),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _showRemoveDialog(listingId, title, index),
                        borderRadius: BorderRadius.circular(6.w),
                        child: Padding(
                          padding: EdgeInsets.all(6.w),
                          child: Icon(
                            Icons.bookmark_rounded,
                            color: const Color(0xFF2196F3),
                            size: 14.w,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (e, stackTrace) {
      if (kDebugMode) {}
      // 猫驴鈥澝モ€号久┾€濃劉猫炉炉氓聧隆莽鈥扳€∶ㄢ偓艗盲赂聧忙藴炉氓麓漏忙潞茠
      return Container(
        margin: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(8.w),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade400, size: 20.w),
            SizedBox(width: 8.w),
            Expanded(
              child: Text(
                'Error loading item',
                style: TextStyle(
                  fontSize: 11.sp,
                  color: Colors.red.shade700,
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  /// 忙藴戮莽陇潞莽搂禄茅鈩⒙っ÷っヂ姑澝β♀€?
  void _showRemoveDialog(String listingId, String title, int index) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.w)),
          title: Row(
            children: [
              Container(
                padding: EdgeInsets.all(4.w),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4.w),
                ),
                child: Icon(Icons.delete_outline_rounded,
                    color: Colors.red, size: 14.w),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  'Remove from Favorites',
                  style:
                  TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to remove "$title" from your favorites and wishlist?',
            style: TextStyle(fontSize: 11.sp, height: 1.3),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel',
                  style: TextStyle(fontSize: 11.sp, color: Colors.grey[600])),
            ),
            Container(
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(4.w),
              ),
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _removeFromFavorites(listingId, index);
                },
                child: Text(
                  'Remove',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 忙啪鈥灻ヂ宦好┞好犅睹︹偓聛 - 莽麓搂氓鈥♀€樏р€八?
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(20.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80.w,
              height: 80.w,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF2196F3).withOpacity(0.1),
                    const Color(0xFF1E88E5).withOpacity(0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(40.w),
                border: Border.all(
                  color: const Color(0xFF2196F3).withOpacity(0.2),
                  width: 1.w,
                ),
              ),
              child: Icon(
                Icons.bookmark_outline_rounded,
                size: 40.w,
                color: const Color(0xFF2196F3),
              ),
            ),
            SizedBox(height: 16.h),
            Text(
              'No Favorites Yet',
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
                letterSpacing: -0.2,
              ),
            ),
            SizedBox(height: 6.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: Text(
                'Start adding items you like to your favorites by tapping the bookmark icon on any listing.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.sp,
                  color: Colors.grey[600],
                  height: 1.3,
                ),
              ),
            ),
            SizedBox(height: 20.h),
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2196F3), Color(0xFF1E88E5)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(8.w),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2196F3).withOpacity(0.3),
                    blurRadius: 8.w,
                    offset: Offset(0, 3.h),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: () {
                  // 盲驴庐氓陇聧茂录拧盲陆驴莽鈥澛モ€号久捌捗モ€÷矫︹€⒙懊ヂ济ㄋ喡ニ喡懊┞︹€撁┞÷?
                  if (widget.onNavigateToHome != null) {
                    widget.onNavigateToHome!();
                  } else {
                    // 氓陇鈥∶р€澛︹€撀姑β∷喢寂∶ヂ悸姑モ€÷好ニ喡懊┞÷睹ヂ扁€?
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding:
                  EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.w),
                  ),
                ),
                icon: Icon(Icons.explore_rounded,
                    size: 12.w, color: Colors.white),
                label: Text(
                  'Browse Items',
                  style: TextStyle(
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 忙啪鈥灻ヂ宦好┾€濃劉猫炉炉莽艩露忙鈧?
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(20.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 70.w,
              height: 70.w,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(35.w),
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 35.w,
                color: Colors.red[400],
              ),
            ),
            SizedBox(height: 14.h),
            Text(
              'Something went wrong',
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              _errorMessage ?? 'Failed to load your favorites.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.sp,
                color: Colors.grey[600],
                height: 1.3,
              ),
            ),
            SizedBox(height: 16.h),
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2196F3), Color(0xFF1E88E5)],
                ),
                borderRadius: BorderRadius.circular(8.w),
              ),
              child: ElevatedButton.icon(
                onPressed: _loadFavorites,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding:
                  EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.w),
                  ),
                ),
                icon: Icon(Icons.refresh_rounded, size: 12.w),
                label: Text(
                  'Try Again',
                  style:
                  TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 氓庐鈥懊モ€βㄅ铰访ヂ忊€撁ε撀ヅ撀懊ヅ掆€撁寂捗┞伮棵モ€β嵜ぢ嘎好┞?
    AppLocalizations? l10n;
    try {
      l10n = AppLocalizations.of(context);
    } catch (e) {
      if (kDebugMode) {}
    }

    // 猫庐驴氓庐垄莽艩露忙鈧?
    if (widget.isGuest) {
      // Guest View: 统一蓝色
      return Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          backgroundColor: _PRIMARY_BLUE, // 统一蓝色
          title: Text(
            l10n?.myFavorites ?? 'My Favorites',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
          elevation: 0,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80.w,
                height: 80.w,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(40.w),
                ),
                child: Icon(
                  Icons.lock_outline_rounded,
                  size: 40.w,
                  color: Colors.grey[500],
                ),
              ),
              SizedBox(height: 16.h),
              Text(
                l10n?.loginRequired ?? 'Login Required',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 6.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.w),
                child: Text(
                  l10n?.loginToSaveFavorites ??
                      'Please login to view and save your favorite items.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 11.sp,
                    height: 1.3,
                  ),
                ),
              ),
              SizedBox(height: 20.h),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    // 统一蓝色
                    colors: [_PRIMARY_BLUE, const Color(0xFF1E88E5)],
                  ),
                  borderRadius: BorderRadius.circular(8.w),
                  boxShadow: [
                    BoxShadow(
                      color: _PRIMARY_BLUE.withOpacity(0.3),
                      blurRadius: 8.w,
                      offset: Offset(0, 3.h),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: () {
                    SafeNavigator.pushNamedAndRemoveUntil('/welcome', (route) => false);
                  },

                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding:
                    EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.w),
                    ),
                  ),
                  icon: Icon(Icons.login_rounded,
                      size: 12.w, color: Colors.white),
                  label: Text(
                    l10n?.loginNow ?? 'Login Now',
                    style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 氓路虏莽鈩⒙幻ヂ解€⒚犅睹︹偓聛
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      // 头部使用自定义组件
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(_CUSTOM_HEADER_HEIGHT), // 使用统一高度
        child: _buildCustomHeader('My Favorites (${_favoriteItems.length})'),
      ),
      body: _isLoading
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 24.w,
              height: 24.w,
              child: CircularProgressIndicator(
                valueColor: const AlwaysStoppedAnimation<Color>(
                    _PRIMARY_BLUE), // 统一蓝色
                strokeWidth: 2.w,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Loading favorites...',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 11.sp,
              ),
            ),
          ],
        ),
      )
          : _errorMessage != null
          ? _buildErrorState()
          : _favoriteItems.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
        onRefresh: _refreshFavorites,
        color: _PRIMARY_BLUE, // 统一蓝色
        backgroundColor: Colors.white,
        strokeWidth: 2.w,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(vertical: 6.h),
          itemCount: _favoriteItems.length,
          itemBuilder: (context, index) {
            return _buildFavoriteCard(
                _favoriteItems[index], index);
          },
        ),
      ),
    );
  }

  /// 忙藴戮莽陇潞忙赂鈥γ┞好︹€扳偓忙舱鈥懊÷っヂ姑澝β♀€?
  void _showClearAllDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.w)),
          title: Row(
            children: [
              Container(
                padding: EdgeInsets.all(4.w),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4.w),
                ),
                child:
                Icon(Icons.warning_outlined, color: Colors.red, size: 14.w),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  'Clear All Favorites',
                  style:
                  TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to remove all items from your favorites and wishlist? This action cannot be undone.',
            style: TextStyle(fontSize: 11.sp, height: 1.3),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel',
                  style: TextStyle(fontSize: 11.sp, color: Colors.grey[600])),
            ),
            Container(
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(4.w),
              ),
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _clearAllFavorites();
                },
                child: Text(
                  'Clear All',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 忙赂鈥γ┞好︹€扳偓忙舱鈥懊︹€澛睹ㄢ€斅?- 盲驴庐氓陇聧茂录拧盲陆驴莽鈥澛?DualFavoritesService 氓聬艗忙颅楼忙赂鈥γ┞?
  Future<void> _clearAllFavorites() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      // 氓鈥λ喢ぢ柯澝ヂ溍ヂ解€溍モ€奥嵜ニ嗏€斆÷┞÷姑寂捗р€澛ぢ号矫ヂ忊€樏┾偓聛茅鈧∶嘎?
      final currentItems = List<Map<String, dynamic>>.from(_favoriteItems);

      // 盲驴庐氓陇聧茂录拧盲陆驴莽鈥澛?DualFavoritesService 氓聬艗忙颅楼忙赂鈥γ┞?
      final success =
      await DualFavoritesService.clearUserFavorites(userId: user.id);

      if (success && mounted) {
        setState(() {
          _favoriteItems.clear();
        });

        // 氓聫鈥樏┾偓聛氓庐啪忙鈥斅睹β糕€γ┞好┾偓拧莽鸥楼
        for (final item in currentItems) {
          final listingId = item['listing_id']?.toString();
          if (listingId != null) {
            FavoritesUpdateService().notifyFavoriteChanged(
              listingId: listingId,
              isAdded: false,
            );
          }
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 12.w),
                SizedBox(width: 4.w),
                const Text('All favorites and wishlist cleared successfully'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6.w)),
            margin: EdgeInsets.all(8.w),
          ),
        );
      } else {
        throw Exception('Failed to clear favorites');
      }
    } catch (e) {
      if (kDebugMode) {}

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline_rounded,
                  color: Colors.white, size: 12.w),
              SizedBox(width: 4.w),
              const Text('Failed to clear favorites. Please try again.'),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.w)),
          margin: EdgeInsets.all(8.w),
        ),
      );
    }
  }
}

/* ---------------- Wishlist Page 氓驴茠忙鈥灺棵ヂ嶁€⒚┞÷得┞澛?- 忙鈥撀懊ヂ⑴?---------------- */

class WishlistPage extends StatefulWidget {
  const WishlistPage({Key? key}) : super(key: key);

  @override
  State<WishlistPage> createState() => _WishlistPageState();
}

class _WishlistPageState extends State<WishlistPage> {
  List<Map<String, dynamic>> _wishlistItems = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadWishlist();
  }

  /// 氓艩 猫陆陆氓驴茠忙鈥灺棵ヂ嶁€⒚ニ嗏€斆÷?
  Future<void> _loadWishlist() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Please login to view your wishlist';
      });
      return;
    }

    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      if (kDebugMode) {}

      // 盲陆驴莽鈥澛?DualFavoritesService 猫沤路氓聫鈥撁ヂ科捗︹€灺棵ヂ嶁€⒚ニ嗏€斆÷妓喢ぢ慌?wishlists 猫隆篓茂录鈥?
      final items = await DualFavoritesService.getUserWishlist(
        userId: user.id,
        limit: 100,
      );

      if (mounted) {
        setState(() {
          _wishlistItems = items;
          _isLoading = false;
        });

        if (kDebugMode) {}
      }
    } catch (e) {
      if (kDebugMode) {}

      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load wishlist. Please try again.';
        });
      }
    }
  }

  /// 氓藛路忙鈥撀懊ヂ科捗︹€灺棵ヂ嶁€⒚ニ嗏€斆÷?
  Future<void> _refreshWishlist() async {
    setState(() => _isRefreshing = true);
    await _loadWishlist();
    setState(() => _isRefreshing = false);
  }

  /// 盲禄沤氓驴茠忙鈥灺棵ヂ嶁€⒚幻┾劉陇氓鈥⑩€犆モ€溌?
  Future<void> _removeFromWishlist(String listingId, int index) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      // 盲陆驴莽鈥澛?DualFavoritesService 氓聬艗忙颅楼莽搂禄茅鈩⒙?
      final success = await DualFavoritesService.removeFromFavorites(
        userId: user.id,
        listingId: listingId,
      );

      if (success && mounted) {
        setState(() {
          _wishlistItems.removeAt(index);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 16.w),
                SizedBox(width: 6.w),
                const Text('Removed from wishlist and favorites'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.w)),
            margin: EdgeInsets.all(12.w),
          ),
        );
      } else {
        throw Exception('Failed to remove from wishlist');
      }
    } catch (e) {
      if (kDebugMode) {}

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline_rounded,
                  color: Colors.white, size: 16.w),
              SizedBox(width: 6.w),
              const Text('Failed to remove item. Please try again.'),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.w)),
          margin: EdgeInsets.all(12.w),
        ),
      );
    }
  }

  /// 猫沤路氓聫鈥撁モ€⑩€犆モ€溌伱モ€郝久р€扳€?
  String _getListingImage(Map<String, dynamic> listing) {
    final images = listing['images'] ?? listing['image_urls'];
    if (images is List && images.isNotEmpty) {
      return images.first.toString();
    }
    return 'assets/images/placeholder.jpg';
  }

  /// 忙 录氓录聫氓艗鈥撁ぢ宦访?录
  String _formatPrice(dynamic price) {
    if (price == null) return 'Price not available';

    final priceStr = price.toString();
    if (priceStr.startsWith('\$')) return priceStr;

    final numPrice = double.tryParse(priceStr);
    if (numPrice != null) {
      return '\$${numPrice.toStringAsFixed(0)}';
    }

    return priceStr;
  }

  /// 忙啪鈥灻ヂ宦好ヂ科捗︹€灺棵ヂ嶁€⒚ヂ嵚∶р€扳€?
  Widget _buildWishlistCard(Map<String, dynamic> item, int index) {
    final listing = item['listing'] ?? {};
    final listingId =
        item['listing_id']?.toString() ?? listing['id']?.toString() ?? '';
    final title = listing['title']?.toString() ?? 'Unknown Item';
    final price = _formatPrice(listing['price']);
    final city = listing['city']?.toString() ?? '';
    final imageUrl = _getListingImage(listing);
    final createdAt = item['created_at']?.toString() ?? '';

    // 忙 录氓录聫氓艗鈥撁β仿幻ヅ?忙鈥斅睹┾€斅?
    final timeAdded = DualFavoritesService.formatSavedTime(createdAt);

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.w)),
      color: Colors.white,
      child: InkWell(
        onTap: () {
          if (listingId.isNotEmpty) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ProductDetailPage(
                  productId: listingId,
                  productData: listing,
                ),
              ),
            ).then((_) {
              // 盲禄沤氓鈥⑩€犆モ€溌伱γζ掆€γ┞÷得库€澝モ€号久ヂ恻矫ニ喡访︹€撀懊ニ嗏€斆÷?
              _loadWishlist();
            });
          }
        },
        borderRadius: BorderRadius.circular(12.w),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12.w),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 6.w,
                offset: Offset(0, 1.h),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(12.w),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 氓鈥⑩€犆モ€溌伱モ€郝久р€扳€?
                Hero(
                  tag: 'wishlist_image_$listingId',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.w),
                    child: Container(
                      width: 65.w,
                      height: 65.w,
                      decoration: BoxDecoration(
                        color: Colors.pink[50],
                        borderRadius: BorderRadius.circular(8.w),
                      ),
                      child: imageUrl.startsWith('http')
                          ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        loadingBuilder:
                            (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(
                            child: SizedBox(
                              width: 15.w,
                              height: 15.w,
                              child: CircularProgressIndicator(
                                value:
                                loadingProgress.expectedTotalBytes !=
                                    null
                                    ? loadingProgress
                                    .cumulativeBytesLoaded /
                                    loadingProgress
                                        .expectedTotalBytes!
                                    : null,
                                strokeWidth: 1.5.w,
                                valueColor:
                                const AlwaysStoppedAnimation<Color>(
                                    Colors.pink),
                              ),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.pink[50],
                              borderRadius: BorderRadius.circular(8.w),
                            ),
                            child: Icon(
                              Icons.image_not_supported_rounded,
                              color: Colors.pink[300],
                              size: 24.w,
                            ),
                          );
                        },
                      )
                          : Container(
                        decoration: BoxDecoration(
                          color: Colors.pink[50],
                          borderRadius: BorderRadius.circular(8.w),
                        ),
                        child: Icon(
                          Icons.image_not_supported_rounded,
                          color: Colors.pink[300],
                          size: 24.w,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12.w),

                // 氓鈥⑩€犆モ€溌伱ぢ柯∶β伮?
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 4.h),
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 6.w, vertical: 2.h),
                        decoration: BoxDecoration(
                          color: Colors.pink.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6.w),
                        ),
                        child: Text(
                          price,
                          style: TextStyle(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.bold,
                            color: Colors.pink[600],
                          ),
                        ),
                      ),
                      SizedBox(height: 6.h),
                      if (city.isNotEmpty)
                        Row(
                          children: [
                            Icon(
                              Icons.location_on_rounded,
                              size: 11.w,
                              color: Colors.grey[500],
                            ),
                            SizedBox(width: 3.w),
                            Expanded(
                              child: Text(
                                city,
                                style: TextStyle(
                                  fontSize: 11.sp,
                                  color: Colors.grey[600],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      SizedBox(height: 3.h),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            size: 10.w,
                            color: Colors.grey[400],
                          ),
                          SizedBox(width: 3.w),
                          Text(
                            'Added $timeAdded',
                            style: TextStyle(
                              fontSize: 9.sp,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // 莽搂禄茅鈩⒙っε掆€懊┾€櫬?
                Container(
                  margin: EdgeInsets.only(left: 6.w),
                  decoration: BoxDecoration(
                    color: Colors.pink.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8.w),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _showRemoveDialog(listingId, title, index),
                      borderRadius: BorderRadius.circular(8.w),
                      child: Padding(
                        padding: EdgeInsets.all(8.w),
                        child: Icon(
                          Icons.favorite_rounded,
                          color: Colors.pink[600],
                          size: 18.w,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 忙藴戮莽陇潞莽搂禄茅鈩⒙っ÷っヂ姑澝β♀€?
  void _showRemoveDialog(String listingId, String title, int index) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.w)),
          title: Row(
            children: [
              Container(
                padding: EdgeInsets.all(6.w),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6.w),
                ),
                child: Icon(Icons.delete_outline_rounded,
                    color: Colors.red, size: 16.w),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  'Remove from Wishlist',
                  style:
                  TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to remove "$title" from your wishlist and favorites?',
            style: TextStyle(fontSize: 13.sp, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel',
                  style: TextStyle(fontSize: 13.sp, color: Colors.grey[600])),
            ),
            Container(
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(6.w),
              ),
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _removeFromWishlist(listingId, index);
                },
                child: Text(
                  'Remove',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 忙啪鈥灻ヂ宦好┞好犅睹︹偓聛
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100.w,
              height: 100.w,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.pink.withOpacity(0.1),
                    Colors.pink.withOpacity(0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(50.w),
                border: Border.all(
                  color: Colors.pink.withOpacity(0.2),
                  width: 1.5.w,
                ),
              ),
              child: Icon(
                Icons.favorite_outline_rounded,
                size: 50.w,
                color: Colors.pink,
              ),
            ),
            SizedBox(height: 24.h),
            Text(
              'No Wishlist Items Yet',
              style: TextStyle(
                fontSize: 20.sp,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
                letterSpacing: -0.3,
              ),
            ),
            SizedBox(height: 8.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: Text(
                'Start adding items you like to your wishlist by tapping the bookmark icon on any listing.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.sp,
                  color: Colors.grey[600],
                  height: 1.4,
                ),
              ),
            ),
            SizedBox(height: 30.h),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.pink, Colors.pink[400]!],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(12.w),
                boxShadow: [
                  BoxShadow(
                    color: Colors.pink.withOpacity(0.3),
                    blurRadius: 10.w,
                    offset: Offset(0, 4.h),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding:
                  EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.w),
                  ),
                ),
                icon: Icon(Icons.explore_rounded,
                    size: 16.w, color: Colors.white),
                label: Text(
                  'Browse Items',
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 忙啪鈥灻ヂ宦好┾€濃劉猫炉炉莽艩露忙鈧?
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90.w,
              height: 90.w,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(45.w),
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 45.w,
                color: Colors.red[400],
              ),
            ),
            SizedBox(height: 20.h),
            Text(
              'Something went wrong',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              _errorMessage ?? 'Failed to load your wishlist.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.sp,
                color: Colors.grey[600],
                height: 1.4,
              ),
            ),
            SizedBox(height: 24.h),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.pink, Colors.pink[400]!],
                ),
                borderRadius: BorderRadius.circular(10.w),
              ),
              child: ElevatedButton.icon(
                onPressed: _loadWishlist,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding:
                  EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.w),
                  ),
                ),
                icon: Icon(Icons.refresh_rounded, size: 16.w),
                label: Text(
                  'Try Again',
                  style:
                  TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.pink,
        title: Text(
          'My Wishlist (${_wishlistItems.length})',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
        elevation: 0,
        actions: [
          if (_wishlistItems.isNotEmpty && !_isLoading)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded,
                  color: Colors.white, size: 20.w),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10.w)),
              onSelected: (value) {
                if (value == 'clear_all') {
                  _showClearAllDialog();
                }
              },
              itemBuilder: (BuildContext context) => [
                PopupMenuItem(
                  value: 'clear_all',
                  child: Row(
                    children: [
                      Icon(Icons.clear_all_rounded,
                          color: Colors.red, size: 16.w),
                      SizedBox(width: 10.w),
                      Text('Clear All', style: TextStyle(fontSize: 13.sp)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: _isLoading
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 30.w,
              height: 30.w,
              child: CircularProgressIndicator(
                valueColor:
                const AlwaysStoppedAnimation<Color>(Colors.pink),
                strokeWidth: 2.5.w,
              ),
            ),
            SizedBox(height: 12.h),
            Text(
              'Loading wishlist...',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 13.sp,
              ),
            ),
          ],
        ),
      )
          : _errorMessage != null
          ? _buildErrorState()
          : _wishlistItems.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
        onRefresh: _refreshWishlist,
        color: Colors.pink,
        backgroundColor: Colors.white,
        strokeWidth: 2.w,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(vertical: 8.h),
          itemCount: _wishlistItems.length,
          itemBuilder: (context, index) {
            return _buildWishlistCard(
                _wishlistItems[index], index);
          },
        ),
      ),
    );
  }

  /// 忙藴戮莽陇潞忙赂鈥γ┞好︹€扳偓忙舱鈥懊÷っヂ姑澝β♀€?
  void _showClearAllDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.w)),
          title: Row(
            children: [
              Container(
                padding: EdgeInsets.all(6.w),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6.w),
                ),
                child:
                Icon(Icons.warning_outlined, color: Colors.red, size: 16.w),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  'Clear All Wishlist',
                  style:
                  TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to remove all items from your wishlist and favorites? This action cannot be undone.',
            style: TextStyle(fontSize: 13.sp, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel',
                  style: TextStyle(fontSize: 13.sp, color: Colors.grey[600])),
            ),
            Container(
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(6.w),
              ),
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _clearAllWishlist();
                },
                child: Text(
                  'Clear All',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 忙赂鈥γ┞好︹€扳偓忙舱鈥懊ヂ科捗︹€灺棵ヂ嶁€?
  Future<void> _clearAllWishlist() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      // 盲陆驴莽鈥澛?DualFavoritesService 氓聬艗忙颅楼忙赂鈥γ┞?
      final success =
      await DualFavoritesService.clearUserFavorites(userId: user.id);

      if (success && mounted) {
        setState(() {
          _wishlistItems.clear();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 16.w),
                SizedBox(width: 6.w),
                const Text('All wishlist and favorites cleared successfully'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.w)),
            margin: EdgeInsets.all(12.w),
          ),
        );
      } else {
        throw Exception('Failed to clear wishlist');
      }
    } catch (e) {
      if (kDebugMode) {}

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline_rounded,
                  color: Colors.white, size: 16.w),
              SizedBox(width: 6.w),
              const Text('Failed to clear wishlist. Please try again.'),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.w)),
          margin: EdgeInsets.all(12.w),
        ),
      );
    }
  }
}
// 莽卢卢氓鈥衡€好┢捖ニ嗏€犆寂ellPage 氓鈥÷好モ€澛┞÷?(忙聛垄氓陇聧氓庐艗忙鈥⒙疵ヅ犈该ㄆ捖? 氓鈥櫯?NotificationPage 茅鈧∶嘎ッ┞÷?(盲陆驴莽鈥澛ぢ号捗ぢ嘎р€八喢ε撀♀€濻ervice茅鈥衡€犆λ喡?

/* ---------------- Sell Page 氓鈥÷好モ€澛┞÷?(莽戮沤氓艗鈥撁р€八喢ε撀? ---------------- */

class SellPage extends StatefulWidget {
  final bool isGuest;
  const SellPage({Key? key, this.isGuest = false}) : super(key: key);

  @override
  State<SellPage> createState() => _SellPageState();
}

class _SellPageState extends State<SellPage> with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (widget.isGuest) {
      return _buildGuestView(l10n);
    }

    final raw = ListingStore.i.getAll();
    final List<Map<String, dynamic>> myListings = (raw is List)
        ? List<Map<String, dynamic>>.from(raw)
        : const <Map<String, dynamic>>[];

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(l10n, myListings.length),
          if (myListings.isEmpty)
            _buildEmptyState(l10n)
          else
            _buildListingsContent(myListings, l10n),
        ],
      ),
    );
  }

  Widget _buildGuestView(AppLocalizations l10n) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2196F3),
        title: Text(
          l10n.sellItem,
          style: TextStyle(
            color: Colors.white,
            fontSize: 18.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
        elevation: 0,
        centerTitle: true,
      ),
      body: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24.w),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 120.w,
                    height: 120.w,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.grey.shade200,
                          Colors.grey.shade100,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(60.r),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 20.r,
                          offset: Offset(0, 8.h),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.lock_outline_rounded,
                      size: 60.r,
                      color: Colors.grey.shade500,
                    ),
                  ),
                  SizedBox(height: 32.h),
                  Text(
                    l10n.loginRequired,
                    style: TextStyle(
                      fontSize: 24.sp,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                      letterSpacing: -0.5,
                    ),
                  ),
                  SizedBox(height: 12.h),
                  Text(
                    l10n.loginToPost,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 16.sp,
                      height: 1.5,
                    ),
                  ),
                  SizedBox(height: 40.h),
                  Container(
                    width: double.infinity,
                    height: 56.h,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2196F3), Color(0xFF1E88E5)],
                      ),
                      borderRadius: BorderRadius.circular(16.r),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2196F3).withOpacity(0.4),
                          blurRadius: 16.r,
                          offset: Offset(0, 8.h),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: () {
                        SafeNavigator.pushNamedAndRemoveUntil(
                            '/welcome', (route) => false);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16.r),
                        ),
                      ),
                      icon: Icon(Icons.login_rounded,
                          size: 20.r, color: Colors.white),
                      label: Text(
                        l10n.loginNow,
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSliverAppBar(AppLocalizations l10n, int listingsCount) {
    return SliverAppBar(
      expandedHeight: 120.h,
      floating: false,
      pinned: true,
      backgroundColor: const Color(0xFF2196F3),
      flexibleSpace: FlexibleSpaceBar(
        title: Text(
          l10n.sellItem,
          style: TextStyle(
            color: Colors.white,
            fontSize: 18.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF2196F3),
                Color(0xFF1E88E5),
                Color(0xFF1976D2),
              ],
            ),
          ),
        ),
      ),
      actions: [
        Container(
          margin: EdgeInsets.only(right: 16.w, top: 8.h, bottom: 8.h),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12.r),
          ),
          child: IconButton(
            onPressed: () => SafeNavigator.push(
              MaterialPageRoute(builder: (_) => const SellFormPage()),
            ),
            icon: Icon(Icons.add_rounded, color: Colors.white, size: 24.r),
            tooltip: 'Add New Listing',
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n) {
    return SliverFillRemaining(
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24.w),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 140.w,
                    height: 140.w,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF2196F3).withOpacity(0.2),
                          const Color(0xFF1E88E5).withOpacity(0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(70.r),
                      border: Border.all(
                        color: const Color(0xFF2196F3).withOpacity(0.3),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2196F3).withOpacity(0.2),
                          blurRadius: 24.r,
                          offset: Offset(0, 12.h),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.add_a_photo_rounded,
                      size: 70.r,
                      color: const Color(0xFF2196F3),
                    ),
                  ),
                  SizedBox(height: 32.h),
                  Text(
                    l10n.sellYourItems,
                    style: TextStyle(
                      fontSize: 28.sp,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                      letterSpacing: -0.8,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 16.h),
                  Text(
                    l10n.takePhotoAndSell,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 16.sp,
                      height: 1.6,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 24.h),
                  Container(
                    padding:
                    EdgeInsets.symmetric(horizontal: 24.w, vertical: 16.h),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2196F3).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16.r),
                      border: Border.all(
                        color: const Color(0xFF2196F3).withOpacity(0.2),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(Icons.camera_alt_rounded,
                                color: const Color(0xFF2196F3), size: 20.r),
                            SizedBox(width: 8.w),
                            Text('Take quality photos',
                                style: TextStyle(
                                    fontSize: 14.sp,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                        SizedBox(height: 8.h),
                        Row(
                          children: [
                            Icon(Icons.edit_rounded,
                                color: const Color(0xFF2196F3), size: 20.r),
                            SizedBox(width: 8.w),
                            Text('Write detailed description',
                                style: TextStyle(
                                    fontSize: 14.sp,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                        SizedBox(height: 8.h),
                        Row(
                          children: [
                            Icon(Icons.monetization_on_rounded,
                                color: const Color(0xFF2196F3), size: 20.r),
                            SizedBox(width: 8.w),
                            Text('Set competitive price',
                                style: TextStyle(
                                    fontSize: 14.sp,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 40.h),
                  Container(
                    width: double.infinity,
                    height: 56.h,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2196F3), Color(0xFF1E88E5)],
                      ),
                      borderRadius: BorderRadius.circular(16.r),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2196F3).withOpacity(0.4),
                          blurRadius: 16.r,
                          offset: Offset(0, 8.h),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16.r),
                        ),
                      ),
                      onPressed: () => SafeNavigator.push(
                        MaterialPageRoute(builder: (_) => const SellFormPage()),
                      ),
                      icon: Icon(Icons.add_rounded,
                          color: Colors.white, size: 24.r),
                      label: Text(
                        l10n.postNewAd,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildListingsContent(
      List<Map<String, dynamic>> myListings, AppLocalizations l10n) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
            (context, index) {
          if (index == 0) {
            return _buildStatsHeader(myListings, l10n);
          }
          final listingIndex = index - 1;
          return TweenAnimationBuilder<double>(
            duration: Duration(milliseconds: 300 + (listingIndex * 100)),
            tween: Tween(begin: 0.0, end: 1.0),
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, 20 * (1 - value)),
                child: Opacity(
                  opacity: value,
                  child: _buildListingCard(myListings[listingIndex], l10n),
                ),
              );
            },
          );
        },
        childCount: myListings.length + 1,
      ),
    );
  }

  Widget _buildStatsHeader(
      List<Map<String, dynamic>> myListings, AppLocalizations l10n) {
    final totalViews =
    myListings.fold<int>(0, (sum, item) => sum + 234); // Mock data
    final totalLikes =
    myListings.fold<int>(0, (sum, item) => sum + 12); // Mock data

    return Container(
      margin: EdgeInsets.all(16.w),
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            const Color(0xFFF8F9FA),
          ],
        ),
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16.r,
            offset: Offset(0, 4.h),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${l10n.myListings}',
                    style: TextStyle(
                      fontSize: 20.sp,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    '${myListings.length} active items',
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2196F3), Color(0xFF1E88E5)],
                  ),
                  borderRadius: BorderRadius.circular(12.r),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2196F3).withOpacity(0.3),
                      blurRadius: 8.r,
                      offset: Offset(0, 4.h),
                    ),
                  ],
                ),
                child: GestureDetector(
                  onTap: () => SafeNavigator.push(
                    MaterialPageRoute(builder: (_) => const SellFormPage()),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, size: 18.r, color: Colors.white),
                      SizedBox(width: 6.w),
                      Text(
                        l10n.newAd,
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 20.h),
          Row(
            children: [
              Expanded(
                  child: _buildStatCard(
                      Icons.visibility_rounded,
                      totalViews.toString(),
                      'Total Views',
                      const Color(0xFF2196F3))),
              SizedBox(width: 12.w),
              Expanded(
                  child: _buildStatCard(
                      Icons.favorite_rounded,
                      totalLikes.toString(),
                      'Total Likes',
                      Colors.red.shade400)),
              SizedBox(width: 12.w),
              Expanded(
                  child: _buildStatCard(
                      Icons.trending_up_rounded,
                      '${(totalViews * 0.15).toInt()}',
                      'Engagement',
                      Colors.green.shade400)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      IconData icon, String value, String label, Color color) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24.r),
          SizedBox(height: 8.h),
          Text(
            value,
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.sp,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildListingCard(Map<String, dynamic> item, AppLocalizations l10n) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12.r,
            offset: Offset(0, 4.h),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20.r),
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProductDetailPage(
                productId: item['id'],
                productData: item,
              ),
            ),
          ),
          borderRadius: BorderRadius.circular(20.r),
          child: Padding(
            padding: EdgeInsets.all(16.w),
            child: Row(
              children: [
                // 氓鈥⑩€犆モ€溌伱モ€郝久р€扳€?
                Hero(
                  tag: 'listing_${item['id']}',
                  child: Container(
                    width: 80.w,
                    height: 80.w,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16.r),
                      gradient: LinearGradient(
                        colors: [Colors.grey.shade100, Colors.grey.shade50],
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16.r),
                      child: item['images'] != null && item['images'].isNotEmpty
                          ? Image.asset(
                        item['images'][0],
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            Icon(
                              Icons.image_rounded,
                              color: Colors.grey.shade400,
                              size: 32.r,
                            ),
                      )
                          : Icon(
                        Icons.image_rounded,
                        color: Colors.grey.shade400,
                        size: 32.r,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 16.w),

                // 氓鈥⑩€犆モ€溌伱ぢ柯∶β伮?
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['title'] ?? l10n.noTitle,
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 8.h),
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 12.w, vertical: 6.h),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF2196F3).withOpacity(0.15),
                              const Color(0xFF2196F3).withOpacity(0.08),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(
                            color: const Color(0xFF2196F3).withOpacity(0.2),
                          ),
                        ),
                        child: Text(
                          item['price'] ?? l10n.noPrice,
                          style: TextStyle(
                            color: const Color(0xFF2196F3),
                            fontWeight: FontWeight.bold,
                            fontSize: 16.sp,
                          ),
                        ),
                      ),
                      SizedBox(height: 12.h),
                      Row(
                        children: [
                          _buildEnhancedStatItem(Icons.visibility_rounded,
                              '234', Colors.blue.shade400),
                          SizedBox(width: 16.w),
                          _buildEnhancedStatItem(Icons.favorite_rounded, '12',
                              Colors.red.shade400),
                          SizedBox(width: 16.w),
                          _buildEnhancedStatItem(Icons.chat_bubble_rounded, '3',
                              Colors.green.shade400),
                        ],
                      ),
                    ],
                  ),
                ),

                // 猫聫艙氓聧鈥⒚ε掆€懊┾€櫬?
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert_rounded,
                      size: 20.r,
                      color: Colors.grey.shade600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16.r),
                    ),
                    onSelected: (value) => _handleMenuAction(value, item, l10n),
                    itemBuilder: (BuildContext context) => [
                      _buildMenuItem('view', Icons.visibility_rounded, 'View',
                          Colors.blue.shade600),
                      _buildMenuItem('edit', Icons.edit_rounded, 'Edit',
                          Colors.orange.shade600),
                      _buildMenuItem('delete', Icons.delete_outline_rounded,
                          'Delete', Colors.red.shade600),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildMenuItem(
      String value, IconData icon, String text, Color color) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(6.r),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Icon(icon, size: 16.r, color: color),
          ),
          SizedBox(width: 12.w),
          Text(text,
              style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildEnhancedStatItem(IconData icon, String count, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.all(4.r),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6.r),
          ),
          child: Icon(icon, size: 12.r, color: color),
        ),
        SizedBox(width: 4.w),
        Text(
          count,
          style: TextStyle(
            color: color,
            fontSize: 12.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  void _handleMenuAction(
      String action, Map<String, dynamic> item, AppLocalizations l10n) async {
    switch (action) {
      case 'view':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProductDetailPage(
              productId: item['id'].toString(),
              productData: item,
            ),
          ),
        );
        break;
      case 'edit':
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const SellFormPage(),
          ),
        );
        break;
      case 'delete':
        _showDeleteDialog(item, l10n);
        break;
    }
  }

  void _showDeleteDialog(Map<String, dynamic> item, AppLocalizations l10n) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8.r),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(Icons.delete_outline_rounded,
                  color: Colors.red, size: 24.r),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                l10n.delete,
                style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${item['title'] ?? 'this listing'}"? This action cannot be undone.',
          style: TextStyle(fontSize: 14.sp, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: TextStyle(fontSize: 14.sp, color: Colors.grey.shade600)),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: [Colors.red.shade400, Colors.red.shade600]),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: TextButton(
              onPressed: () {
                Navigator.pop(context);
                _deleteListing(item, l10n);
              },
              child: Text(
                'Delete',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _deleteListing(Map<String, dynamic> item, AppLocalizations l10n) async {
    try {
      final urls =
          (item['images'] as List?)?.cast<String>() ?? const <String>[];
      final paths = urls
          .map(ListingService.publicUrlToObjectPath)
          .whereType<String>()
          .toList();

      await ListingService.deleteListingAndStorage(
        id: (item['id'] as num).toInt(),
        imageObjectPaths: paths,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 18.r),
                SizedBox(width: 8.w),
                Text(l10n.listingDeleted),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.r)),
            margin: EdgeInsets.all(16.w),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline_rounded,
                    color: Colors.white, size: 18.r),
                SizedBox(width: 8.w),
                Expanded(child: Text('Delete failed: $e')),
              ],
            ),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.r)),
            margin: EdgeInsets.all(16.w),
          ),
        );
      }
    }
  }
}

/* ---------------- Notification Page 茅鈧∶嘎ッ┞÷?(莽麓搂氓鈥♀€樏九矫ヅ掆€撁р€八喢ε撀? ---------------- */

class NotificationPage extends StatefulWidget {
  final VoidCallback? onClearBadge;
  final bool isGuest;
  final Function(int)? onNotificationCountChanged;

  const NotificationPage({
    Key? key,
    this.onClearBadge,
    this.isGuest = false,
    this.onNotificationCountChanged,
  }) : super(key: key);

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;

  // 自定义头部组件，用于统一蓝色、大标题和间距
  Widget _buildCustomHeader(String title) {
    final l10n = AppLocalizations.of(context)!;
    final unreadCount =
        _notifications.where((n) => n['is_read'] != true).length;
    final displayTitle = '${title}${unreadCount > 0 ? ' ($unreadCount)' : ''}';

    return Container(
      color: _PRIMARY_BLUE, // 统一的深蓝
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 16.h), // 标题距安全区顶部约 16dp
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      displayTitle,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24.sp, // 统一字体大小
                        fontWeight: FontWeight.w600, // SemiBold
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_notifications.isNotEmpty)
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert_rounded,
                          color: Colors.white, size: 18.r),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.r)),
                      onSelected: (value) {
                        if (value == 'mark_all_read') {
                          _markAllAsRead();
                        } else if (value == 'clear_all') {
                          _clearAll();
                        }
                      },
                      itemBuilder: (BuildContext context) => [
                        PopupMenuItem(
                          value: 'mark_all_read',
                          child: Row(
                            children: [
                              Icon(Icons.done_all_rounded,
                                  size: 14.r, color: Colors.grey.shade600),
                              SizedBox(width: 8.w),
                              Text(l10n.markAllAsRead,
                                  style: TextStyle(fontSize: 12.sp)),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'clear_all',
                          child: Row(
                            children: [
                              Icon(Icons.clear_all_rounded,
                                  color: Colors.red, size: 14.r),
                              SizedBox(width: 8.w),
                              Text(l10n.clearAll,
                                  style: TextStyle(
                                      fontSize: 12.sp, color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            SizedBox(height: 16.h),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    if (!widget.isGuest) {
      _loadNotifications();
      _subscribeToNotifications();
    } else {
      setState(() => _isLoading = false);
    }

    if (widget.onClearBadge != null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => widget.onClearBadge!());
    }
  }

  @override
  void dispose() {
    _unsubscribeFromNotifications();
    super.dispose();
  }

  Future<void> _loadNotifications() async {
    try {
      setState(() => _isLoading = true);

      final notifications = await NotificationService.getUserNotifications(
        limit: 100,
        includeRead: true,
      );

      if (mounted) {
        setState(() {
          _notifications = notifications;
          _isLoading = false;
        });
        _updateUnreadCount();
      }
    } catch (e) {
      if (kDebugMode) {}
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // 芒艙鈥?盲驴庐忙颅拢茂录拧盲陆驴莽鈥澛βＣ÷♀€灻ヂ忊€毭︹€⒙懊捌捗р€澛?
  Future<void> _subscribeToNotifications() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    await NotificationService.subscribeUser(
      user.id, // 盲陆聧莽陆庐氓聫鈥毭︹€⒙?
      onEvent: (Map<String, dynamic> notification) {
        // 氓鈥樎矫ヂ惵嵜ヂ忊€毭︹€⒙?
        if (!mounted) return;
        setState(() {
          _notifications.insert(0, notification);
        });
        _updateUnreadCount();
      },
    );
  }

  Future<void> _unsubscribeFromNotifications() async {
    await NotificationService.unsubscribe();
  }

  void _updateUnreadCount() {
    final unreadCount =
        _notifications.where((n) => n['is_read'] != true).length;
    if (widget.onNotificationCountChanged != null) {
      widget.onNotificationCountChanged!(unreadCount);
    }
  }

  Future<void> _markAsRead(int index) async {
    final notification = _notifications[index];
    if (notification['is_read'] == true) return;

    try {
      final success = await NotificationService.markNotificationAsRead(
        notification['id'].toString(),
      );

      if (success && mounted) {
        setState(() {
          _notifications[index]['is_read'] = true;
          _notifications[index]['read_at'] = DateTime.now().toIso8601String();
        });
        _updateUnreadCount();
      }
    } catch (e) {
      if (kDebugMode) {}
    }
  }

  Future<void> _deleteNotification(int index) async {
    final l10n = AppLocalizations.of(context)!;
    final notification = _notifications[index];

    try {
      final success = await NotificationService.deleteNotification(
        notification['id'].toString(),
      );

      if (success && mounted) {
        setState(() => _notifications.removeAt(index));
        _updateUnreadCount();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 14.sp),
                SizedBox(width: 6.w),
                Text(l10n.notificationDeleted,
                    style: TextStyle(fontSize: 12.sp)),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6.r)),
            margin: EdgeInsets.all(8.w),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) {}
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline_rounded,
                  color: Colors.white, size: 14.sp),
              SizedBox(width: 6.w),
              Text('Failed to delete notification',
                  style: TextStyle(fontSize: 12.sp)),
            ],
          ),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.r)),
          margin: EdgeInsets.all(8.w),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      final success = await NotificationService.markAllNotificationsAsRead();

      if (success && mounted) {
        setState(() {
          for (var notification in _notifications) {
            notification['is_read'] = true;
            notification['read_at'] = DateTime.now().toIso8601String();
          }
        });
        _updateUnreadCount();
      }
    } catch (e) {
      if (kDebugMode) {}
    }
  }

  Future<void> _clearAll() async {
    try {
      final success = await NotificationService.clearAllNotifications();

      if (success && mounted) {
        setState(() => _notifications.clear());
        _updateUnreadCount();
      }
    } catch (e) {
      if (kDebugMode) {}
    }
  }

  Widget _getNotificationIcon(String type) {
    final color = Color(NotificationService.getNotificationColor(type));
    IconData iconData;

    switch (type) {
      case 'offer':
        iconData = Icons.local_offer_rounded;
        break;
      case 'wishlist':
        iconData = Icons.bookmark_rounded;
        break;
      case 'purchase':
        iconData = Icons.shopping_cart_rounded;
        break;
      case 'message':
        iconData = Icons.message_rounded;
        break;
      case 'price_drop':
        iconData = Icons.trending_down_rounded;
        break;
      case 'system':
      default:
        iconData = Icons.notifications_rounded;
    }

    return Container(
      width: 32.w,
      height: 32.w,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: color.withOpacity(0.3), width: 0.5),
      ),
      child: Icon(iconData, color: color, size: 16.r),
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: TextStyle(fontSize: 12.sp)),
        backgroundColor:
        isError ? Colors.red.shade600 : const Color(0xFF4CAF50),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.r)),
        margin: EdgeInsets.all(8.w),
        duration: Duration(seconds: isError ? 3 : 2),
      ),
    );
  }

  void _handleNotificationTap(Map<String, dynamic> notification) {
    final index = _notifications.indexOf(notification);
    if (index >= 0) {
      _markAsRead(index);
    }

    // 忙路禄氓艩 猫掳茠猫炉鈥⒚︹€斅ッヂ库€?

    final type = notification['type']?.toString() ?? '';

    // 氓掳聺猫炉鈥⒚ぢ慌矫ヂづ∶ぢ嘎ぢ铰嵜铰ㄅ铰访ヂ忊€揑D盲驴隆忙聛炉
    String? listingId = notification['listing_id']?.toString();
    String? offerId = notification['offer_id']?.toString();

    // 氓娄鈥毭ε九撁р€郝疵ε铰ッヂ€斆β得ぢ嘎好┞好寂捗ヂ奥澝€⒚ぢ慌絧ayload盲赂颅猫沤路氓聫鈥?
    final payload = notification['payload'] as Map<String, dynamic>? ?? {};
    if ((listingId == null || listingId.isEmpty) && payload.isNotEmpty) {
      listingId = payload['listing_id']?.toString();
    }
    if ((offerId == null || offerId.isEmpty) && payload.isNotEmpty) {
      offerId = payload['offer_id']?.toString();
    }

    // 盲鹿鸥氓掳聺猫炉鈥⒚ぢ慌絤etadata盲赂颅猫沤路氓聫鈥?
    final metadata = notification['metadata'] as Map<String, dynamic>? ?? {};
    if ((listingId == null || listingId.isEmpty) && metadata.isNotEmpty) {
      listingId = metadata['listing_id']?.toString();
    }
    if ((offerId == null || offerId.isEmpty) && metadata.isNotEmpty) {
      offerId = metadata['offer_id']?.toString();
    }

    final notificationId = notification['id']?.toString();

    // 忙拢鈧ε嘎ッ︹€⒙懊β嵚ヂ捗︹€⒙疵︹偓搂
    if (type.isEmpty) {
      _showSnack('Notification data is incomplete', isError: true);
      return;
    }

    switch (type) {
      case 'message':
        if (offerId != null && offerId.isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => OfferDetailPage(
                offerId: offerId!,
                offerData: _buildOfferDataFromNotification(notification),
              ),
            ),
          );
        } else {
          _showSnack('Cannot open message: missing offer ID', isError: true);
        }
        break;

      case 'offer':
      case 'system':
        if (offerId != null && offerId.isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => OfferDetailPage(
                offerId: offerId!,
                offerData: _buildOfferDataFromNotification(notification),
              ),
            ),
          );
        } else if (listingId != null && listingId.isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProductDetailPage(productId: listingId!),
            ),
          );
        } else {
          _showSnack('Cannot open notification: missing required IDs',
              isError: true);
        }
        break;

      case 'wishlist':
      case 'price_drop':
      default:
        if (listingId != null && listingId.isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProductDetailPage(productId: listingId!),
            ),
          );
        } else {
          _showSnack('Cannot open notification: missing listing ID',
              isError: true);
        }
        break;
    }
  }

  Map<String, dynamic>? _buildOfferDataFromNotification(
      Map<String, dynamic> notification) {
    final metadata = notification['metadata'] as Map<String, dynamic>? ?? {};
    final offerId = notification['offer_id']?.toString();

    if (offerId == null) return null;

    return {
      'id': offerId,
      'offer_amount': metadata['offer_amount'],
      'listing_id': notification['listing_id'],
      'buyer_name': metadata['buyer_name'] ?? metadata['sender_name'],
      'status': metadata['action'] ?? 'pending',
      'message': metadata['buyer_message'] ?? metadata['response_message'],
      'listings': {
        'id': notification['listing_id'],
        'title': metadata['listing_title'],
        'price': metadata['original_price'],
      },
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (widget.isGuest) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          backgroundColor: _PRIMARY_BLUE, // 统一颜色
          title: Text(
            l10n.notifications,
            style: TextStyle(
              color: Colors.white,
              fontSize: 18.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
          elevation: 0,
          centerTitle: true,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 60.w,
                height: 60.w,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(30.r),
                ),
                child: Icon(
                  Icons.lock_outline_rounded,
                  size: 30.r,
                  color: Colors.grey.shade500,
                ),
              ),
              SizedBox(height: 16.h),
              Text(
                l10n.loginRequired,
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 6.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.w),
                child: Text(
                  l10n.loginToReceiveNotifications,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12.sp,
                    height: 1.4,
                  ),
                ),
              ),
              SizedBox(height: 20.h),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_PRIMARY_BLUE, const Color(0xFF1E88E5)], // 统一颜色
                  ),
                  borderRadius: BorderRadius.circular(10.r),
                  boxShadow: [
                    BoxShadow(
                      color: _PRIMARY_BLUE.withOpacity(0.3), // 统一颜色
                      blurRadius: 8.r,
                      offset: Offset(0, 3.h),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const LoginScreen()),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding:
                    EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                  ),
                  icon: Icon(Icons.login_rounded,
                      size: 14.r, color: Colors.white),
                  label: Text(
                    l10n.loginNow,
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final unreadCount =
        _notifications.where((n) => n['is_read'] != true).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      // 头部使用自定义组件
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(_CUSTOM_HEADER_HEIGHT), // 使用统一高度
        child: _buildCustomHeader(l10n.notifications),
      ),
      body: _isLoading
          ? Center(
        child: Container(
          padding: EdgeInsets.all(24.w),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16.r),
            boxShadow: [
              BoxShadow(
                color: _PRIMARY_BLUE.withOpacity(0.08), // 统一颜色
                blurRadius: 10.r,
                offset: Offset(0, 4.h),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40.w,
                height: 40.w,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _PRIMARY_BLUE.withOpacity(0.2), // 统一颜色
                      _PRIMARY_BLUE.withOpacity(0.1), // 统一颜色
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20.r),
                ),
                child: Center(
                  child: SizedBox(
                    width: 20.w,
                    height: 20.w,
                    child: CircularProgressIndicator(
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          _PRIMARY_BLUE), // 统一颜色
                      strokeWidth: 2.5,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 12.h),
              Text(
                'Loading notifications...',
                style: TextStyle(
                  color: _PRIMARY_BLUE, // 统一颜色
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      )
          : _notifications.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 60.w,
              height: 60.w,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _PRIMARY_BLUE.withOpacity(0.1), // 统一颜色
                    const Color(0xFF1E88E5).withOpacity(0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(30.r),
                border: Border.all(
                  color: _PRIMARY_BLUE.withOpacity(0.2), // 统一颜色
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.notifications_none_rounded,
                size: 30.r,
                color: _PRIMARY_BLUE, // 统一颜色
              ),
            ),
            SizedBox(height: 16.h),
            Text(
              l10n.noNotifications,
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: 6.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: Text(
                l10n.notificationsWillAppearHere,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12.sp,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      )
          : RefreshIndicator(
        onRefresh: _loadNotifications,
        color: _PRIMARY_BLUE, // 统一颜色
        backgroundColor: Colors.white,
        strokeWidth: 2.w,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: _notifications.length,
          itemBuilder: (context, index) {
            final notification = _notifications[index];
            final isRead = notification['is_read'] == true;
            final type = notification['type']?.toString() ?? '';
            final createdAt =
                notification['created_at']?.toString() ?? '';

            return Dismissible(
              key: Key('${notification['id']}'),
              background: Container(
                color: Colors.red.shade600,
                alignment: Alignment.centerRight,
                padding: EdgeInsets.only(right: 12.w),
                child: Icon(
                  Icons.delete_rounded,
                  color: Colors.white,
                  size: 20.r,
                ),
              ),
              direction: DismissDirection.endToStart,
              onDismissed: (direction) => _deleteNotification(index),
              child: Container(
                color: isRead
                    ? Colors.white
                    : _PRIMARY_BLUE.withOpacity(0.03), // 统一颜色
                margin: EdgeInsets.only(bottom: 0.5.h),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _handleNotificationTap(notification),
                    splashColor:
                    _PRIMARY_BLUE.withOpacity(0.1), // 统一颜色
                    highlightColor:
                    _PRIMARY_BLUE.withOpacity(0.05), // 统一颜色
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12.w,
                        vertical: 8.h,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _getNotificationIcon(type),
                          SizedBox(width: 10.w),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${notification['title'] ?? ''}',
                                        style: TextStyle(
                                          fontWeight: isRead
                                              ? FontWeight.w500
                                              : FontWeight.w600,
                                          fontSize: 13.sp,
                                          color: Colors.black87,
                                          height: 1.3,
                                        ),
                                        maxLines: 2,
                                        overflow:
                                        TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (!isRead)
                                      Container(
                                        width: 6.w,
                                        height: 6.w,
                                        margin: EdgeInsets.only(
                                            left: 6.w),
                                        decoration:
                                        const BoxDecoration(
                                          color:
                                          _PRIMARY_BLUE, // 统一颜色
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                  ],
                                ),
                                SizedBox(height: 2.h),
                                Text(
                                  '${notification['message'] ?? ''}',
                                  style: TextStyle(
                                    fontSize: 11.sp,
                                    color: Colors.grey.shade600,
                                    height: 1.4,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                SizedBox(height: 4.h),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.access_time_rounded,
                                      size: 10.r,
                                      color: Colors.grey.shade400,
                                    ),
                                    SizedBox(width: 2.w),
                                    Text(
                                      NotificationService
                                          .formatNotificationTime(
                                          createdAt),
                                      style: TextStyle(
                                        fontSize: 10.sp,
                                        color: Colors.grey.shade400,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}


class NoGlowScrollBehavior extends ScrollBehavior {
  @override
  Widget buildViewportChrome(
      BuildContext context, Widget child, AxisDirection axisDirection) {
    return child;
  }
}

const _kPrivacyUrl = 'https://www.swaply.cc/privacy';
const _kDeleteUrl = 'https://www.swaply.cc/delete-account';
