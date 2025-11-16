import 'dart:async';
import 'dart:developer' as dev; // ✅ 新增的 import
import 'dart:io';
// import 'dart:async'; // ❌ 重复：已删除
import 'package:swaply/services/verification_guard.dart';
import 'package:app_links/app_links.dart'; // ✅ 深链支持（替代 uni_links）
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ✅ 全局状态栏/系统UI控制
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// ====== 应用内的依赖 ======
import 'package:swaply/auth/login_screen.dart';
import 'package:swaply/auth/reset_password_page.dart'; // ✅ 新增：密码找回完成后设置新密码页面
import 'package:swaply/auth/welcome_screen.dart';
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
import 'package:swaply/services/coupon_service.dart';
import 'package:swaply/services/dual_favorites_service.dart';
import 'package:swaply/services/email_verification_service.dart';
import 'package:swaply/services/favorites_update_service.dart';
import 'package:swaply/services/listing_service.dart';
import 'package:swaply/services/notification_service.dart';
import 'package:swaply/services/profile_service.dart';
import 'package:swaply/services/reward_service.dart';
import 'package:swaply/services/welcome_dialog_service.dart'; // ✅ 欢迎券弹窗统一入口
import 'package:swaply/utils/verification_utils.dart' as vutils;
import 'package:swaply/widgets/ios_insets_guard.dart';
import 'package:swaply/widgets/verified_avatar.dart';
import 'debug/recovery_probe.dart';

// ✅ 新增：版本更新提示服务
import 'package:swaply/services/app_update_service.dart';

// ========= 全局 Auth 事件监听（只注册一次） =========
bool _authHookWired = false;
StreamSubscription<AuthState>? _globalAuthSub;
final GlobalKey<NavigatorState> appNavKey = GlobalKey<NavigatorState>();
// ✅ 只导航一次到重置页的保护位
bool _navigatedToReset = false;
// ✅ 深链订阅（全局保存，便于取消）
StreamSubscription? _deeplinkSub;

class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);
  static AppLocalizations? of(BuildContext context) {
    return AppLocalizations(const Locale('en'));
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
  _AppLocalizationsDelegate();
  // ---------- Generic / Auth ----------
  String get appTitle => 'Swaply';
  String get loginRequired => 'Login required';
  String loginRequiredMessage(String feature) =>
      'Please login to use $feature.';
  String get cancel => 'Cancel';
  String get login => 'Login';
  String get logout => 'Logout';
  String get logoutConfirmation => 'Are you sure you want to logout?';
  String get createAccount => 'Create account';
  String get alreadyHaveAccount => 'Already have an account?';
  String get signUpNow => 'Sign up now';
  String get signUpToUnlock => 'Sign up to unlock the features below';
  String get verification => 'Verification';
  String get accountVerification => 'Account verification';
  String get notVerified => 'Not verified';
  String get about => 'About';
  String get settings => 'Settings';
  String get helpSupport => 'Help & Support';
  // ---------- Tabs / Common ----------
  String get home => 'Home';
  String get saved => 'Saved';
  String get sell => 'Sell';
  String get notifications => 'Notifications';
  String get profile => 'Profile';
  String get favorites => 'Favorites';
  String get rating => 'Rating';
  // ---------- Home ----------
  String get whatLookingFor => 'What are you looking for?';
  String get allZimbabwe => 'All Zimbabwe';
  String get searchPlaceholder => 'Search...';
  // Categories
  String get trending => 'Trending';
  String get vehicles => 'Vehicles';
  String get property => 'Property';
  String get beauty => 'Beauty & Personal Care';
  String get jobs => 'Jobs';
  String get babiesKids => 'Babies & Kids';
  String get services => 'Services';
  String get leisure => 'Leisure Activities';
  String get repairConst => 'Repair & Construction';
  String get furniture => 'Home, Furniture & Appliances';
  String get pets => 'Pets';
  String get electronics => 'Electronics';
  String get phones => 'Phones & Tablets';
  String get seekingWork => 'Seeking Work & CVs';
  String get fashion => 'Fashion';
  String get foodDrinks => 'Food, Agriculture & Drinks';
  // ---------- Saved ----------
  String get myFavorites => 'My Favorites';
  String get loginToSaveFavorites =>
      'Login to save your favorite items and searches.';
  String get loginNow => 'Login now';
  String get ads => 'Ads';
  String get searches => 'Searches';
  String get noFavoriteAdsYet => 'No favorite ads yet';
  String get favoritesHelp =>
      'Tap the bookmark icon on a listing to add it to Favorites.';
  String get browseItems => 'Browse items';
  String get removedFromFavorites => 'Removed from favorites';
  String get alertsEnabled => 'Alerts enabled';
  String get searchingFor => 'Searching for';
  String get savedOn => 'saved on';
  String get wishlist => 'Wishlist';
  String get noSavedSearches => 'No saved searches';
  // ---------- Sell ----------
  String get sellItem => 'Sell Item';
  String get loginToPost => 'Login to post your listings.';
  String get sellYourItems => 'Sell your items';
  String get takePhotoAndSell => 'Take a photo and sell in minutes.';
  String get postNewAd => 'Post new ad';
  String get myListings => 'My Listings';
  String get newAd => 'New Ad';
  String get noTitle => 'No title';
  String get noPrice => 'No price';
  String get views => 'views';
  String get totalViews => 'Total views';
  String get likes => 'likes';
  String get edit => 'Edit';
  String get promote => 'Promote';
  String get delete => 'Delete';
  String get editModeComingSoon => 'Edit mode is coming soon';
  String get editFeatureComingSoon => 'Edit feature is coming soon';
  String get listingDeleted => 'Listing deleted';
  String get promoteFeatureComingSoon => 'Promote feature is coming soon';
  String get activeAds => 'Active ads';
  String get navigateToSellTab => 'Navigate to Sell tab';
  String get navigateToSavedTab => 'Navigate to Saved tab';
  String get myPurchases => 'My Purchases';
  String get postListings => 'post listings';
  // ---------- Notifications ----------
  String get notificationDeleted => 'Notification deleted';
  String get loginToReceiveNotifications => 'Login to receive notifications.';
  String get markAllAsRead => 'Mark all as read';
  String get clearAll => 'Clear all';
  String get noNotifications => 'No notifications';
  String get notificationsWillAppearHere =>
      'Your notifications will appear here.';
  String get receiveNotifications => 'Login to receive notifications.';
  // ---------- Profile ----------
  String get guestUser => 'Guest user';
  String get browseWithoutAccount => 'Browsing without an account';
  String memberSince(String m) => 'Member since $m';
  String get editProfile => 'Edit Profile';
  // ---------- Cities ----------
  String get harare => 'Harare';
  String get bulawayo => 'Bulawayo';
  String get chitungwiza => 'Chitungwiza';
  String get mutare => 'Mutare';
  String get gweru => 'Gweru';
  String get kwekwe => 'Kwekwe';
  String get kadoma => 'Kadoma';
  String get masvingo => 'Masvingo';
  String get chinhoyi => 'Chinhoyi';
  String get chegutu => 'Chegutu';
  String get bindura => 'Bindura';
  String get marondera => 'Marondera';
  String get redcliff => 'Redcliff';
  // ---------- Variants / Typos ----------
  String get saveItems => 'Save items';
  String get saveltems => 'Save items'; // l/I 误写
  @override
  dynamic noSuchMethod(Invocation invocation) => '';
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(AppLocalizations(const Locale('en')));
  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

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

// ========= 全局 Auth 处理（欢迎弹窗改为新版统一控制） =========

// ===== 兼容旧版本：占位函数（不再使用，但保留以免编译报错） =====
@pragma('vm:prefer-inline')
String _fixUtf8Mojibake(String? raw) => raw ?? '';

@pragma('vm:prefer-inline')
void _showWelcomeGiftDialog() {
  // 已废弃：欢迎券弹窗由新版 WelcomeCouponDialog 在页面侧触发。
}

Future<void> _migrateWelcomeKeys(String userId) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('new_user_welcome_pending_$userId');
  await prefs.remove('welcome_gift_shown_$userId');
}

void wireAuthHook() {
  if (_authHookWired) return;
  _authHookWired = true;

  final auth = Supabase.instance.client.auth;
  _globalAuthSub?.cancel();

  _globalAuthSub = auth.onAuthStateChange.listen((data) async {
    final event = data.event;

    // ✅ 找回密码：只导航一次
    if (event == AuthChangeEvent.passwordRecovery && !_navigatedToReset) {
      _navigatedToReset = true;
      debugPrint(
          '[Auth] passwordRecovery detected -> navigate ResetPasswordPage');
      appNavKey.currentState?.pushNamed('/reset-password');
      return;
    }

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
        // 1) 订阅通知
        await NotificationService.subscribeUser(u.id);

        // 2) 资料兜底
        try {
          await _ensureProfileForCurrentUserOnce();
        } catch (e) {
          debugPrint('[Auth] Profile sync error: $e');
        }

        // 3) 仅确保“欢迎券存在” + 清理旧键；展示交由新版弹窗
        try {
          await RewardService.ensureWelcomeForCurrentUser();
          await _migrateWelcomeKeys(u.id);
        } catch (e) {
          debugPrint('[Auth] ensureWelcomeForCurrentUser error: $e');
        }

        // 4) 导航 & 安排欢迎券弹窗检查
        final ctx = appNavKey.currentContext;
        if (ctx != null) {
          // 仅在真正登录(signedIn)时回到首页，避免 initialSession 二次 push
          if (event == AuthChangeEvent.signedIn) {
            final current = ModalRoute.of(ctx)?.settings.name;
            if (current != '/home') {
              Navigator.of(ctx)
                  .pushNamedAndRemoveUntil('/home', (route) => false);
            }
          }
          // ✅ 新增：不论 initialSession 还是 signedIn，只要有 ctx 就安排检查
          WelcomeDialogService.scheduleCheck(ctx);
        }
      }
    }

    if (event == AuthChangeEvent.signedOut) {
      await NotificationService.unsubscribe();
      CouponService.clearCache();
      DualFavoritesService.clearCache();
      RewardService.clearCache();

      final ctx = appNavKey.currentContext;
      if (ctx != null) {
        Navigator.of(ctx)
            .pushNamedAndRemoveUntil('/welcome', (route) => false);
      }
    }
  });
}

// ✅ 统一处理 Supabase 深链
Future<void> _handleSupabaseUri(Uri? uri) async {
  if (uri == null) return;
  try {
    final params = <String, String>{};
    params.addAll(uri.queryParameters);
    if (uri.fragment.isNotEmpty) {
      try {
        params.addAll(Uri.splitQueryString(uri.fragment));
      } catch (e) {
        final frag = uri.fragment.replaceAll('#', '').replaceAll('?', '&');
        params.addAll(Uri.splitQueryString(frag));
      }
    }

    final type = (params['type'] ?? params['event'] ?? '').toLowerCase();
    final code = params['code'];
    final refreshToken = params['refresh_token'];

    if (code != null && code.isNotEmpty) {
      await Supabase.instance.client.auth.exchangeCodeForSession(code);
      debugPrint('[DeepLink] exchangeCodeForSession ok');
    } else if (refreshToken != null && refreshToken.isNotEmpty) {
      await Supabase.instance.client.auth.setSession(refreshToken);
      debugPrint('[DeepLink] setSession(refresh_token) ok');
    } else {
      debugPrint('[DeepLink] no code/refresh_token in uri: $uri');
    }

    if (type == 'recovery' && !_navigatedToReset) {
      _navigatedToReset = true;
      appNavKey.currentState?.pushNamed('/reset-password');
    }
  } catch (e) {
    debugPrint('[DeepLink] handle uri error: $e');
  }
}

// ✅ 获取初始深链并尝试恢复会话
Future<void> _recoverInitialSupabaseSession() async {
  try {
    final uri = await AppLinks().getInitialLink();
    await _handleSupabaseUri(uri);
    if (uri != null) {
      debugPrint('[DeepLink] initial uri handled: $uri');
    }
  } catch (e) {
    debugPrint('[DeepLink] initial recover error: $e');
  }
}

// ✅ 资料兜底
Future<void> _ensureProfileForCurrentUserOnce() async {
  final client = Supabase.instance.client;
  final u = client.auth.currentUser;
  if (u == null) return;

  try {
    final rows =
    await client.from('profiles').select('id').eq('id', u.id).limit(1);

    final meta = u.userMetadata ?? const {};
    final fullName = (meta['full_name'] ?? meta['name'] ?? '').toString();
    final phone = (meta['phone'] ?? '').toString();

    if (rows.isEmpty) {
      await client.from('profiles').insert({
        'id': u.id,
        'email': u.email,
        if (fullName.isNotEmpty) 'full_name': fullName,
        if (phone.isNotEmpty) 'phone': phone,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      debugPrint('[Profile] created profile row for ${u.id}');
    } else {
      final patch = <String, dynamic>{};
      if (fullName.isNotEmpty) patch['full_name'] = fullName;
      if (phone.isNotEmpty) patch['phone'] = phone;
      if (patch.isNotEmpty) {
        patch['updated_at'] = DateTime.now().toUtc().toIso8601String();
        await client.from('profiles').update(patch).eq('id', u.id);
        debugPrint('[Profile] patched profile for ${u.id}');
      }
    }
  } catch (e) {
    debugPrint('[Profile] ensure/sync error: $e');
  }
}

// ✅ 前台监听后续深链
void _listenDeepLinksForSupabase() {
  _deeplinkSub?.cancel();
  final links = AppLinks();
  _deeplinkSub = links.uriLinkStream.listen((Uri uri) async {
    try {
      await _handleSupabaseUri(uri);
      debugPrint('[DeepLink] stream uri handled: $uri');
    } catch (e) {
      debugPrint('[DeepLink] stream recover error: $e');
    }
  }, onError: (e) {
    debugPrint('[DeepLink] stream error: $e');
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ Edge-to-Edge
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  ));

  // 屏蔽刷新日志
      {
    final orig = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null &&
          message.contains('supabase.auth: INFO: Refresh session')) {
        return;
      }
      orig(message, wrapWidth: wrapWidth);
    };
  }

  // 全局错误兜底
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
                Text('Something went wrong',
                    style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 14.sp)),
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

  // ✅ Supabase 初始化
  await Supabase.initialize(
    url: 'https://rhckybselarzglkmlyqs.supabase.co',
    anonKey:
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJoY2t5YnNlbGFyemdsa21seXFzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTUwMTM0NTgsImV4cCI6MjA3MDU4OTQ1OH0.3I0T2DidiF-q9l2tWeHOjB31QogXHDqRtEjDn0RfVbU',
    authOptions: const FlutterAuthClientOptions(
      autoRefreshToken: true,
    ),
    // debug: true,
  );

  // ✅ 初始深链
  await _recoverInitialSupabaseSession();

  // ✅ 冷/热启动：如当前已登录，先订阅通知
  final supaClient = Supabase.instance.client;
  final bootUser = supaClient.auth.currentUser;
  if (bootUser != null) {
    await NotificationService.subscribeUser(bootUser.id);
  }

  // ✅ 全局 Auth 监听
  wireAuthHook();

  // ✅ 启动应用
  runApp(
    ChangeNotifierProvider<LanguageProvider>(
      create: (context) => LanguageProvider(),
      child: const MyApp(),
    ),
  );

  // ✅ 前台深链
  _listenDeepLinksForSupabase();
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    RecoveryProbe.attach(); // 仅打印日志
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    RecoveryProbe.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        debugPrint('App resumed - clearing notifications if needed');
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
    final hasSession = Supabase.instance.client.auth.currentSession != null;

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
              navigatorKey: appNavKey,
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
              initialRoute: hasSession ? '/home' : '/welcome',
              routes: <String, WidgetBuilder>{
                '/welcome': (BuildContext context) => const WelcomeScreen(),
                '/login': (BuildContext context) => const LoginScreen(),
                '/home': (BuildContext context) => MainNavigationPage(
                  isGuest:
                  Supabase.instance.client.auth.currentSession == null,
                ),
                '/coupons': (BuildContext context) =>
                const CouponManagementPage(),
                '/reset-password': (BuildContext context) =>
                const ResetPasswordPage(),
              },
            );
          },
        );
      },
    );
  }
}

// ===================== MainNavigationPage (patched) =====================

class MainNavigationPage extends StatefulWidget {
  final bool isGuest;
  const MainNavigationPage({super.key, this.isGuest = false});
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

  // 🔔 未读角标 & 订阅句柄
  int _notificationCount = 0;
  StreamSubscription<Map<String, dynamic>>? _notifSub;

  // 冷启动或需要时同步未读数
  Future<void> _syncUnread() async {
    final n = await NotificationService.getUnreadNotificationsCount();
    if (!mounted) return;
    setState(() => _notificationCount = n);
  }

  late AnimationController _sellButtonController;
  late Animation<double> _sellButtonAnimation;

  final _homeKey = GlobalKey<NavigatorState>();
  final _savedKey = GlobalKey<NavigatorState>();
  final _sellKey = GlobalKey<NavigatorState>();
  final _notifKey = GlobalKey<NavigatorState>();
  final _profileKey = GlobalKey<NavigatorState>();

  late final List<GlobalKey<NavigatorState>> _navigatorKeys = [
    _homeKey,
    _savedKey,
    _sellKey,
    _notifKey,
    _profileKey,
  ];

  static bool _welcomeGiftChecked = false;

  @override
  void initState() {
    super.initState();

    // 先同步一次未读数
    if (!widget.isGuest) {
      _syncUnread();
    }

    // 监听 NotificationService 的全局广播：INSERT/UPDATE 实时刷新角标
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      _notifSub = NotificationService.stream.listen((evt) {
        if (!mounted) return;

        // 可选：服务端广播重置信号
        if (evt['_type'] == '__reset__') {
          setState(() => _notificationCount = 0);
          return;
        }

        // 只处理属于当前用户的事件
        final recipient = (evt['recipient_id'] ?? '').toString();
        if (recipient != user.id) return;

        final isRead = evt['is_read'] == true;
        final isDeleted = evt['is_deleted'] == true;

        // UPDATE（已读/删除）→ 全量刷新；INSERT（未读）→ +1
        if (isRead || isDeleted) {
          _syncUnread();
        } else {
          setState(() {
            _notificationCount = (_notificationCount + 1).clamp(0, 999);
          });
        }
      });
    }

    _loadNotificationCount();

    _sellButtonController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _sellButtonAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _sellButtonController, curve: Curves.easeInOut),
    );

    // ✅ 新增：首帧后进行“版本更新检查”（只提示、不强制由服务端控制）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AppUpdateService.checkForUpdates(context);
    });

    if (!widget.isGuest) {
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
    _notifSub?.cancel();
    _notifSub = null;
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

      final alreadyShown = prefs.getBool(shownKey) ?? false;
      if (alreadyShown) {
        _welcomeGiftChecked = true;
        await prefs.remove(pendingKey);
        return;
      }

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
        if (rows.isNotEmpty) {
          row = rows.first;
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
              'Welcome gift 🎁',
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
                        MaterialPageRoute(
                            builder: (context) => const TaskManagementPage()),
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
                            builder: (context) =>
                            const CouponManagementPage()),
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
    if (!widget.isGuest) {
      try {
        final count =
        await NotificationService.getUnreadNotificationsCount();
        if (mounted) {
          setState(() => _notificationCount = count);
        }
      } catch (e) {
        if (kDebugMode) {}
      }
    }
  }

  void _onPopInvokedWithResult(bool didPop, Object? result) {
    if (didPop) return;
    final current = _navigatorKeys[_selectedIndex].currentState!;
    if (current.canPop()) current.pop();
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
          title: Text(l10n.loginRequired,
              style:
              TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
          content: Text(l10n.loginRequiredMessage(feature),
              style: TextStyle(fontSize: 13.sp, height: 1.4)),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel,
                    style: TextStyle(
                        fontSize: 13.sp, color: Colors.grey[600]))),
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF2196F3), Color(0xFF1E88E5)]),
                borderRadius: BorderRadius.circular(6.w),
              ),
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context)
                      .pushNamedAndRemoveUntil('/welcome', (route) => false);
                },
                child: Text(l10n.login,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTabNavigator(
      GlobalKey<NavigatorState> key, Widget root, LanguageProvider languageProvider) {
    return Navigator(
      key: key,
      onGenerateRoute: (_) => MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider<LanguageProvider>.value(
          value: languageProvider,
          child: root,
        ),
      ),
    );
  }

  void _navigateToHome() {
    setState(() => _selectedIndex = 0);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final languageProvider = Provider.of<LanguageProvider>(context);

    // ✅ 导航条实际占用：图标行 52 + 上下 padding 12 + iOS Home 指示器安全区
    final double _navGap = 52.h + 12.h + MediaQuery.of(context).padding.bottom;

    final List<Widget> pages = [
      _buildTabNavigator(
        _homeKey,
        const IosInsetsGuard(child: _HomeRoot()),
        languageProvider,
      ),
      _buildTabNavigator(
        _savedKey,
        _SavedRoot(
          isGuest: widget.isGuest,
          onNavigateToHome: _navigateToHome,
        ),
        languageProvider,
      ),
      _buildTabNavigator(
        _sellKey,
        _SellRoot(isGuest: widget.isGuest),
        languageProvider,
      ),
      _buildTabNavigator(
        _notifKey,
        _NotifRoot(
          onClearBadge: _clearNotifications,
          isGuest: widget.isGuest,
          onNotificationCountChanged: (count) {
            if (mounted) setState(() => _notificationCount = count);
          },
        ),
        languageProvider,
      ),
      // ✅ 仅对 Profile 根页增加底部留白，避免 Logout 被遮挡
      _buildTabNavigator(
        _profileKey,
        Padding(
          padding: EdgeInsets.only(bottom: _navGap),
          child: _ProfileRoot(isGuest: widget.isGuest),
        ),
        languageProvider,
      ),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onPopInvokedWithResult,
      child: Scaffold(
        extendBody: true, // ✅ 让 body 延伸到导航条下
        backgroundColor: Colors.white,
        body: IndexedStack(
          index: _selectedIndex,
          children: pages,
        ),

        // ✅ 修复：导航条本体占满到底，安全区仅作用在内部内容
        bottomNavigationBar: Builder(
          builder: (ctx) {
            final double bottomPad = MediaQuery.of(ctx).padding.bottom; // iOS 底部安全区高度
            final bool isiOS = defaultTargetPlatform == TargetPlatform.iOS;
            final Color barBg = isiOS ? const Color(0xFFF2F2F7) : Colors.white;

            return Material(
              color: barBg,
              surfaceTintColor: Colors.transparent, // 关闭 M3 表面叠色
              child: Container(
                decoration: BoxDecoration(
                  color: barBg,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 10.h,
                      offset: Offset(0, -2.h),
                    ),
                  ],
                ),
                // ⬇️ 关键：把安全区高度加到“内部”padding 的 bottom
                padding: EdgeInsets.fromLTRB(8.w, 6.h, 8.w, 6.h + bottomPad),
                child: SizedBox(
                  height: 52.h, // 只控制图标行高度
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildCompactNavItem(
                        icon: Icons.home_outlined,
                        activeIcon: Icons.home_rounded,
                        label: l10n.home,
                        index: 0,
                        context: ctx,
                      ),
                      _buildCompactNavItem(
                        icon: Icons.bookmark_outline_rounded,
                        activeIcon: Icons.bookmark_rounded,
                        label: l10n.saved,
                        index: 1,
                        context: ctx,
                      ),
                      _buildCentralSellButton(ctx),
                      _buildCompactNavItemWithBadge(
                        icon: Icons.notifications_outlined,
                        activeIcon: Icons.notifications_rounded,
                        label: l10n.notifications,
                        index: 3,
                        badgeCount: _notificationCount,
                        context: ctx,
                      ),
                      _buildCompactNavItem(
                        icon: Icons.person_outline_rounded,
                        activeIcon: Icons.person_rounded,
                        label: l10n.profile,
                        index: 4,
                        context: ctx,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ================= 底部导航项 =================
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
        if (widget.isGuest && (index == 1)) {
          _showLoginRequired(l10n.saveItems, context);
          return;
        }
        setState(() => _selectedIndex = index);
      },
      child: SizedBox(
        width: 64.w, // ⬅️ 比原来 60.w 略宽，避免英文长词被挤
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
                  key: ValueKey('${index}_$isSelected'),
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
                  fontWeight:
                  isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                    textAlign: TextAlign.center,
                  ),
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
        if (widget.isGuest) {
          _showLoginRequired(l10n.receiveNotifications, context);
          return;
        }
        setState(() {
          _selectedIndex = index;
          if (index == 3) {
            _notificationCount = 0;
          }
        });
      },
      child: SizedBox(
        width: 64.w, // ⬅️ 同步扩宽
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
                      key: ValueKey('${index}_$isSelected'),
                      color: isSelected ? _PRIMARY_BLUE : Colors.grey[600],
                      size: 22.w,
                    ),
                  ),
                  if (badgeCount > 0 && !widget.isGuest)
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
                  fontWeight:
                  isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label, // “Notifications” 将自动收缩不再显示“...”
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                    textAlign: TextAlign.center,
                  ),
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
        if (widget.isGuest) {
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

// ===================== /MainNavigationPage (patched) =====================

/* ------------------------------------------------ */
/* =========== TOP-LEVEL WIDGETS START HERE =========== */
/* ------------------------------------------------ */

// 盲驴庐氓陇陋茅鈥⒙棵寂捗λ嗏€樏ヂ徛ヂ扁€⒚ぢ好ぢ衡€犆ぢ柯︹€澛姑♀€灻?赂氓驴茠茅茠篓氓藛鈥犆ｂ偓鈥毭モ€β睹ぢ解劉茅茠篓氓藛鈥犆ぢ柯澝ε捖伱ぢ嘎嵜ヂ徦?
/* ---------------- Tab 忙 鹿茅隆碌 ---------------- */

class _HomeRoot extends StatelessWidget {
  const _HomeRoot();
  @override
  Widget build(BuildContext context) => const swaply.HomePage();
}

// 盲驴庐忙鈥澛姑寂∶β仿幻ヅ?氓炉录猫藛陋氓鈥号久捌捗ヂ忊€毭︹€⒙?
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

/* ---------------- Saved Page (收藏页) START ---------------- */
class SavedPage extends StatefulWidget {
  final bool isGuest;
  final VoidCallback? onNavigateToHome;

  const SavedPage({super.key, this.isGuest = false, this.onNavigateToHome});
  @override
  State<SavedPage> createState() => _SavedPageState();
}

class _SavedPageState extends State<SavedPage> with WidgetsBindingObserver {
  // ✅ 统一 Facebook 蓝
  static const Color _PRIMARY_BLUE = Color(0xFF1877F2);

  List<Map<String, dynamic>> _favoriteItems = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;
  Timer? _autoRefreshTimer;
  StreamSubscription<FavoriteUpdateEvent>? _favoritesSubscription;

  // ✅ A) 精简版蓝色头部（与通知页完全一致：更短、更上移；标题与右上角按钮同一基线）
  Widget _blueHeader({
    required BuildContext context,
    required String title,
    required bool centerTitle,
    Widget? trailing, // 右上角按钮（可选）
  }) {
    final double statusBar = MediaQuery.of(context).padding.top;
    const double kHeaderVisual = 48.0;
    const double kSide = 20.0;

    return SizedBox(
      height: statusBar + kHeaderVisual,
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1877F2), Color(0xFF1E88E5)],
                ),
              ),
            ),
          ),
          Positioned(
            left: kSide,
            right: 12.0,
            top: statusBar + 6.0,
            child: SizedBox(
              height: 36.0,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      textAlign: centerTitle ? TextAlign.center : TextAlign.left,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                  ),
                  if (trailing != null) trailing,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ B) 右上角菜单按钮（更小 28×28，与标题对齐）
  Widget _buildMenuButton() {
    final bool isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      offset: const Offset(0, 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10.w),
      ),
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
              Icon(Icons.clear_all_rounded, color: Colors.red, size: 12.w),
              SizedBox(width: 8.w),
              Text('Clear All', style: TextStyle(fontSize: 11.sp)),
            ],
          ),
        ),
      ],
      child: SizedBox(
        height: 28.w,
        width: 28.w,
        child: Material(
          color: Colors.white.withOpacity(0.18),
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: Center(
            child: Icon(
              isIOS ? Icons.more_horiz_rounded : Icons.more_vert_rounded,
              color: Colors.white,
              size: 18.w,
            ),
          ),
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
      _startAutoRefresh();           // ✅ 这里需要下面的方法
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !widget.isGuest) {
      _loadFavorites();
    }
  }

  /// ✅ 自动刷新（每30秒），避免并发；离开页面在 dispose 中已取消
  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer =
        Timer.periodic(const Duration(seconds: 30), (timer) {
          if (!widget.isGuest && mounted && !_isRefreshing) {
            if (kDebugMode) print('Auto-refresh favorites…');
            _loadFavorites();
          }
        });
  }

  /// 猫庐戮莽陆庐忙鈥澛睹ㄢ€斅徝︹€郝疵︹€撀懊р€衡€樏ヂ惵?
  void _setupFavoritesListener() {
    _favoritesSubscription =
        FavoritesUpdateService().favoritesStream.listen((event) {
          if (!mounted || widget.isGuest) return;
          if (kDebugMode) {}
          if (event.isAdded && event.listingData != null) {
            _addToLocalFavorites(event.listingData!);
          } else if (!event.isAdded) {
            _removeFromLocalFavorites(event.listingId);
          }
        }, onError: (error) {
          if (kDebugMode) print('Error in favorites stream: $error');
        });
  }

  /// 莽芦鈥姑ヂ嵚趁β仿幻ヅ?氓藛掳忙艙卢氓艙掳忙鈥澛睹ㄢ€斅徝ニ嗏€斆铰β?
  void _addToLocalFavorites(Map<String, dynamic> listingData) {
    try {
      final listingId = listingData['id']?.toString();
      if (listingId == null) return;
      final exists = _favoriteItems.any((item) =>
      item['listing_id']?.toString() == listingId ||
          item['listing']?['id']?.toString() == listingId);
      if (!exists) {
        final favoriteItem = {
          'listing_id': listingId,
          'listing': _safeMapConvert(listingData),
          'created_at': DateTime.now().toIso8601String(),
        };
        setState(() {
          _favoriteItems.insert(0, favoriteItem);
        });
        if (kDebugMode) {}
      }
    } catch (e) {
      if (kDebugMode) print('Error adding to local favorites: $e');
    }
  }

  /// 莽芦鈥姑ヂ嵚趁ぢ慌矫ε撀ヅ撀懊︹€澛睹ㄢ€斅徝ニ嗏€斆÷幻┾劉隴
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

  /// 氓庐鈥懊莫€βㄅ铰访ヂ忊€撁ヂ€斆γぢ嘎裁モ偓录
  String _safeGetString(Map<String, dynamic> map, String key,
      {String defaultValue = ''}) {
    try {
      return map[key]?.toString() ?? defaultValue;
    } catch (e) {
      if (kDebugMode) print('Error getting string for key $key: $e');
      return defaultValue;
    }
  }

  /// 氓艩 猫陆陆忙鈥澛睹ㄢ€斅徝ニ嗏€斆÷?- DualFavoritesService
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
      final rawItems = await DualFavoritesService.getUserFavorites(
        userId: user.id,
        limit: 100,
      );
      if (mounted) {
        final safeItems = <Map<String, dynamic>>[];
        for (final item in rawItems) {
          final safeItem = _safeMapConvert(item);
          if (safeItem.isNotEmpty) {
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

  /// 盲禄沤忙鈥澛睹ㄢ€斅徝ヂぢ姑幻┾劉隴氓鈥⑩€犆モ€溌?- DualFavoritesService
  Future<void> _removeFromFavorites(String listingId, int index) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      final success = await DualFavoritesService.removeFromFavorites(
        userId: user.id,
        listingId: listingId,
      );
      if (success && mounted) {
        setState(() {
          _favoriteItems.removeAt(index);
        });
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
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.w)),
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

  /// 猫沤路氓聫鈥撁モ€⑩€犆モ€溌伱モ€郝久р€扳€?- 莽录漏氓掳聫
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

  /// 忙 录氓录聫氓艗鈥撁ぢ宦访?录
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

  /// 忙啪鈥灻ヂ宦好┞好-卡片
  Widget _buildFavoriteCard(Map<String, dynamic> item, int index) {
    try {
      final safeListing = _safeMapConvert(item['listing'] ?? {});
      final safeItem = _safeMapConvert(item);
      final listingId = _safeGetString(safeItem, 'listing_id');
      if (listingId.isEmpty) {
        if (kDebugMode) print('Warning: Empty listing ID for item at $index');
        return const SizedBox.shrink();
      }
      final title =
      _safeGetString(safeListing, 'title', defaultValue: 'Unknown Item');
      final price = _formatPrice(safeListing['price']);
      final city = _safeGetString(safeListing, 'city');
      final imageUrl = _getListingImage(safeListing);
      final createdAt = _safeGetString(safeItem, 'created_at');
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
              ).then((_) => _loadFavorites());
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
                  // 图片
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

                  // 文本信息
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

                  // 右侧按钮
                  Container(
                    margin: EdgeInsets.only(left: 4.w),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2196F3).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6.w),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _showRemoveDialog(title, listingId, index),
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
    } catch (e) {
      if (kDebugMode) {}
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

  /// 删除确认
  void _showRemoveDialog(String title, String listingId, int index) {
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

  /// 空态
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
                  if (widget.onNavigateToHome != null) {
                    widget.onNavigateToHome!();
                  } else {
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

  /// 错态
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
    AppLocalizations? l10n;
    try {
      l10n = AppLocalizations.of(context);
    } catch (e) {
      if (kDebugMode) {}
    }

    if (widget.isGuest) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        body: Column(
          children: [
            _blueHeader(
              context: context,
              title: l10n?.myFavorites ?? 'My Favorites',
              centerTitle: false,
              trailing: null,
            ),
            Expanded(
              child: Center(
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
                        gradient: const LinearGradient(
                          colors: [_PRIMARY_BLUE, Color(0xFF1E88E5)],
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
                          Navigator.of(context).pushNamedAndRemoveUntil(
                              '/welcome', (route) => false);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: EdgeInsets.symmetric(
                              horizontal: 16.w, vertical: 8.h),
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
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: Column(
        children: [
          _blueHeader(
            context: context,
            title: 'My Favorites (${_favoriteItems.length})',
            centerTitle: false,
            trailing:
            (_favoriteItems.isNotEmpty && !_isLoading) ? _buildMenuButton() : null,
          ),
          Expanded(
            child: _isLoading
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 24.w,
                    height: 24.w,
                    child: CircularProgressIndicator(
                      valueColor:
                      const AlwaysStoppedAnimation<Color>(_PRIMARY_BLUE),
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
              color: _PRIMARY_BLUE,
              backgroundColor: Colors.white,
              strokeWidth: 2.w,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                // ✅ 统一更紧凑的顶部间距：12
                padding: EdgeInsets.only(top: 12.h),
                itemCount: _favoriteItems.length,
                itemBuilder: (context, index) {
                  return _buildFavoriteCard(
                      _favoriteItems[index], index);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 清空确认
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

  /// 清空所有收藏
  Future<void> _clearAllFavorites() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      final currentItems = List<Map<String, dynamic>>.from(_favoriteItems);
      final success =
      await DualFavoritesService.clearUserFavorites(userId: user.id);
      if (success && mounted) {
        setState(() {
          _favoriteItems.clear();
        });
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
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.w)),
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

/* ---------------- Wishlist Page 收藏夹页面 - 统一服务 ---------------- */

class WishlistPage extends StatefulWidget {
  const WishlistPage({super.key});

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

  /// 加载收藏夹列表
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

      // 使用 DualFavoritesService 获取收藏夹（包含 wishlists 和 favorites）
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

  /// 刷新收藏夹
  Future<void> _refreshWishlist() async {
    setState(() => _isRefreshing = true);
    await _loadWishlist();
    setState(() => _isRefreshing = false);
  }

  /// 从收藏夹和喜爱中移除
  Future<void> _removeFromWishlist(String listingId, int index) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      // 使用 DualFavoritesService 移除
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

  /// 获取列表图片
  String _getListingImage(Map<String, dynamic> listing) {
    final images = listing['images'] ?? listing['image_urls'];
    if (images is List && images.isNotEmpty) {
      return images.first.toString();
    }
    return 'assets/images/placeholder.jpg';
  }

  /// 格式化价格
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

  /// 构建收藏卡片
  Widget _buildWishlistCard(Map<String, dynamic> item, int index) {
    final listing = item['listing'] ?? {};
    final listingId =
        item['listing_id']?.toString() ?? listing['id']?.toString() ?? '';
    final title = listing['title']?.toString() ?? 'Unknown Item';
    final price = _formatPrice(listing['price']);
    final city = listing['city']?.toString() ?? '';
    final imageUrl = _getListingImage(listing);
    final createdAt = item['created_at']?.toString() ?? '';

    // 格式化时间
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
              // 返回时重新加载，以防用户在详情页取消了收藏
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
                // 图片
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

                // 信息
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

                // 移除按钮
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

  /// 弹出移除确认框
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

  /// 构建空状态
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

  /// 构建错误状态
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

  // ✅ [MODIFIED] 统一的 AppBar 构建器 (已按 verification_page.dart 标准重写)
  PreferredSizeWidget _buildStandardAppBar(BuildContext context) {
    final double statusBar = MediaQuery.of(context).padding.top;
    final bool isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    const Color kBgColor = Colors.pink; // 此页面的背景色

    // 动态标题
    final String title = 'My Wishlist (${_wishlistItems.length})';
    final titleStyle = TextStyle(
      color: Colors.white,
      fontSize: 16.sp, // (保持原 sp)
      fontWeight: FontWeight.w600,
    );

    // 动态 Actions
    final actionsWidget = (_wishlistItems.isNotEmpty && !_isLoading)
        ? PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded,
          color: Colors.white, size: 20.w), // (保持原 w)
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
    )
        : null; // iOS 侧如果为 null，SizedBox 占位

    // ============== Android & 其他：保持原 AppBar 不变 ==============
    if (!isIOS) {
      return AppBar(
        backgroundColor: kBgColor,
        title: Text(title, style: titleStyle),
        elevation: 0,
        actions: actionsWidget != null ? [actionsWidget] : [],
        leading: IconButton(
          // (确保 Android 也有返回按钮)
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      );
    }

    // ===== ✅ [MODIFIED] iOS：使用“基准页” (verification_page.dart) 的 44pt Row 布局 =====

    // 1. 标准布局数值
    const double kNavBarHeight = 44.0; // 标准导航条高度
    const double kButtonSize = 32.0; // 标准按钮尺寸
    const double kSidePadding = 16.0; // 标准左右内边距
    const double kButtonSpacing = 12.0; // 标准间距

    // 2. 构建 32x32 返回按钮
    final Widget iosBackButton = SizedBox(
      width: kButtonSize,
      height: kButtonSize,
      child: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10), // 保持原圆角
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.arrow_back_ios_new, // 保持原图标
              size: 18,
              color: Colors.white),
        ),
      ),
    );

    // 3. 构建居中标题
    final Widget iosTitle = Expanded(
      child: Text(
        title, // 动态标题
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center, // 保证居中
        style: const TextStyle(
          // (应用标准 Style)
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
    );

    // 4. 构建 32x32 右侧 Action
    final Widget iosRightButton = SizedBox(
      width: kButtonSize,
      height: kButtonSize,
      child: actionsWidget != null
          ? Center(child: actionsWidget) // 居中 Action
          : null, // 如果没有 Action，则为空
    );

    // 5. 组装
    return PreferredSize(
      preferredSize: Size.fromHeight(statusBar + kNavBarHeight), // ✅ 44pt + statusBar
      child: Container(
        color: kBgColor,
        padding: EdgeInsets.only(top: statusBar), // 让出状态栏
        child: SizedBox(
          height: kNavBarHeight, // 44pt
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: kSidePadding), // 16
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center, // 垂直居中
              children: [
                iosBackButton, // 32x32
                const SizedBox(width: kButtonSpacing), // 12
                iosTitle, // Expanded
                const SizedBox(width: kButtonSpacing), // 12
                iosRightButton, // 32x32 (Action 或空占位)
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      // ✅ [MODIFIED] 替换 AppBar
      appBar: _buildStandardAppBar(context),
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

  /// 弹出清空确认框
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

  /// 清空收藏夹
  Future<void> _clearAllWishlist() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      // 使用 DualFavoritesService 清空
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
/* ---------------- Sell Page ---------------- */

class SellPage extends StatefulWidget {
  final bool isGuest;
  const SellPage({super.key, this.isGuest = false});

  @override
  State<SellPage> createState() => _SellPageState();
}

class _SellPageState extends State<SellPage> with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // ✅ [MODIFIED] 统一蓝色头部（iOS 已按 standard 布局；Android 改为与 iOS 同构的行布局，标题与右上角按钮严格对齐，并缩短蓝色区域）
  Widget _blueHeader({
    required BuildContext context,
    required String title,
    required bool centerTitle,
    Widget? trailing,
    double trailingTopAdjust = 0.0, // (参数保留；Android 新布局不再需要额外上移)
  }) {
    final double statusBar = MediaQuery.of(context).padding.top;
    final bool isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    const Color kUserPrimaryBlue = Color(0xFF1877F2);

    // ============== Android (NEW: 同构行布局，蓝区更短) ==============
    if (!isIOS) {
      const double kHeaderVisual = 44.0;   // ✅ 缩短蓝色区域
      const double kSideTop = 2.0;         // ✅ 顶部行距
      const double kSide = 16.0;           // ✅ 左右边距
      const double kBtnSize = 32.0;        // ✅ 右上角按钮尺寸
      const double kSpacing = 16.0;        // ✅ 占位与标题间距
      const double kTitleTop = -5.0;       // ✅ 轻微上移标题，和按钮基线视觉对齐

      return SizedBox(
        height: statusBar + kHeaderVisual,
        child: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [kUserPrimaryBlue, Color(0xFF1E88E5)],
                  ),
                ),
              ),
            ),
            // 左侧占位（保持标题真正居中）
            Positioned(
              top: statusBar + kSideTop,
              left: kSide,
              child: const SizedBox(width: kBtnSize, height: kBtnSize),
            ),
            // 标题（左右各预留按钮+间距，确保与右侧按钮处于同一“行”）
            Positioned(
              top: statusBar + kTitleTop,
              left: kSide + kBtnSize + kSpacing,
              right: kSide + kBtnSize + kSpacing,
              child: Text(
                title,
                textAlign: centerTitle ? TextAlign.center : TextAlign.left,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            // 右上角按钮 —— 与标题同一行顶距（已对齐）
            if (trailing != null)
              Positioned(
                top: statusBar + kSideTop, // ✅ 与标题“行”对齐
                right: kSide,
                child: SizedBox(height: kBtnSize, width: kBtnSize, child: trailing),
              ),
          ],
        ),
      );
    }

    // ============== iOS (Verification Page Standard Logic) ==============
    const double kHeaderVisual = 38.0; // Standard
    const double kTitleTop = -7.0;     // Standard
    const double kSideTop = 2.0;       // Standard
    const double kSide = 16.0;         // Standard
    const double kBtnSize = 32.0;
    const double kSpacing = 16.0;

    return SizedBox(
      height: statusBar + kHeaderVisual,
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [kUserPrimaryBlue, Color(0xFF1E88E5)],
                ),
              ),
            ),
          ),
          Positioned(
            top: statusBar + kSideTop,
            left: kSide,
            child: const SizedBox(width: kBtnSize, height: kBtnSize),
          ),
          Positioned(
            top: statusBar + kTitleTop,
            left: kSide + kBtnSize + kSpacing,
            right: kSide + kBtnSize + kSpacing,
            child: Text(
              title,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (trailing != null)
            Positioned(
              top: statusBar + kSideTop,
              right: kSide,
              child: SizedBox(height: kBtnSize, width: kBtnSize, child: trailing),
            ),
        ],
      ),
    );
  }

  // 右上角「+」按钮（外框 28×28，更小更紧凑）
  Widget _buildPlusButton(BuildContext context) {
    const double box = 32.0;
    const double icon = 19.0;

    return Container(
      width: box,
      height: box,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: IconButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SellFormPage()),
        ),
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        iconSize: icon,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: box, height: box),
        splashRadius: box / 2,
        visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
        tooltip: 'Add New Listing',
      ),
    );
  }

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
      // 访客视图保持不变
      return _buildGuestView(l10n);
    }

    final raw = ListingStore.i.getAll();
    final List<Map<String, dynamic>> myListings =
    (raw is List) ? List<Map<String, dynamic>>.from(raw) : const <Map<String, dynamic>>[];

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: CustomScrollView(
        physics: const NeverScrollableScrollPhysics(),
        slivers: [
          // 头部：标题居中，右上角 + 与标题对齐
          SliverToBoxAdapter(
            child: _blueHeader(
              context: context,
              title: l10n.sellItem,
              centerTitle: true,
              trailing: _buildPlusButton(context),
              trailingTopAdjust: -6.0, // （Android 新布局已对齐，此值不再生效，但保留参数）
            ),
          ),
          if (myListings.isEmpty)
            _buildEmptyState(l10n)
          else
            _buildListingsContent(myListings, l10n),
        ],
      ),
    );
  }

  Widget _buildGuestView(AppLocalizations l10n) {
    // 访客视图保持不变
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1877F2),
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
                        colors: [Color(0xFF1877F2), Color(0xFF1E88E5)],
                      ),
                      borderRadius: BorderRadius.circular(16.r),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF1877F2).withOpacity(0.4),
                          blurRadius: 16.r,
                          offset: Offset(0, 8.h),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pushNamedAndRemoveUntil(
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

  Widget _buildEmptyState(AppLocalizations l10n) {
    // ✅ 使用 Facebook 蓝
    const Color kUserPrimaryBlue = Color(0xFF1877F2);

    return SliverFillRemaining(
      child: Transform.scale(
        scale: 0.8,
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
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
                              kUserPrimaryBlue.withOpacity(0.2),
                              kUserPrimaryBlue.withOpacity(0.1),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(70.r),
                          border: Border.all(
                            color: kUserPrimaryBlue.withOpacity(0.3),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: kUserPrimaryBlue.withOpacity(0.2),
                              blurRadius: 24.r,
                              offset: Offset(0, 12.h),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.add_a_photo_rounded,
                          size: 70.r,
                          color: kUserPrimaryBlue,
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
                        padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 16.h),
                        decoration: BoxDecoration(
                          color: kUserPrimaryBlue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16.r),
                          border: Border.all(
                            color: kUserPrimaryBlue.withOpacity(0.2),
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(Icons.camera_alt_rounded,
                                    color: kUserPrimaryBlue, size: 20.r),
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
                                    color: kUserPrimaryBlue, size: 20.r),
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
                                    color: kUserPrimaryBlue, size: 20.r),
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
                            colors: [kUserPrimaryBlue, Color(0xFF1E88E5)],
                          ),
                          borderRadius: BorderRadius.circular(16.r),
                          boxShadow: [
                            BoxShadow(
                              color: kUserPrimaryBlue.withOpacity(0.4),
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
                          onPressed: () => Navigator.of(context).push(
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
        ),
      ),
    );
  }

  Widget _buildListingsContent(
      List<Map<String, dynamic>> myListings, AppLocalizations l10n) {
    const Color kUserPrimaryBlue = Color(0xFF1877F2);

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
    const Color kUserPrimaryBlue = Color(0xFF1877F2);

    final totalViews = myListings.fold<int>(0, (sum, item) => sum + 234); // Mock
    final totalLikes = myListings.fold<int>(0, (sum, item) => sum + 12);  // Mock

    return Container(
      margin: EdgeInsets.all(16.w),
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFF8F9FA)],
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
                    l10n.myListings,
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
                    colors: [kUserPrimaryBlue, Color(0xFF1E88E5)],
                  ),
                  borderRadius: BorderRadius.circular(12.r),
                  boxShadow: [
                    BoxShadow(
                      color: kUserPrimaryBlue.withOpacity(0.3),
                      blurRadius: 8.r,
                      offset: Offset(0, 4.h),
                    ),
                  ],
                ),
                child: GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SellFormPage()),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, size: 12.r, color: Colors.white),
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
                  kUserPrimaryBlue,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: _buildStatCard(
                  Icons.favorite_rounded,
                  totalLikes.toString(),
                  'Total Likes',
                  Colors.red.shade400,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: _buildStatCard(
                  Icons.trending_up_rounded,
                  '${(totalViews * 0.15).toInt()}',
                  'Engagement',
                  Colors.green.shade400,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(IconData icon, String value, String label, Color color) {
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
    const Color kUserPrimaryBlue = Color(0xFF1877F2);

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
                // 缩略图
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
                        errorBuilder: (context, error, stackTrace) => Icon(
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

                // 文本
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
                        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              kUserPrimaryBlue.withOpacity(0.15),
                              kUserPrimaryBlue.withOpacity(0.08),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(
                            color: kUserPrimaryBlue.withOpacity(0.2),
                          ),
                        ),
                        child: Text(
                          item['price'] ?? l10n.noPrice,
                          style: TextStyle(
                            color: kUserPrimaryBlue,
                            fontWeight: FontWeight.bold,
                            fontSize: 16.sp,
                          ),
                        ),
                      ),
                      SizedBox(height: 12.h),
                      Row(
                        children: [
                          _buildEnhancedStatItem(
                              Icons.visibility_rounded, '234', Colors.blue.shade400),
                          SizedBox(width: 16.w),
                          _buildEnhancedStatItem(
                              Icons.favorite_rounded, '12', Colors.red.shade400),
                          SizedBox(width: 16.w),
                          _buildEnhancedStatItem(
                              Icons.chat_bubble_rounded, '3', Colors.green.shade400),
                        ],
                      ),
                    ],
                  ),
                ),

                // 三点菜单
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
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
                colors: [Colors.red.shade400, Colors.red.shade600],
              ),
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
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _deleteListing(Map<String, dynamic> item, AppLocalizations l10n) async {
    try {
      final urls = (item['images'] as List?)?.cast<String>() ?? const <String>[];
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
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 20.r),
                SizedBox(width: 8.w),
                Text(l10n.listingDeleted),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
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
                Icon(Icons.error_outline_rounded, color: Colors.white, size: 20.r),
                SizedBox(width: 8.w),
                Expanded(child: Text('Delete failed: $e')),
              ],
            ),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
            margin: EdgeInsets.all(16.w),
          ),
        );
      }
    }
  }
}

// ---------------- Notification Page ----------------

/* ---------------- Notification Page (莽麓搂氓鈥♀€樏九矫ヅ掆€撁р€八喢ε撀? ---------------- */
class NotificationPage extends StatefulWidget {
  final VoidCallback? onClearBadge;
  final bool isGuest;
  final Function(int)? onNotificationCountChanged;

  const NotificationPage({
    super.key,
    this.onClearBadge,
    this.isGuest = false,
    this.onNotificationCountChanged,
  });

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;

  // ✅ 统一使用首页的 Facebook 蓝
  static const Color _PRIMARY_BLUE = Color(0xFF1877F2);

  // ✅ 新增：仅监听“全局通知流”，不在页面里直连 Supabase
  StreamSubscription<Map<String, dynamic>>? _notifSub;

  // ✅ A) 精简版蓝色头部（与 Sell 页一致：更短、更上移；标题与右上角按钮同一基线）
  Widget _blueHeader({
    required BuildContext context,
    required String title,
    required bool centerTitle,
    Widget? trailing, // 右上角按钮（可选）
  }) {
    final double statusBar = MediaQuery.of(context).padding.top;
    const double kHeaderVisual = 48.0; // 头部视觉高度（更短）
    const double kSide = 20.0;

    return SizedBox(
      height: statusBar + kHeaderVisual,
      child: Stack(
        children: [
          // 背景（渐变）
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1877F2), Color(0xFF1E88E5)],
                ),
              ),
            ),
          ),
          // 标题 + 右上角按钮：同一行、整体上移
          Positioned(
            left: kSide,
            right: 12.0,
            top: statusBar + 6.0,
            child: SizedBox(
              height: 36.0,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      textAlign: centerTitle ? TextAlign.center : TextAlign.left,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                  ),
                  if (trailing != null) trailing,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ B) 右上角菜单按钮：更小(28×28)并与标题对齐；弹出层更贴合
  Widget _buildMenuButton() {
    final l10n = AppLocalizations.of(context)!;
    final bool isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      offset: const Offset(0, 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10.w),
      ),
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
              Text(l10n.markAllAsRead, style: TextStyle(fontSize: 12.sp)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'clear_all',
          child: Row(
            children: [
              Icon(Icons.clear_all_rounded, color: Colors.red, size: 14.r),
              SizedBox(width: 8.w),
              Text(l10n.clearAll,
                  style: TextStyle(fontSize: 12.sp, color: Colors.red)),
            ],
          ),
        ),
      ],
      child: SizedBox(
        height: 28.w,
        width: 28.w,
        child: Material(
          color: Colors.white.withOpacity(0.18),
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: Center(
            child: Icon(
              isIOS ? Icons.more_horiz_rounded : Icons.more_vert_rounded,
              color: Colors.white,
              size: 18.w,
            ),
          ),
        ),
      ),
    );
  }

  // ⛔️ [_buildCustomHeader 已被删除，由 _blueHeader 替代]
  @override
  void initState() {
    super.initState();
    if (!widget.isGuest) {
      _loadNotifications(); // 首屏拉历史
      // ✅ 监听全局广播：任何新事件/更新都能及时进来（即使用户在别的页面）
      _notifSub = NotificationService.stream.listen((row) {
        if (!mounted) return;
        final id = (row['id'] ?? '').toString();
        final idx = _notifications.indexWhere(
              (n) => (n['id'] ?? '').toString() == id,
        );
        setState(() {
          if (idx >= 0) {
            _notifications[idx] = row; // 覆盖更新
          } else {
            _notifications.insert(0, row); // 新增顶插
          }
        });
        _updateUnreadCount();
      });
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
    _notifSub?.cancel(); // ✅ 只取消对“流”的监听，不动全局订阅
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

  // ⛔️ 页面级订阅/退订已删除，统一改为监听 NotificationService.stream
  // Future<void> _subscribeToNotifications() async { ... }
  // Future<void> _unsubscribeFromNotifications() async { ... }

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
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.r)),
            margin: EdgeInsets.all(8.w),
            duration: const Duration(seconds: 2),
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
          duration: const Duration(seconds: 2),
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
    final type = notification['type']?.toString() ?? '';
    String? listingId = notification['listing_id']?.toString();
    String? offerId = notification['offer_id']?.toString();
    final payload = notification['payload'] as Map<String, dynamic>? ?? {};
    if ((listingId == null || listingId.isEmpty) && payload.isNotEmpty) {
      listingId = payload['listing_id']?.toString();
    }
    if ((offerId == null || offerId.isEmpty) && payload.isNotEmpty) {
      offerId = payload['offer_id']?.toString();
    }
    final metadata = notification['metadata'] as Map<String, dynamic>? ?? {};
    if ((listingId == null || listingId.isEmpty) && metadata.isNotEmpty) {
      listingId = metadata['listing_id']?.toString();
    }
    if ((offerId == null || offerId.isEmpty) && metadata.isNotEmpty) {
      offerId = metadata['offer_id']?.toString();
    }
    final notificationId = notification['id']?.toString();
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
        body: Column(
          children: [
            _blueHeader(
              context: context,
              title: l10n.notifications,
              centerTitle: false,
              trailing: null,
            ),
            Expanded(
              child: Center(
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
                        gradient: const LinearGradient(
                          colors: [_PRIMARY_BLUE, Color(0xFF1E88E5)],
                        ),
                        borderRadius: BorderRadius.circular(10.r),
                        boxShadow: [
                          BoxShadow(
                            color: _PRIMARY_BLUE.withOpacity(0.3),
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
                          padding: EdgeInsets.symmetric(
                              horizontal: 20.w, vertical: 10.h),
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
            ),
          ],
        ),
      );
    }

    final unreadCount =
        _notifications.where((n) => n['is_read'] != true).length;
    final displayTitle =
        '${l10n.notifications}${unreadCount > 0 ? ' ($unreadCount)' : ''}';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: Column(
        children: [
          _blueHeader(
            context: context,
            title: displayTitle,
            centerTitle: false,
            trailing: _notifications.isNotEmpty ? _buildMenuButton() : null,
          ),
          Expanded(
            child: _isLoading
                ? Center(
              child: Container(
                padding: EdgeInsets.all(24.w),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16.r),
                  boxShadow: [
                    BoxShadow(
                      color: _PRIMARY_BLUE.withOpacity(0.08),
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
                            _PRIMARY_BLUE.withOpacity(0.2),
                            _PRIMARY_BLUE.withOpacity(0.1),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20.r),
                      ),
                      child: Center(
                        child: SizedBox(
                          width: 20.w,
                          height: 20.w,
                          child: const CircularProgressIndicator(
                            valueColor:
                            AlwaysStoppedAnimation<Color>(
                                _PRIMARY_BLUE),
                            strokeWidth: 2.5,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 12.h),
                    Text(
                      'Loading notifications...',
                      style: TextStyle(
                        color: _PRIMARY_BLUE,
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
                          _PRIMARY_BLUE.withOpacity(0.1),
                          const Color(0xFF1E88E5).withOpacity(0.05),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(30.r),
                      border: Border.all(
                        color:
                        _PRIMARY_BLUE.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      Icons.notifications_none_rounded,
                      size: 30.r,
                      color: _PRIMARY_BLUE,
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
              color: _PRIMARY_BLUE,
              backgroundColor: Colors.white,
              strokeWidth: 2.w,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                // ✅ 统一更紧凑的顶部间距：12
                padding: EdgeInsets.only(top: 12.h),
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
                    onDismissed: (direction) =>
                        _deleteNotification(index),
                    child: Container(
                      color: isRead
                          ? Colors.white
                          : _PRIMARY_BLUE.withOpacity(0.03),
                      margin: EdgeInsets.only(bottom: 0.5.h),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () =>
                              _handleNotificationTap(notification),
                          splashColor:
                          _PRIMARY_BLUE.withOpacity(0.1),
                          highlightColor:
                          _PRIMARY_BLUE.withOpacity(0.05),
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 12.w,
                              vertical: 8.h,
                            ),
                            child: Row(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
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
                                              overflow: TextOverflow
                                                  .ellipsis,
                                            ),
                                          ),
                                          if (!isRead)
                                            Container(
                                              width: 6.w,
                                              height: 6.w,
                                              margin:
                                              EdgeInsets.only(
                                                  left: 6.w),
                                              decoration:
                                              const BoxDecoration(
                                                color:
                                                _PRIMARY_BLUE,
                                                shape:
                                                BoxShape.circle,
                                              ),
                                            ),
                                        ],
                                      ),
                                      SizedBox(height: 2.h),
                                      Text(
                                        '${notification['message'] ?? ''}',
                                        style: TextStyle(
                                          fontSize: 11.sp,
                                          color:
                                          Colors.grey.shade600,
                                          height: 1.4,
                                        ),
                                        maxLines: 2,
                                        overflow:
                                        TextOverflow.ellipsis,
                                      ),
                                      SizedBox(height: 4.h),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.access_time_rounded,
                                            size: 10.r,
                                            color: Colors
                                                .grey.shade400,
                                          ),
                                          SizedBox(width: 2.w),
                                          Text(
                                            NotificationService
                                                .formatNotificationTime(
                                                createdAt),
                                            style: TextStyle(
                                              fontSize: 10.sp,
                                              color: Colors
                                                  .grey.shade400,
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
          ),
        ],
      ),
    );
  }
}

class NoGlowScrollBehavior extends ScrollBehavior {
  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}

const _kPrivacyUrl = 'https://www.swaply.cc/privacy';
const _kDeleteUrl = 'https://www.swaply.cc/delete-account';



//---------------- Profile Page 个人资料页 ----------------
class ProfilePage extends StatefulWidget {
  final bool isGuest;
  const ProfilePage({super.key, this.isGuest = false});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
  bool _loading = true;

  /// 基础资料（用于显示：名/头像/时间等）
  Map<String, dynamic>? _profile;

  /// 仅读 profiles 行（包含 verification_type 等）
  Map<String, dynamic>? _profileRow;

  final _svc = ProfileService();

  // ✅ 认证服务与状态（取 user_verifications）
  final _verifySvc = EmailVerificationService();
  bool _verified = false;
  vt.VerificationBadgeType _badge = vt.VerificationBadgeType.none;
  Map<String, dynamic>? _verificationRow;
  bool _verifyLoading = false;

  bool _uploadingAvatar = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // ✅ 稳定性：保存订阅句柄 & 并发保护
  StreamSubscription<AuthState>? _authSub;
  bool _verifyBusy = false;

  // ===== [PATCH A: Verification Refresh Hook] =====
  StreamSubscription<bool>? _verifSub;
  bool _verifHookInited = false;

  /// ✅ 显示用名字：
  /// 1) profiles.full_name
  /// 2) auth.users.user_metadata.full_name / name
  /// 3) auth.users.email
  /// 4) 兜底 "User"
  String get _displayName {
    final supa = Supabase.instance.client;
    final user = supa.auth.currentUser;

    final fromProfile = (_profile?['full_name'] ?? '').toString().trim();

    final meta = user?.userMetadata ?? {};
    final fromMeta =
    (meta['full_name'] ?? meta['name'] ?? '').toString().trim();

    final email = (user?.email ?? '').trim();

    if (fromProfile.isNotEmpty) return fromProfile;
    if (fromMeta.isNotEmpty) return fromMeta;
    if (email.isNotEmpty) return email;
    return 'User';
  }

  /// ✅ 显示用联系方式：
  /// 1) profiles.phone
  /// 2) auth.users.user_metadata.phone / phone_number
  /// 3) auth.users.email
  /// 4) 兜底空字符串
  String get _displayContact {
    final supa = Supabase.instance.client;
    final user = supa.auth.currentUser;

    final phoneProfile = (_profile?['phone'] ?? '').toString().trim();

    final meta = user?.userMetadata ?? {};
    final phoneMeta =
    (meta['phone'] ?? meta['phone_number'] ?? '').toString().trim();

    final email = (user?.email ?? '').trim();

    if (phoneProfile.isNotEmpty) return phoneProfile;
    if (phoneMeta.isNotEmpty) return phoneMeta;
    if (email.isNotEmpty) return email;
    return '';
  }

  @override
  void initState() {
    super.initState();
    _animationController =
        AnimationController(duration: const Duration(milliseconds: 800), vsync: this);
    _fadeAnimation =
        CurvedAnimation(parent: _animationController, curve: Curves.easeInOut);

    if (!widget.isGuest) {
      _load();
    } else {
      _animationController.forward();
    }

    // ✅ 保存订阅，dispose 时取消
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      if (mounted) _reloadUserVerificationStatus();
    });

    // ===== [PATCH A] 首次进入先拉一次当前认证状态 =====
    _reloadUserVerificationStatus();

    // ===== [PATCH A] 只初始化一次订阅（避免热重载重复）=====
    if (!_verifHookInited) {
      _verifHookInited = true;
      _verifSub = VerificationGuard.stream.listen((ok) async {
        if (!mounted) return;
        // 任何页面完成认证，这里立刻重拉
        await _reloadUserVerificationStatus();
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _authSub?.cancel(); // ✅ 取消订阅
    _verifSub?.cancel(); // ===== [PATCH A] 取消认证刷新订阅 =====
    _animationController.dispose();
    super.dispose();
  }

  /// 仅读基础资料（显示用）
  Future<void> _load() async {
    try {
      final base = await _svc.getUserProfile();
      final map =
      base == null ? <String, dynamic>{} : Map<String, dynamic>.from(base);

      if (!mounted) return;
      setState(() {
        _profile = map;
        _profileRow = map;
        _loading = false;
      });
      _animationController.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _animationController.forward();
    }
  }

  // ✅ 仅读 user_verifications，一次性计算 _verified/_badge，并更新状态
  Future<void> _reloadUserVerificationStatus() async {
    if (!mounted || _verifyBusy) return; // 并发 & 生命周期保护
    _verifyBusy = true;
    setState(() => _verifyLoading = true);

    try {
      // ✅ 一定用 getUser() 获取“最新用户”
      final auth = Supabase.instance.client.auth;
      final userResp = await auth.getUser();
      final user = userResp.user;

      final row = await _verifySvc.fetchVerificationRow(); // user_verifications

      final verified = vutils.computeIsVerified(verificationRow: row, user: user);
      final badge = vutils.computeBadgeType(verificationRow: row, user: user);

      if (!mounted) return;
      setState(() {
        _verificationRow = row;
        _verified = verified;
        _badge = badge;
        _verifyLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _verifyLoading = false);
    } finally {
      _verifyBusy = false;
    }
  }

  Future<void> _editNamePhone() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    try {
      final p = await ProfileService.instance.getUserProfile();
      if (p != null) {
        nameCtrl.text =
            (p['display_name'] ?? p['full_name'] ?? '').toString();
        phoneCtrl.text = (p['phone'] ?? '').toString();
      }
    } catch (_) {}

    if (!mounted) {
      nameCtrl.dispose();
      phoneCtrl.dispose();
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 8,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white, Colors.grey.shade50],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.edit_rounded,
                          color: Theme.of(context).primaryColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Text('Edit Profile',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(fontSize: 16),
                  decoration: InputDecoration(
                    labelText: 'Full name',
                    labelStyle: const TextStyle(fontSize: 14),
                    prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                      BorderSide(color: Theme.of(context).primaryColor, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(fontSize: 16),
                  decoration: InputDecoration(
                    labelText: 'Phone',
                    labelStyle: const TextStyle(fontSize: 14),
                    prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                      BorderSide(color: Theme.of(context).primaryColor, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogCtx).maybePop(false),
                      style: TextButton.styleFrom(
                          padding:
                          const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                      child: const Text('Cancel', style: TextStyle(fontSize: 15)),
                    ),
                    const SizedBox(width: 12),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFF2196F3), Color(0xFF1E88E5)]),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(dialogCtx).maybePop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding:
                          const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Save',
                            style: TextStyle(fontSize: 15, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (result == true && mounted) {
      try {
        await ProfileService.instance.updateUserProfile(
          fullName: nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
          phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Profile updated successfully', style: TextStyle(fontSize: 14)),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ),
        );
        await _load();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                    child:
                    Text('Upload failed: $e', style: const TextStyle(fontSize: 14))),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }

    nameCtrl.dispose();
    phoneCtrl.dispose();
  }

  // -----------------------------------------------------
  // 上传头像：并发保护 + 缓存破坏参数
  // -----------------------------------------------------
  Future<void> _uploadAvatarSimple() async {
    if (!mounted) return;
    setState(() => _uploadingAvatar = true);

    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );
      if (image == null) return;

      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final bytes = await File(image.path).readAsBytes();
      final ext = image.path.split('.').last;
      final path = '${user.id}/avatar_${DateTime.now().millisecondsSinceEpoch}.$ext';

      if (!mounted) return;

      await Supabase.instance.client.storage
          .from('avatars')
          .uploadBinary(path, bytes, fileOptions: const FileOptions(upsert: true));

      final baseUrl =
      Supabase.instance.client.storage.from('avatars').getPublicUrl(path);
      final cacheBust = DateTime.now().millisecondsSinceEpoch;
      final publicUrlWithCacheBust = '$baseUrl?v=$cacheBust';

      await ProfileService.instance.updateUserProfile(avatarUrl: publicUrlWithCacheBust);

      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('Avatar updated successfully', style: TextStyle(fontSize: 14)),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text('Upload failed: $e', style: const TextStyle(fontSize: 14))),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  // -----------------------------------------------------
  // Header：自适应高度 + 内部 padding；恢复“Member since …”显示
  // -----------------------------------------------------
  Widget _buildHeaderClassic({
    required bool isGuest,
    required String name,
    required String email,
    String? avatarUrl,
    String? memberSince,
    vt.VerificationBadgeType verificationType = vt.VerificationBadgeType.none,
  }) {
    final double statusBar = MediaQuery.of(context).padding.top;

    return Container(
      // 渐变背景（与你之前的风格一致）
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2563EB), Color(0xFF3B82F6), Color(0xFF60A5FA)],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: Padding(
        // 内消化状态栏高度，整体不被拉高
        padding: EdgeInsets.fromLTRB(24, (statusBar > 0 ? statusBar + 12 : 20), 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Hero(
              tag: 'profile_avatar',
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [
                    Colors.white.withOpacity(0.9),
                    Colors.white.withOpacity(0.3),
                  ]),
                  boxShadow: const [
                    BoxShadow(
                      color: Color.fromRGBO(0, 0, 0, 0.2),
                      blurRadius: 16,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: VerifiedAvatar(
                  avatarUrl: avatarUrl,
                  radius: 42, // 保持你原来偏紧凑的头像尺寸
                  verificationType: verificationType,
                  onTap: !isGuest ? _uploadAvatarSimple : null,
                  defaultIcon: isGuest ? Icons.person_outline : Icons.person,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20.0,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                shadows: [
                  Shadow(offset: Offset(0, 2), blurRadius: 4, color: Color(0x40000000)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.20),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.30), width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(email.contains('@') ? Icons.email : Icons.phone,
                      size: 14, color: Colors.white.withOpacity(0.95)),
                  const SizedBox(width: 6),
                  Text(email,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.95),
                          fontSize: 13.0,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            if (!isGuest && memberSince != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 12, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      memberSince,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // Guest user interface
    if (widget.isGuest) {
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.0)),
        child: Scaffold(
          backgroundColor: const Color(0xFFF8F9FA),
          body: ScrollConfiguration(
            behavior: const ScrollBehavior(),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _buildHeaderClassic(
                    isGuest: true,
                    name: l10n.guestUser,
                    email: l10n.browseWithoutAccount,
                    avatarUrl: null,
                  ),
                ),
                SliverToBoxAdapter(
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: const Padding(
                      padding: EdgeInsets.all(20),
                      child: _GuestSimpleOptions(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Loading state
    if (_loading) {
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.0)),
        child: const Scaffold(
          backgroundColor: Color(0xFFF8F9FA),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(width: 36, height: 36, child: CircularProgressIndicator(strokeWidth: 3)),
                SizedBox(height: 16),
                Text('Loading profile...', style: TextStyle(color: Color(0xFF666666), fontSize: 15)),
              ],
            ),
          ),
        ),
      );
    }

    final fullName = _displayName;
    final displayContact = _displayContact;
    final avatarUrl = (_profile?['avatar_url'] ?? '') as String?;
    final memberSince = _profile?['created_at']?.toString();
    String? memberSinceText;
    if (memberSince != null && memberSince.isNotEmpty) {
      final cut = memberSince.length >= 10 ? memberSince.substring(0, 10) : memberSince;
      memberSinceText = 'Member since $cut';
    }

    // Normal User interface
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.0)),
      child: Scaffold(
        extendBody: true,
        backgroundColor: const Color(0xFFF8F9FA),
        body: Stack(
          children: [
            ScrollConfiguration(
              behavior: const ScrollBehavior(),
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: _buildHeaderClassic(
                      isGuest: false,
                      name: fullName,
                      email: displayContact,
                      avatarUrl: (avatarUrl != null && avatarUrl.isNotEmpty) ? avatarUrl : null,
                      memberSince: memberSinceText,
                      verificationType: _verified ? _badge : vt.VerificationBadgeType.none,
                    ),
                  ),

                  // 内容区域
                  SliverToBoxAdapter(
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Profile',
                                style: TextStyle(
                                    fontSize: 16.0,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF6B7280),
                                    letterSpacing: 0.5)),
                            const SizedBox(height: 10),
                            _ProfileOptionEnhanced(
                              icon: Icons.edit_rounded,
                              title: 'Edit Profile',
                              color: Colors.blue,
                              onTap: _editNamePhone,
                            ),
                            const SizedBox(height: 12),
                            _VerificationTileCard(
                              isVerified: _verified,
                              isLoading: _verifyLoading,
                              onTap: () async {
                                await Navigator.of(context).push<bool>(
                                  MaterialPageRoute(builder: (_) => const VerificationPage()),
                                );
                                await _reloadUserVerificationStatus();
                              },
                            ),

                            const SizedBox(height: 10),
                            const Text('Rewards & Activities',
                                style: TextStyle(
                                    fontSize: 16.0,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF6B7280),
                                    letterSpacing: 0.5)),
                            const SizedBox(height: 10),

                            _RewardsTileUnified(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const TaskManagementPage()),
                                );
                              },
                            ),
                            const SizedBox(height: 12),

                            _ProfileOptionEnhanced(
                              icon: Icons.inventory_2_rounded,
                              title: l10n.myListings,
                              color: Colors.indigo,
                              onTap: () => Navigator.push(
                                  context, MaterialPageRoute(builder: (_) => const MyListingsPage())),
                            ),
                            const SizedBox(height: 12),

                            _ProfileOptionEnhanced(
                              icon: Icons.favorite_rounded,
                              title: l10n.wishlist,
                              color: Colors.pink,
                              onTap: () {
                                final user = Supabase.instance.client.auth.currentUser;
                                if (user == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Please sign in to view Wishlist')),
                                  );
                                  return;
                                }
                                Navigator.push(
                                    context, MaterialPageRoute(builder: (_) => const WishlistPage()));
                              },
                            ),
                            const SizedBox(height: 12),

                            _ProfileOptionEnhanced(
                              icon: Icons.person_add_alt_1_rounded,
                              title: 'Invite Friends',
                              subtitle: 'Earn coupons by inviting friends',
                              color: Colors.orange,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const InviteFriendsPage()),
                              ),
                            ),
                            const SizedBox(height: 12),

                            _ProfileOptionEnhanced(
                              icon: Icons.local_activity_rounded,
                              title: 'My Coupons',
                              subtitle: 'View and manage your coupons',
                              color: Colors.purple,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const CouponManagementPage()),
                              ),
                            ),

                            const SizedBox(height: 10),
                            const Text('Support',
                                style: TextStyle(
                                    fontSize: 16.0,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF6B7280),
                                    letterSpacing: 0.5)),
                            const SizedBox(height: 10),

                            _ProfileOptionEnhanced(
                              icon: Icons.manage_accounts,
                              title: 'Account',
                              subtitle: 'Password, devices, delete',
                              color: Colors.cyan,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const AccountSettingsPage() ),
                              ),
                            ),
                            const SizedBox(height: 12),

                            _ProfileOptionEnhanced(
                              icon: Icons.privacy_tip_outlined,
                              title: 'Privacy Policy',
                              color: Colors.blueGrey,
                              onTap: () => launchUrl(Uri.parse(_kPrivacyUrl)),
                            ),
                            const SizedBox(height: 12),

                            _ProfileOptionEnhanced(
                              icon: Icons.delete_outline,
                              title: 'Data Deletion / How to delete my account',
                              color: Colors.deepOrange,
                              onTap: () => launchUrl(Uri.parse(_kDeleteUrl)),
                            ),
                            const SizedBox(height: 12),

                            _ProfileOptionEnhanced(
                              icon: Icons.help_outline_rounded,
                              title: l10n.helpSupport,
                              color: Colors.teal,
                              onTap: () => Navigator.push(
                                  context, MaterialPageRoute(builder: (_) => const HelpSupportPage())),
                            ),
                            const SizedBox(height: 12),

                            _ProfileOptionEnhanced(
                              icon: Icons.info_outline_rounded,
                              title: l10n.about,
                              color: Colors.blueGrey,
                              onTap: () =>
                                  Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutPage())),
                            ),
                            const SizedBox(height: 18),

                            _ProfileOptionEnhanced(
                              icon: Icons.logout_rounded,
                              title: l10n.logout,
                              color: Colors.red,
                              onTap: () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18)),
                                    title: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                              color: Colors.red.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(8)),
                                          child: const Icon(Icons.logout_rounded,
                                              color: Colors.red, size: 20),
                                        ),
                                        const SizedBox(width: 12),
                                        const Text('Logout',
                                            style: TextStyle(
                                                fontSize: 18, fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                    content: const Text('Are you sure you want to logout?',
                                        style: TextStyle(fontSize: 15, height: 1.4)),
                                    actions: [
                                      TextButton(
                                          onPressed: () => Navigator.of(ctx).pop(false),
                                          child: Text('Cancel',
                                              style: TextStyle(fontSize: 15, color: Colors.grey[600]))),
                                      Container(
                                        decoration: BoxDecoration(
                                            color: Colors.red,
                                            borderRadius: BorderRadius.circular(8)),
                                        child: TextButton(
                                          onPressed: () => Navigator.of(ctx).pop(true),
                                          child: const Text('Logout',
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w600)),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed == true) {
                                  try {
                                    await Supabase.instance.client.auth.signOut();
                                    RewardService.clearCache();
                                    // ✅ 同步清理认证缓存并重置本页状态
                                    VerificationGuard.invalidateCache();
                                    if (mounted) {
                                      setState(() {
                                        _verified = false;
                                        _badge = vt.VerificationBadgeType.none;
                                      });
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Row(
                                            children: [
                                              const Icon(Icons.error_outline_rounded,
                                                  color: Colors.white, size: 18),
                                              const SizedBox(width: 8),
                                              Text('Logout failed: $e',
                                                  style: const TextStyle(fontSize: 14)),
                                            ],
                                          ),
                                          backgroundColor: Colors.red,
                                          behavior: SnackBarBehavior.floating,
                                          shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(10)),
                                          margin: const EdgeInsets.all(16),
                                        ),
                                      );
                                    }
                                  }
                                }
                              },
                            ),
                            const SizedBox(height: 40),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 上传中遮罩
            if (_uploadingAvatar)
              Positioned.fill(
                child: Container(
                  color: Colors.black54,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                          color: Colors.white, borderRadius: BorderRadius.circular(16)),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(width: 36, height: 36, child: CircularProgressIndicator()),
                          SizedBox(height: 16),
                          Text('Uploading avatar...',
                              style: TextStyle(color: Color(0xFF616161), fontSize: 15)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/* ---------------- Verification Tile（iOS 紧凑版；Android 原样） ---------------- */
class _VerificationTileCard extends StatelessWidget {
  final bool isVerified;
  final bool isLoading;
  final VoidCallback? onTap;

  const _VerificationTileCard({
    required this.isVerified,
    required this.isLoading,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color badgeColor = isVerified ? Colors.green : Colors.grey;
    final bool isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    final double vPad = isIOS ? 12 : 16;      // 垂直更紧凑
    final double iconSize = isIOS ? 22 : 26;  // 图标略小
    final double radius = isIOS ? 14 : 16;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: vPad),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(radius),
            boxShadow: const [
              BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.04), blurRadius: 12, offset: Offset(0, 2)),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(isIOS ? 10 : 12),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(isIOS ? 12 : 14),
                ),
                child: Icon(Icons.verified, color: badgeColor, size: iconSize),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isVerified ? 'Verified' : 'Verification',
                        style: const TextStyle(fontSize: 16.0, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text(isVerified ? 'Status: Verified' : 'Status: Not verified',
                        style: TextStyle(fontSize: 13.0, color: Colors.grey[600])),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              isLoading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(Icons.arrow_forward_ios, size: 18, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------------- 通用列表项（iOS 紧凑版；Android 原样） ---------------- */
class _ProfileOptionEnhanced extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color color;
  final VoidCallback? onTap;

  const _ProfileOptionEnhanced({
    required this.icon,
    required this.title,
    required this.color,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    final double vPad = isIOS ? 12 : 16;
    final double iconSize = isIOS ? 22 : 26;
    final double radius = isIOS ? 14 : 16;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: vPad),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(radius),
            boxShadow: const [
              BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.04), blurRadius: 12, offset: Offset(0, 2))
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(isIOS ? 10 : 12),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(isIOS ? 12 : 14)),
                child: Icon(icon, color: color, size: iconSize),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style:
                        const TextStyle(fontSize: 16.0, fontWeight: FontWeight.w600)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(subtitle!,
                          style: TextStyle(fontSize: 13.0, color: Colors.grey[600])),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.arrow_forward_ios, size: 18, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------------- My Rewards（iOS 紧凑版；Android 原样） ---------------- */
class _RewardsTileUnified extends StatelessWidget {
  final VoidCallback? onTap;
  const _RewardsTileUnified({this.onTap});

  @override
  Widget build(BuildContext context) {
    final bool isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    final double vPad = isIOS ? 12 : 16;
    final double iconSize = isIOS ? 22 : 26;
    final double radius = isIOS ? 14 : 16;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: vPad),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(radius),
            boxShadow: const [
              BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.04), blurRadius: 12, offset: Offset(0, 2)),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(isIOS ? 10 : 12),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(isIOS ? 12 : 14),
                ),
                child: Icon(Icons.emoji_events_rounded,
                    color: Colors.deepPurple, size: iconSize),
              ),
              const SizedBox(width: 18),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('My Rewards',
                        style:
                        TextStyle(fontSize: 16.0, fontWeight: FontWeight.w600)),
                    SizedBox(height: 3),
                    Text('Points: 0 · Coupons: 1',
                        style: TextStyle(fontSize: 13.0, color: Color(0xFF6B7280))),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.arrow_forward_ios, size: 18, color: Color(0xFFBDBDBD)),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------------- Guest 选项（简版） ---------------- */
class _GuestSimpleOptions extends StatelessWidget {
  const _GuestSimpleOptions();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        _ProfileOptionEnhanced(
          icon: Icons.help_outline_rounded,
          title: l10n.helpSupport,
          color: Colors.blue,
          onTap: () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpSupportPage())),
        ),
        const SizedBox(height: 14),
        _ProfileOptionEnhanced(
          icon: Icons.info_outline_rounded,
          title: l10n.about,
          color: Colors.indigo,
          onTap: () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutPage())),
        ),
      ],
    );
  }
}

/* ---------------- Help & Support Page ---------------- */
class HelpSupportPage extends StatelessWidget {
  const HelpSupportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      // ✅ [MODIFIED] 替换 AppBar
      appBar: _buildStandardAppBar(context, l10n.helpSupport),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF60A5FA), Color(0xFF3B82F6)]),
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                      color: Color.fromRGBO(37, 99, 235, 0.3),
                      blurRadius: 24,
                      offset: Offset(0, 12))
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Need Help?',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Text('Our support team is here to help you 24/7',
                      style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 15)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('Contact Information',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: Colors.grey[800])),
            const SizedBox(height: 14),
            _buildContactCard(
              icon: Icons.email_outlined,
              title: 'Email Support',
              subtitle: 'swaply@swaply.cc',
              color: Colors.blue,
              onTap: () => launchUrl(Uri(scheme: 'mailto', path: 'swaply@swaply.cc')),
            ),
            const SizedBox(height: 12),
            _buildContactCard(
              icon: Icons.language,
              title: 'Website',
              subtitle: 'www.swaply.cc',
              color: Colors.green,
              onTap: () => launchUrl(Uri.parse('https://www.swaply.cc')),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ [MODIFIED] 统一的 AppBar 构建器 (已按 verification_page.dart 标准重写)
  PreferredSizeWidget _buildStandardAppBar(BuildContext context, String title) {
    final double statusBar = MediaQuery.of(context).padding.top;
    // 使用 Theme.of(context).platform 因为它不需要 'foundation.dart'
    final bool isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    const Color kBgColor = Color(0xFF2563EB); // 此页面的背景色

    // ============== Android & 其他：保持原 AppBar 不变 ==============
    if (!isIOS) {
      return AppBar(
        title: Text(title, style: const TextStyle(color: Colors.white)),
        backgroundColor: kBgColor,
        elevation: 0,
      );
    }

    // ===== ✅ [MODIFIED] iOS：使用“基准页” (verification_page.dart) 的 44pt Row 布局 =====

    // 1. 标准布局数值
    const double kNavBarHeight = 44.0; // 标准导航条高度
    const double kButtonSize = 32.0; // 标准按钮尺寸
    const double kSidePadding = 16.0; // 标准左右内边距
    const double kButtonSpacing = 12.0; // 标准间距

    // 2. 构建 32x32 返回按钮
    final Widget iosBackButton = SizedBox(
      width: kButtonSize,
      height: kButtonSize,
      child: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10), // 保持原圆角
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.arrow_back_ios_new, // 保持原图标
              size: 18,
              color: Colors.white),
        ),
      ),
    );

    // 3. 构建居中标题
    final Widget iosTitle = Expanded(
      child: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center, // 保证居中
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 18, // 保持原字体大小
        ),
      ),
    );

    // 4. 构建 32x32 右侧占位
    const Widget iosRightPlaceholder =
    SizedBox(width: kButtonSize, height: kButtonSize);

    // 5. 组装
    return PreferredSize(
      preferredSize: Size.fromHeight(statusBar + kNavBarHeight), // ✅ 44pt + statusBar
      child: Container(
        color: kBgColor,
        padding: EdgeInsets.only(top: statusBar), // 让出状态栏
        child: SizedBox(
          height: kNavBarHeight, // 44pt
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: kSidePadding), // 16
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center, // 垂直居中
              children: [
                iosBackButton, // 32x32
                const SizedBox(width: kButtonSpacing), // 12
                iosTitle, // Expanded
                const SizedBox(width: kButtonSpacing), // 12
                iosRightPlaceholder, // 32x32 占位
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContactCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.04), blurRadius: 10, offset: Offset(0, 2))
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[800])),
                  const SizedBox(height: 3),
                  Text(subtitle, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                ]),
              ),
              if (onTap != null)
                Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------------- About Page ---------------- */
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      // ✅ [MODIFIED] 替换 AppBar
      appBar: _buildStandardAppBar(context, 'About'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.05), blurRadius: 12, offset: Offset(0, 4))
                ],
              ),
              child: const Column(
                children: [
                  Text('Trade What You Have\nFor What You Need',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2F2F2F),
                          height: 1.3)),
                  SizedBox(height: 14),
                  Text(
                    'Swaply is your community marketplace for trading items you no longer need for things you actually want.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: Color(0xFF6B7280), height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.05), blurRadius: 12, offset: Offset(0, 4))
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.copyright_rounded, size: 18, color: Colors.grey[600]),
                  const SizedBox(width: 5),
                  Text('2024 Swaply. All rights reserved.',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ [MODIFIED] 统一的 AppBar 构建器 (已按 verification_page.dart 标准重写)
  PreferredSizeWidget _buildStandardAppBar(BuildContext context, String title) {
    final double statusBar = MediaQuery.of(context).padding.top;
    // 使用 Theme.of(context).platform 因为它不需要 'foundation.dart'
    final bool isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    const Color kBgColor = Color(0xFF2563EB); // 此页面的背景色

    // ============== Android & 其他：保持原 AppBar 不变 ==============
    if (!isIOS) {
      return AppBar(
        title: Text(title, style: const TextStyle(color: Colors.white)),
        backgroundColor: kBgColor,
        elevation: 0,
      );
    }

    // ===== ✅ [MODIFIED] iOS：使用“基准页” (verification_page.dart) 的 44pt Row 布局 =====

    // 1. 标准布局数值
    const double kNavBarHeight = 44.0; // 标准导航条高度
    const double kButtonSize = 32.0; // 标准按钮尺寸
    const double kSidePadding = 16.0; // 标准左右内边距
    const double kButtonSpacing = 12.0; // 标准间距

    // 2. 构建 32x32 返回按钮
    final Widget iosBackButton = SizedBox(
      width: kButtonSize,
      height: kButtonSize,
      child: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10), // 保持原圆角
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.arrow_back_ios_new, // 保持原图标
              size: 18,
              color: Colors.white),
        ),
      ),
    );

    // 3. 构建居中标题
    final Widget iosTitle = Expanded(
      child: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center, // 保证居中
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 18, // 保持原字体大小
        ),
      ),
    );

    // 4. 构建 32x32 右侧占位
    const Widget iosRightPlaceholder =
    SizedBox(width: kButtonSize, height: kButtonSize);

    // 5. 组装
    return PreferredSize(
      preferredSize: Size.fromHeight(statusBar + kNavBarHeight), // ✅ 44pt + statusBar
      child: Container(
        color: kBgColor,
        padding: EdgeInsets.only(top: statusBar), // 让出状态栏
        child: SizedBox(
          height: kNavBarHeight, // 44pt
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: kSidePadding), // 16
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center, // 垂直居中
              children: [
                iosBackButton, // 32x32
                const SizedBox(width: kButtonSpacing), // 12
                iosTitle, // Expanded
                const SizedBox(width: kButtonSpacing), // 12
                iosRightPlaceholder, // 32x32 占位
              ],
            ),
          ),
        ),
      ),
    );
  }
}
/// 登录态变更监听：用户 signedIn 时，确保 profiles 里有一行
/// 只做一件事：如果 profiles 里没有该用户，就 upsert 一行
Future<void> _ensureProfileExists(User user) async {
  final supabase = Supabase.instance.client;

  try {
    // 查是否已存在
    final existing = await supabase
        .from('profiles')
        .select('id')
        .eq('id', user.id)
        .maybeSingle();

    if (existing != null) return; // 已有，无需处理

    // 尽量从 OAuth / 注册 metadata 里取到名字、头像和电话
    final meta      = user.userMetadata ?? {};
    final fullName  = (meta['full_name'] ?? meta['name'] ?? user.email ?? 'New User').toString();
    final avatarUrl = (meta['avatar_url'] ?? meta['picture'])?.toString();
    final phone     = (meta['phone'] ?? meta['phone_number'] ?? '').toString(); // ✅ 新增

    // 用 upsert 防止重复/并发 (等价于 INSERT ... ON CONFLICT(id) DO UPDATE)
    await supabase.from('profiles').upsert(
      {
        'id':        user.id,      // 与 auth.users.id 一致
        'email':     user.email,
        'full_name': fullName,
        if (avatarUrl != null && avatarUrl.isNotEmpty) 'avatar_url': avatarUrl,
        if (phone.isNotEmpty) 'phone': phone, // ✅ 新增：把 phone 写进 profiles
      },
      onConflict: 'id',
      ignoreDuplicates: true,
    );
  } catch (e, st) {
    dev.log('ensureProfile error: $e', stackTrace: st);
    // 不抛出错误，避免影响正常 UI
  }
}
