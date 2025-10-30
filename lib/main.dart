// lib/main.dart - 修复版本：移除导致自动登出的refreshSession调用 + 启用 PKCE OAuth
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// ====== 本项目内的依赖 ======
import 'package:swaply/auth/login_screen.dart';
import 'package:swaply/auth/welcome_screen.dart';
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
import 'package:swaply/utils/verification_utils.dart' as vutils;
import 'package:swaply/widgets/my_rewards_tile.dart';
import 'package:swaply/widgets/verified_avatar.dart';
import 'package:swaply/widgets/verification_badge.dart' as vb;
import 'package:swaply/widgets/verification_badge_mini.dart';
import 'startup_screen.dart';

// ========= 全局 Auth 事件订阅（只注册一次）=========
bool _authHookWired = false;
StreamSubscription<AuthState>? _globalAuthSub;
final GlobalKey<NavigatorState> appNavKey = GlobalKey<NavigatorState>();

class AppLocalizations {
  final Locale locale;
  AppLocalizations(this.locale);

  static AppLocalizations? of(BuildContext context) {
    return AppLocalizations(const Locale('en'));
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  // ---------- Generic / Auth ----------
  String get appTitle => 'Swaply';
  String get loginRequired => 'Login required';
  String loginRequiredMessage(String feature) => 'Please login to use $feature.';
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
  String get loginToSaveFavorites => 'Login to save your favorite items and searches.';
  String get loginNow => 'Login now';
  String get ads => 'Ads';
  String get searches => 'Searches';
  String get noFavoriteAdsYet => 'No favorite ads yet';
  String get favoritesHelp => 'Tap the bookmark icon on a listing to add it to Favorites.';
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
  String get notificationsWillAppearHere => 'Your notifications will appear here.';
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

  // ---------- Variants / Typos you might have ----------
  String get saveItems => 'Save items';
  String get saveltems => 'Save items'; // l/I 拼写错误

  @override
  dynamic noSuchMethod(Invocation invocation) => '';
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
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

// ========= 全局 Auth 处理（带欢迎弹窗：一次性） =========
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
        await NotificationService.subscribeUser(u.id);

        // ✅ 新逻辑：由服务端幂等 RPC 决定是否需要弹一次欢迎券
        try {
          final res = await RewardService.ensureWelcomeForCurrentUser();
          if (res.shouldPopup) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('new_user_welcome_pending_${u.id}', true);
          }
        } catch (e) {
          debugPrint('[Auth] ensureWelcomeForCurrentUser error: $e');
        }

        final ctx = appNavKey.currentContext;
        if (ctx != null) {
          // 导航到主页
          Navigator.of(ctx).pushNamedAndRemoveUntil('/home', (route) => false);
          // ✅ 不在这里直接弹窗，让主页面统一检查 SharedPreferences 决定是否弹
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
        Navigator.of(ctx).pushNamedAndRemoveUntil(
          '/welcome',
              (route) => false,
        );
      }
    }
  });
}

// —— 仅供本文件使用的 UTF-8 乱码修复（把“ðŸ… / Ã / â …”类还原），不依赖 dart:convert ——
// （避免你在 main.dart 顶部忘记 import 导致的报错）
String _fixUtf8Mojibake(String? raw) {
  if (raw == null || raw.isEmpty) return raw ?? '';
  var s = raw;

  // 若不存在典型乱码痕迹，直接返回
  if (!s.contains('ð') && !s.contains('Ã') && !s.contains('â')) return s;

  const map = <String, String>{
    'ðŸŽ‰': '🎉', // party popper
    'ðŸŽ': '🎁', // gift
    'â†’': '→',
    'â€”': '—',
    'â€“': '–',
    'â€œ': '“',
    'â€': '”',
    'â€˜': '‘',
    'â€™': '’',
    'â€¢': '•',
    'â€¦': '…',
    'Ã—': '×',
    'Ã·': '÷',
    'Â®': '®',
    'Â©': '©',
    'Â°': '°',
    'Â·': '·',
    'Â':  '',  // 孤立的 Â
  };

  map.forEach((k, v) => s = s.replaceAll(k, v));
  return s;
}

// 简单的“欢迎礼”弹窗（保持与其他处视觉一致）
void _showWelcomeGiftDialog() {
  final ctx = appNavKey.currentContext;
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
            child: Icon(Icons.card_giftcard, size: 30.w, color: const Color(0xFF2196F3)),
          ),
          SizedBox(height: 12.h),
          Text(_fixUtf8Mojibake('Welcome gift 🎁'),
              style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700)),
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
                    appNavKey.currentState?.push(MaterialPageRoute(builder: (_) => TaskManagementPage()));
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
                    appNavKey.currentState?.push(MaterialPageRoute(builder: (_) => CouponManagementPage()));
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

  // === 静音 Supabase 的 refresh session 噪音（仅开发期） ===
      {
    final _orig = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null &&
          message.contains('supabase.auth: INFO: Refresh session')) {
        return; // 忽略这条日志
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
                Text('Something went wrong', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.sp)),
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
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJoY2t5YnNlbGFyemdsa21seXFzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTUwMTM0NTgsImV4cCI6MjA3MDU4OTQ1OH0.3I0T2DidiF-q9l2tWeHOjB31QogXHDqRtEjDn0RfVbU',
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce, // 👈 关键，别写成 flowType
      autoRefreshToken: true,
    ),
  );


  // ✅ 在 Supabase 初始化后，runApp 之前调用全局监听器
  wireAuthHook();

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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
        debugPrint('App resumed - clearing notifications if needed');
        // 不再主动 refreshSession，避免自动登出
        // AuthService().refreshSession(minInterval: const Duration(minutes: 15));
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
              // ✅ 仅使用 initialRoute，避免同时设置 home 造成路由冲突
              initialRoute: hasSession ? '/home' : '/welcome',
              routes: {
                '/welcome': (_) => const WelcomeScreen(),
                '/login': (_) => const LoginScreen(),
                '/home': (_) => const swaply.HomePage(),
                '/coupons': (_) => CouponManagementPage(),
              },
            );
          },
        );
      },
    );
  }
}

// ç»§ç»­æ·»åŠ  MainNavigationPage å’Œå…¶ä»–ç±»...
// [ä¸ºäº†èŠ‚çœç©ºé—´ï¼Œè¿™é‡Œä¿æŒå…¶ä½™ä»£ç ä¸å˜]
// ç»§ç»­æ·»åŠ  MainNavigationPage å’Œå…¶ä»–ç±»...
class MainNavigationPage extends StatefulWidget {
  final bool isGuest;
  const MainNavigationPage({Key? key, this.isGuest = false}) : super(key: key);
  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> with TickerProviderStateMixin {
  int _selectedIndex = 0;
  int _notificationCount = 0;
  late AnimationController _sellButtonController;
  late Animation<double> _sellButtonAnimation;
  // â‘¤ åˆ æŽ‰ç¬¬äºŒå¥—ç›‘å¬å™¨ç›¸å…³å˜é‡ï¼ˆå·²åˆ é™¤ _authSubscriptionï¼‰

  final _homeKey = GlobalKey<NavigatorState>();
  final _savedKey = GlobalKey<NavigatorState>();
  final _sellKey = GlobalKey<NavigatorState>();
  final _notifKey = GlobalKey<NavigatorState>();
  final _profileKey = GlobalKey<NavigatorState>();

  late final List<GlobalKey<NavigatorState>> _navigatorKeys = [
    _homeKey, _savedKey, _sellKey, _notifKey, _profileKey,
  ];

  // âœ… æ–°å¢žï¼šç±»çº§åˆ«çš„é™æ€æ ‡è®°
  static bool _welcomeGiftChecked = false;

  @override
  void initState() {
    super.initState();
    _loadNotificationCount();

    // â‘¤ åˆ æŽ‰ MainNavigationPage é‡Œçš„ç¬¬äºŒå¥—ç›‘å¬å™¨ï¼ˆæ•´æ®µåˆ é™¤ï¼‰

    // SellæŒ‰é’®åŠ¨ç”»
    _sellButtonController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _sellButtonAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _sellButtonController, curve: Curves.easeInOut),
    );

    // âœ… æ–°å¢žï¼šå»¶è¿Ÿæ£€æŸ¥æ¬¢è¿Žåˆ¸ï¼ˆå…œåº•æœºåˆ¶ï¼‰
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
    // â‘¤ åˆ æŽ‰å–æ¶ˆè®¢é˜…ä»£ç ï¼ˆå·²åˆ é™¤ï¼‰
    super.dispose();
  }

  // âœ… æ–°å¢žï¼šæ£€æŸ¥å¹¶æ˜¾ç¤ºæ¬¢è¿Žåˆ¸çš„æ–¹æ³•
  Future<void> _checkAndShowWelcomeGift() async {
    // 避免重复检查
    if (_welcomeGiftChecked) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingKey = 'new_user_welcome_pending_${user.id}';
      final shownKey   = 'welcome_gift_shown_${user.id}';

      // 只在“刚创建了欢迎券”的情况下弹窗（该标记在 wireAuthHook 中被置为 true）
      final pending = prefs.getBool(pendingKey) ?? false;
      if (!pending) {
        _welcomeGiftChecked = true; // 没有待弹窗标记：认为已检查过，避免反复查询
        return;
      }

      // 尝试取出最新 welcome 券以展示码值（失败也不影响弹窗）
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

      // 标记已处理，并清掉 pending
      _welcomeGiftChecked = true;
      await prefs.setBool(shownKey, true);
      await prefs.remove(pendingKey);

      if (!mounted) return;
      if (row != null) {
        _showLocalWelcomeDialog(row);   // 带码值的弹窗
      } else {
        _showWelcomeGiftDialog();       // 兜底弹窗（无码值也可）
      }
    } catch (e) {
      if (kDebugMode) {
        print('[MainNavigation] Error checking welcome gift: $e');
      }
    }
  }

  void _showLocalWelcomeDialog(Map<String, dynamic> couponData) {
    showDialog(
      context: context,
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
              child: Icon(Icons.card_giftcard, size: 30.w, color: const Color(0xFF2196F3)),
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
                        MaterialPageRoute(builder: (_) => CouponManagementPage()),
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
        final count = await NotificationService.getUnreadNotificationsCount();
        if (mounted) {
          setState(() => _notificationCount = count);
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error loading notification count: $e');
        }
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.w)),
          title: Text(l10n.loginRequired, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
          content: Text(l10n.loginRequiredMessage(feature), style: TextStyle(fontSize: 13.sp, height: 1.4)),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel, style: TextStyle(fontSize: 13.sp, color: Colors.grey[600]))
            ),
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF2196F3), Color(0xFF1E88E5)]),
                borderRadius: BorderRadius.circular(6.w),
              ),
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pushNamedAndRemoveUntil('/welcome', (route) => false);
                },
                child: Text(l10n.login, style: TextStyle(color: Colors.white, fontSize: 13.sp, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTabNavigator(GlobalKey<NavigatorState> key, Widget root, LanguageProvider languageProvider) {
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

  // æ–°å¢žï¼šåˆ‡æ¢åˆ°é¦–é¡µçš„æ–¹æ³•
  void _navigateToHome() {
    setState(() => _selectedIndex = 0);
  }
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final languageProvider = Provider.of<LanguageProvider>(context);

    // å®šä¹‰5ä¸ªæ ‡ç­¾é¡µ
    final List<Widget> _pages = [
      _buildTabNavigator(_homeKey, const _HomeRoot(), languageProvider),
      _buildTabNavigator(_savedKey, _SavedRoot(
        isGuest: widget.isGuest,
        onNavigateToHome: _navigateToHome,
      ), languageProvider),
      _buildTabNavigator(_sellKey, _SellRoot(isGuest: widget.isGuest), languageProvider),
      _buildTabNavigator(_notifKey, _NotifRoot(
        onClearBadge: _clearNotifications,
        isGuest: widget.isGuest,
        onNotificationCountChanged: (count) {
          if (mounted) {
            setState(() => _notificationCount = count);
          }
        },
      ), languageProvider),
      _buildTabNavigator(_profileKey, _ProfileRoot(isGuest: widget.isGuest), languageProvider),
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
          child: SafeArea(
            top: false,
            child: Container(
              height: 65.h,
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
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
        if (widget.isGuest && (index == 1)) {
          _showLoginRequired(l10n.saveItems, context);
          return;
        }
        setState(() => _selectedIndex = index);
      },
      child: Container(
        width: 60.w, // å¢žåŠ å®½åº¦ä»¥æ˜¾ç¤ºå®Œæ•´æ–‡å­—
        height: 52.h,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 4.h),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF2196F3).withOpacity(0.1)
                : Colors.transparent,
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
                  color: isSelected
                      ? const Color(0xFF2196F3)
                      : Colors.grey[600],
                  size: 22.w,
                ),
              ),
              SizedBox(height: 2.h),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 150),
                style: TextStyle(
                  color: isSelected
                      ? const Color(0xFF2196F3)
                      : Colors.grey[600],
                  fontSize: 8.5.sp, // ç¨å¾®è°ƒæ•´å­—ä½“å¤§å°
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center, // å±…ä¸­å¯¹é½
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
          if (index == 3) _loadNotificationCount();
        });
      },
      child: Container(
        width: 60.w, // å¢žåŠ å®½åº¦ä»¥æ˜¾ç¤ºå®Œæ•´æ–‡å­—
        height: 52.h,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 4.h),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF2196F3).withOpacity(0.1)
                : Colors.transparent,
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
                      color: isSelected
                          ? const Color(0xFF2196F3)
                          : Colors.grey[600],
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
                  color: isSelected
                      ? const Color(0xFF2196F3)
                      : Colors.grey[600],
                  fontSize: 8.5.sp, // ç¨å¾®è°ƒæ•´å­—ä½“å¤§å°
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center, // å±…ä¸­å¯¹é½
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
              width: 56.w, // 稍微增大悬浮按钮
              height: 46.h, // ↓ 降低高度以避免底部 3~4px 溢出
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isSelected
                      ? [
                    const Color(0xFF1565C0),
                    const Color(0xFF2196F3),
                    const Color(0xFF42A5F5),
                  ]
                      : [
                    const Color(0xFF2196F3),
                    const Color(0xFF1E88E5),
                    const Color(0xFF1976D2),
                  ],
                ),
                borderRadius: BorderRadius.circular(28.w),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2196F3).withOpacity(0.4),
                    blurRadius: isSelected ? 12.h : 10.h,
                    offset: Offset(0, isSelected ? 4.h : 3.h),
                    spreadRadius: isSelected ? 2.w : 1.w,
                  ),
                  // 添加额外的阴影增强悬浮效果
                  BoxShadow(
                    color: const Color(0xFF2196F3).withOpacity(0.2),
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
                      size: 22.h, // ↓ 减小图标以配合整体高度
                    ),
                  ),
                  SizedBox(height: 0.5.h), // ↓ 减少上下留白
                  Text(
                    l10n.sell,
                    textHeightBehavior: const TextHeightBehavior(
                      applyHeightToFirstAscent: false,
                      applyHeightToLastDescent: false,
                    ),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 7.5.sp,  // ↓ 再小一点避免文字行高撑开
                      height: 1.0,       // ↓ 紧凑行高，消除 1~2px 视觉溢出
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

// ... ç»§ç»­æ·»åŠ å‰©ä½™çš„ä»£ç ï¼ˆåŒ…æ‹¬æ‰€æœ‰å…¶ä»–é¡µé¢ç»„ä»¶ï¼‰...
// ç”±äºŽä»£ç å¤ªé•¿ï¼Œæˆ‘åªå±•ç¤ºäº†ä¿®æ”¹çš„æ ¸å¿ƒéƒ¨åˆ†ã€‚å…¶ä½™éƒ¨åˆ†ä¿æŒä¸å˜.
/* ---------------- Tab æ ¹é¡µ ---------------- */

class _HomeRoot extends StatelessWidget {
  const _HomeRoot();
  @override
  Widget build(BuildContext context) => const swaply.HomePage();
}

// ä¿®æ”¹ï¼šæ·»åŠ å¯¼èˆªå›žè°ƒå‚æ•°
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
class SavedPage extends StatefulWidget {
  final bool isGuest;
  final VoidCallback? onNavigateToHome;
  const SavedPage({Key? key, this.isGuest = false, this.onNavigateToHome}) : super(key: key);

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (!widget.isGuest) {
      _loadFavorites();
      // å¯åŠ¨è‡ªåŠ¨åˆ·æ–°å®šæ—¶å™¨ï¼ˆæ¯30ç§’æ£€æŸ¥ä¸€æ¬¡ï¼‰
      _startAutoRefresh();
      // è®¾ç½®æ”¶è—æ›´æ–°ç›‘å¬
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

  // âœ… ä¿®å¤ï¼šè¿™é‡Œåº”è¯¥æ˜¯ç”Ÿå‘½å‘¨æœŸå›žè°ƒï¼Œè€Œä¸æ˜¯è·¯ç”±æ¡ç›®
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !widget.isGuest) {
      // åº”ç”¨é‡æ–°æ¿€æ´»æ—¶åˆ·æ–°æ•°æ®
      _loadFavorites();
    }
  }

  /// è®¾ç½®æ”¶è—æ›´æ–°ç›‘å¬
  void _setupFavoritesListener() {
    _favoritesSubscription = FavoritesUpdateService().favoritesStream.listen(
          (event) {
        if (!mounted || widget.isGuest) return;

        if (kDebugMode) {
          print('SavedPage received favorite update: ${event.listingId}, added: ${event.isAdded}');
        }

        if (event.isAdded && event.listingData != null) {
          // æ·»åŠ åˆ°æ”¶è—ï¼šç«‹å³æ·»åŠ åˆ°æœ¬åœ°åˆ—è¡¨
          _addToLocalFavorites(event.listingData!);
        } else if (!event.isAdded) {
          // ä»Žæ”¶è—ç§»é™¤ï¼šç«‹å³ä»Žæœ¬åœ°åˆ—è¡¨ç§»é™¤
          _removeFromLocalFavorites(event.listingId);
        }
      },
      onError: (error) {
        if (kDebugMode) print('Error in favorites stream: $error');
      },
    );
  }

  /// ç«‹å³æ·»åŠ åˆ°æœ¬åœ°æ”¶è—åˆ—è¡¨
  void _addToLocalFavorites(Map<String, dynamic> listingData) {
    try {
      // æ£€æŸ¥æ˜¯å¦å·²å­˜åœ¨
      final listingId = listingData['id']?.toString();
      if (listingId == null) return;

      final exists = _favoriteItems.any((item) =>
      item['listing_id']?.toString() == listingId ||
          item['listing']?['id']?.toString() == listingId
      );

      if (!exists) {
        // æž„é€ ç¬¦åˆæ”¶è—æ ¼å¼çš„æ•°æ®
        final favoriteItem = {
          'listing_id': listingId,
          'listing': _safeMapConvert(listingData),
          'created_at': DateTime.now().toIso8601String(),
        };

        setState(() {
          _favoriteItems.insert(0, favoriteItem); // æ’å…¥åˆ°åˆ—è¡¨å¼€å¤´
        });

        if (kDebugMode) {
          print('Added item to local favorites: $listingId');
        }
      }
    } catch (e) {
      if (kDebugMode) print('Error adding to local favorites: $e');
    }
  }

  /// ç«‹å³ä»Žæœ¬åœ°æ”¶è—åˆ—è¡¨ç§»é™¤
  void _removeFromLocalFavorites(String listingId) {
    try {
      final initialLength = _favoriteItems.length;

      setState(() {
        _favoriteItems.removeWhere((item) =>
        item['listing_id']?.toString() == listingId ||
            item['listing']?['id']?.toString() == listingId
        );
      });

      if (_favoriteItems.length < initialLength) {
        if (kDebugMode) {
          print('Removed item from local favorites: $listingId');
        }
      }
    } catch (e) {
      if (kDebugMode) print('Error removing from local favorites: $e');
    }
  }

  /// å¯åŠ¨è‡ªåŠ¨åˆ·æ–°å®šæ—¶å™¨
  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!widget.isGuest && mounted && !_isRefreshing) {
        if (kDebugMode) print('è‡ªåŠ¨åˆ·æ–°æ”¶è—åˆ—è¡¨...');
        _loadFavorites();
      }
    });
  }

  /// å®‰å…¨çš„ç±»åž‹è½¬æ¢æ–¹æ³•
  Map<String, dynamic> _safeMapConvert(dynamic input) {
    if (input == null) return <String, dynamic>{};

    if (input is Map<String, dynamic>) {
      return input;
    } else if (input is Map) {
      try {
        return Map<String, dynamic>.from(input);
      } catch (e) {
        if (kDebugMode) print('ç±»åž‹è½¬æ¢å¤±è´¥: $e');
        return <String, dynamic>{};
      }
    }

    return <String, dynamic>{};
  }

  /// å®‰å…¨èŽ·å–å­—ç¬¦ä¸²å€¼
  String _safeGetString(Map<String, dynamic> map, String key, {String defaultValue = ''}) {
    try {
      return map[key]?.toString() ?? defaultValue;
    } catch (e) {
      if (kDebugMode) print('Error getting string for key $key: $e');
      return defaultValue;
    }
  }

  /// åŠ è½½æ”¶è—åˆ—è¡¨ - ä¿®å¤ï¼šä½¿ç”¨ DualFavoritesService
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

      if (kDebugMode) {
        print('Loading favorites for user: ${user.id}');
      }

      // ä¿®å¤ï¼šä½¿ç”¨ DualFavoritesService èŽ·å–æ”¶è—åˆ—è¡¨ï¼ˆä»Ž favorites è¡¨ï¼‰
      final rawItems = await DualFavoritesService.getUserFavorites(
        userId: user.id,
        limit: 100,
      );

      if (mounted) {
        // å®‰å…¨è½¬æ¢æ•°æ®
        final safeItems = <Map<String, dynamic>>[];
        for (final item in rawItems) {
          final safeItem = _safeMapConvert(item);
          if (safeItem.isNotEmpty) {
            // ç¡®ä¿ listing æ•°æ®ä¹Ÿæ˜¯å®‰å…¨è½¬æ¢çš„
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

        if (kDebugMode) {
          print('Loaded ${_favoriteItems.length} favorite items');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading favorites: $e');
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load favorites. Please try again.';
        });
      }
    }
  }

  /// åˆ·æ–°æ”¶è—åˆ—è¡¨
  Future<void> _refreshFavorites() async {
    setState(() => _isRefreshing = true);
    await _loadFavorites();
    setState(() => _isRefreshing = false);
  }

  /// ä»Žæ”¶è—å¤¹ç§»é™¤å•†å“ - ä¿®å¤ï¼šä½¿ç”¨ DualFavoritesService
  Future<void> _removeFromFavorites(String listingId, int index) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      // ä¿®å¤ï¼šä½¿ç”¨ DualFavoritesService åŒæ­¥ç§»é™¤
      final success = await DualFavoritesService.removeFromFavorites(
        userId: user.id,
        listingId: listingId,
      );

      if (success && mounted) {
        setState(() {
          _favoriteItems.removeAt(index);
        });

        // å‘é€å®žæ—¶æ›´æ–°é€šçŸ¥
        FavoritesUpdateService().notifyFavoriteChanged(
          listingId: listingId,
          isAdded: false,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 12.w),
                SizedBox(width: 4.w),
                const Text('Removed from favorites and wishlist'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.w)),
            margin: EdgeInsets.all(8.w),
          ),
        );
      } else {
        throw Exception('Failed to remove from favorites');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error removing from favorites: $e');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline_rounded, color: Colors.white, size: 12.w),
              SizedBox(width: 4.w),
              const Text('Failed to remove item. Please try again.'),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.w)),
          margin: EdgeInsets.all(8.w),
        ),
      );
    }
  }

  /// èŽ·å–å•†å“å›¾ç‰‡ - å®‰å…¨ç‰ˆæœ¬
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

  /// æ ¼å¼åŒ–ä»·æ ¼ - å®‰å…¨ç‰ˆæœ¬
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

  /// æž„å»ºå•†å“å¡ç‰‡ - ä¿®å¤ç‰ˆæœ¬
  Widget _buildFavoriteCard(Map<String, dynamic> item, int index) {
    try {
      // å®‰å…¨çš„ç±»åž‹è½¬æ¢ - ç»Ÿä¸€ä½¿ç”¨ 'listing' é”®
      final safeListing = _safeMapConvert(item['listing'] ?? {});
      final safeItem = _safeMapConvert(item);

      final listingId = _safeGetString(safeItem, 'listing_id');
      if (listingId.isEmpty) {
        if (kDebugMode) print('Warning: Empty listing ID for item at index $index');
        return const SizedBox.shrink();
      }

      final title = _safeGetString(safeListing, 'title', defaultValue: 'Unknown Item');
      final price = _formatPrice(safeListing['price']);
      final city = _safeGetString(safeListing, 'city');
      final imageUrl = _getListingImage(safeListing);
      final createdAt = _safeGetString(safeItem, 'created_at');

      // æ ¼å¼åŒ–æ”¶è—æ—¶é—´
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
                // ä»Žå•†å“è¯¦æƒ…é¡µè¿”å›žåŽåˆ·æ–°åˆ—è¡¨
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
                  // å•†å“å›¾ç‰‡ - ç¼©å°
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
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Center(
                              child: SizedBox(
                                width: 12.w,
                                height: 12.w,
                                child: CircularProgressIndicator(
                                  value: loadingProgress.expectedTotalBytes != null
                                      ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                      : null,
                                  strokeWidth: 1.w,
                                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2196F3)),
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

                  // å•†å“ä¿¡æ¯ - ç¼©å°å­—ä½“å’Œé—´è·
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
                          padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 1.h),
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

                  // ç§»é™¤æŒ‰é’® - ç¼©å°
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
      if (kDebugMode) {
        print('Error building favorite card at index $index: $e');
        print('Stack trace: $stackTrace');
        print('Item data: $item');
      }
      // è¿”å›žé”™è¯¯å¡ç‰‡è€Œä¸æ˜¯å´©æºƒ
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

  /// æ˜¾ç¤ºç§»é™¤ç¡®è®¤å¯¹è¯æ¡†
  void _showRemoveDialog(String listingId, String title, int index) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.w)),
          title: Row(
            children: [
              Container(
                padding: EdgeInsets.all(4.w),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4.w),
                ),
                child: Icon(Icons.delete_outline_rounded, color: Colors.red, size: 14.w),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  'Remove from Favorites',
                  style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
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
              child: Text('Cancel', style: TextStyle(fontSize: 11.sp, color: Colors.grey[600])),
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

  /// æž„å»ºç©ºçŠ¶æ€ - ç´§å‡‘ç‰ˆ
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
                  // ä¿®å¤ï¼šä½¿ç”¨å›žè°ƒå‡½æ•°å¯¼èˆªåˆ°é¦–é¡µ
                  if (widget.onNavigateToHome != null) {
                    widget.onNavigateToHome!();
                  } else {
                    // å¤‡ç”¨æ–¹æ¡ˆï¼šå¼¹å‡ºåˆ°é¡¶å±‚
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.w),
                  ),
                ),
                icon: Icon(Icons.explore_rounded, size: 12.w, color: Colors.white),
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

  /// æž„å»ºé”™è¯¯çŠ¶æ€
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
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.w),
                  ),
                ),
                icon: Icon(Icons.refresh_rounded, size: 12.w),
                label: Text(
                  'Try Again',
                  style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w600),
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
    // å®‰å…¨èŽ·å–æœ¬åœ°åŒ–ï¼Œé¿å…ä¸ºç©º
    AppLocalizations? l10n;
    try {
      l10n = AppLocalizations.of(context);
    } catch (e) {
      if (kDebugMode) {
        print('AppLocalizations not available: $e');
      }
    }

    // è®¿å®¢çŠ¶æ€
    if (widget.isGuest) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          backgroundColor: const Color(0xFF2196F3),
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
                  l10n?.loginToSaveFavorites ?? 'Please login to view and save your favorite items.',
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
                    colors: [Color(0xFF2196F3), Color(0xFF1E88E5)],
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
                    Navigator.of(context).pushNamedAndRemoveUntil('/welcome', (route) => false);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.w),
                    ),
                  ),
                  icon: Icon(Icons.login_rounded, size: 12.w, color: Colors.white),
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

    // å·²ç™»å½•çŠ¶æ€
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2196F3),
        title: Text(
          'My Favorites (${_favoriteItems.length})',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
        elevation: 0,
        actions: [
          if (_favoriteItems.isNotEmpty && !_isLoading)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, color: Colors.white, size: 16.w),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.w)),
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
            ),
        ],
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
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2196F3)),
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
        color: const Color(0xFF2196F3),
        backgroundColor: Colors.white,
        strokeWidth: 2.w,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(vertical: 6.h),
          itemCount: _favoriteItems.length,
          itemBuilder: (context, index) {
            return _buildFavoriteCard(_favoriteItems[index], index);
          },
        ),
      ),
    );
  }

  /// æ˜¾ç¤ºæ¸…ç©ºæ‰€æœ‰ç¡®è®¤å¯¹è¯æ¡†
  void _showClearAllDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.w)),
          title: Row(
            children: [
              Container(
                padding: EdgeInsets.all(4.w),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4.w),
                ),
                child: Icon(Icons.warning_outlined, color: Colors.red, size: 14.w),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  'Clear All Favorites',
                  style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
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
              child: Text('Cancel', style: TextStyle(fontSize: 11.sp, color: Colors.grey[600])),
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

  /// æ¸…ç©ºæ‰€æœ‰æ”¶è— - ä¿®å¤ï¼šä½¿ç”¨ DualFavoritesService åŒæ­¥æ¸…ç©º
  Future<void> _clearAllFavorites() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      // å…ˆä¿å­˜å½“å‰åˆ—è¡¨é¡¹ï¼Œç”¨äºŽå‘é€é€šçŸ¥
      final currentItems = List<Map<String, dynamic>>.from(_favoriteItems);

      // ä¿®å¤ï¼šä½¿ç”¨ DualFavoritesService åŒæ­¥æ¸…ç©º
      final success = await DualFavoritesService.clearUserFavorites(userId: user.id);

      if (success && mounted) {
        setState(() {
          _favoriteItems.clear();
        });

        // å‘é€å®žæ—¶æ¸…ç©ºé€šçŸ¥
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
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 12.w),
                SizedBox(width: 4.w),
                const Text('All favorites and wishlist cleared successfully'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.w)),
            margin: EdgeInsets.all(8.w),
          ),
        );
      } else {
        throw Exception('Failed to clear favorites');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error clearing favorites: $e');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline_rounded, color: Colors.white, size: 12.w),
              SizedBox(width: 4.w),
              const Text('Failed to clear favorites. Please try again.'),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.w)),
          margin: EdgeInsets.all(8.w),
        ),
      );
    }
  }
}
/* ---------------- Wishlist Page å¿ƒæ„¿å•é¡µé¢ - æ–°å¢ž ---------------- */

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

  /// åŠ è½½å¿ƒæ„¿å•åˆ—è¡¨
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

      if (kDebugMode) {
        print('Loading wishlist for user: ${user.id}');
      }

      // ä½¿ç”¨ DualFavoritesService èŽ·å–å¿ƒæ„¿å•åˆ—è¡¨ï¼ˆä»Ž wishlists è¡¨ï¼‰
      final items = await DualFavoritesService.getUserWishlist(
        userId: user.id,
        limit: 100,
      );

      if (mounted) {
        setState(() {
          _wishlistItems = items;
          _isLoading = false;
        });

        if (kDebugMode) {
          print('Loaded ${items.length} wishlist items');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading wishlist: $e');
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load wishlist. Please try again.';
        });
      }
    }
  }

  /// åˆ·æ–°å¿ƒæ„¿å•åˆ—è¡¨
  Future<void> _refreshWishlist() async {
    setState(() => _isRefreshing = true);
    await _loadWishlist();
    setState(() => _isRefreshing = false);
  }

  /// ä»Žå¿ƒæ„¿å•ç§»é™¤å•†å“
  Future<void> _removeFromWishlist(String listingId, int index) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      // ä½¿ç”¨ DualFavoritesService åŒæ­¥ç§»é™¤
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
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 16.w),
                SizedBox(width: 6.w),
                const Text('Removed from wishlist and favorites'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.w)),
            margin: EdgeInsets.all(12.w),
          ),
        );
      } else {
        throw Exception('Failed to remove from wishlist');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error removing from wishlist: $e');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline_rounded, color: Colors.white, size: 16.w),
              SizedBox(width: 6.w),
              const Text('Failed to remove item. Please try again.'),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.w)),
          margin: EdgeInsets.all(12.w),
        ),
      );
    }
  }

  /// èŽ·å–å•†å“å›¾ç‰‡
  String _getListingImage(Map<String, dynamic> listing) {
    final images = listing['images'] ?? listing['image_urls'];
    if (images is List && images.isNotEmpty) {
      return images.first.toString();
    }
    return 'assets/images/placeholder.jpg';
  }

  /// æ ¼å¼åŒ–ä»·æ ¼
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

  /// æž„å»ºå¿ƒæ„¿å•å¡ç‰‡
  Widget _buildWishlistCard(Map<String, dynamic> item, int index) {
    final listing = item['listing'] ?? {};
    final listingId = item['listing_id']?.toString() ?? listing['id']?.toString() ?? '';
    final title = listing['title']?.toString() ?? 'Unknown Item';
    final price = _formatPrice(listing['price']);
    final city = listing['city']?.toString() ?? '';
    final imageUrl = _getListingImage(listing);
    final createdAt = item['created_at']?.toString() ?? '';

    // æ ¼å¼åŒ–æ·»åŠ æ—¶é—´
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
              // ä»Žå•†å“è¯¦æƒ…é¡µè¿”å›žåŽåˆ·æ–°åˆ—è¡¨
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
                // å•†å“å›¾ç‰‡
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
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(
                            child: SizedBox(
                              width: 15.w,
                              height: 15.w,
                              child: CircularProgressIndicator(
                                value: loadingProgress.expectedTotalBytes != null
                                    ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                    : null,
                                strokeWidth: 1.5.w,
                                valueColor: const AlwaysStoppedAnimation<Color>(Colors.pink),
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

                // å•†å“ä¿¡æ¯
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
                        padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
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

                // ç§»é™¤æŒ‰é’®
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

  /// æ˜¾ç¤ºç§»é™¤ç¡®è®¤å¯¹è¯æ¡†
  void _showRemoveDialog(String listingId, String title, int index) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.w)),
          title: Row(
            children: [
              Container(
                padding: EdgeInsets.all(6.w),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6.w),
                ),
                child: Icon(Icons.delete_outline_rounded, color: Colors.red, size: 16.w),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  'Remove from Wishlist',
                  style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
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
              child: Text('Cancel', style: TextStyle(fontSize: 13.sp, color: Colors.grey[600])),
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

  /// æž„å»ºç©ºçŠ¶æ€
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
                  padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.w),
                  ),
                ),
                icon: Icon(Icons.explore_rounded, size: 16.w, color: Colors.white),
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

  /// æž„å»ºé”™è¯¯çŠ¶æ€
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
                  padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.w),
                  ),
                ),
                icon: Icon(Icons.refresh_rounded, size: 16.w),
                label: Text(
                  'Try Again',
                  style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
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
              icon: Icon(Icons.more_vert_rounded, color: Colors.white, size: 20.w),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.w)),
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
                      Icon(Icons.clear_all_rounded, color: Colors.red, size: 16.w),
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
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.pink),
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
            return _buildWishlistCard(_wishlistItems[index], index);
          },
        ),
      ),
    );
  }

  /// æ˜¾ç¤ºæ¸…ç©ºæ‰€æœ‰ç¡®è®¤å¯¹è¯æ¡†
  void _showClearAllDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.w)),
          title: Row(
            children: [
              Container(
                padding: EdgeInsets.all(6.w),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6.w),
                ),
                child: Icon(Icons.warning_outlined, color: Colors.red, size: 16.w),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  'Clear All Wishlist',
                  style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
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
              child: Text('Cancel', style: TextStyle(fontSize: 13.sp, color: Colors.grey[600])),
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

  /// æ¸…ç©ºæ‰€æœ‰å¿ƒæ„¿å•
  Future<void> _clearAllWishlist() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      // ä½¿ç”¨ DualFavoritesService åŒæ­¥æ¸…ç©º
      final success = await DualFavoritesService.clearUserFavorites(userId: user.id);

      if (success && mounted) {
        setState(() {
          _wishlistItems.clear();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 16.w),
                SizedBox(width: 6.w),
                const Text('All wishlist and favorites cleared successfully'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.w)),
            margin: EdgeInsets.all(12.w),
          ),
        );
      } else {
        throw Exception('Failed to clear wishlist');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error clearing wishlist: $e');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline_rounded, color: Colors.white, size: 16.w),
              SizedBox(width: 6.w),
              const Text('Failed to clear wishlist. Please try again.'),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.w)),
          margin: EdgeInsets.all(12.w),
        ),
      );
    }
  }
}
// ç¬¬å››éƒ¨åˆ†ï¼šSellPage å‡ºå”®é¡µ (æ¢å¤å®Œæ•´åŠŸèƒ½) å’Œ NotificationPage é€šçŸ¥é¡µ (ä½¿ç”¨ç¬¬äºŒä¸ªç‰ˆæœ¬çš„Serviceé›†æˆ)

/* ---------------- Sell Page å‡ºå”®é¡µ (ç¾ŽåŒ–ç‰ˆæœ¬) ---------------- */

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
    final List<Map<String, dynamic>> myListings =
    (raw is List) ? List<Map<String, dynamic>>.from(raw) : const <Map<String, dynamic>>[];

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
                        Navigator.of(context).pushNamedAndRemoveUntil('/welcome', (route) => false);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16.r),
                        ),
                      ),
                      icon: Icon(Icons.login_rounded, size: 20.r, color: Colors.white),
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
            onPressed: () => Navigator.of(context).push(
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
                    padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 16.h),
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
                                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
                          ],
                        ),
                        SizedBox(height: 8.h),
                        Row(
                          children: [
                            Icon(Icons.edit_rounded,
                                color: const Color(0xFF2196F3), size: 20.r),
                            SizedBox(width: 8.w),
                            Text('Write detailed description',
                                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
                          ],
                        ),
                        SizedBox(height: 8.h),
                        Row(
                          children: [
                            Icon(Icons.monetization_on_rounded,
                                color: const Color(0xFF2196F3), size: 20.r),
                            SizedBox(width: 8.w),
                            Text('Set competitive price',
                                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
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
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SellFormPage()),
                      ),
                      icon: Icon(Icons.add_rounded, color: Colors.white, size: 24.r),
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

  Widget _buildListingsContent(List<Map<String, dynamic>> myListings, AppLocalizations l10n) {
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

  Widget _buildStatsHeader(List<Map<String, dynamic>> myListings, AppLocalizations l10n) {
    final totalViews = myListings.fold<int>(0, (sum, item) => sum + 234); // Mock data
    final totalLikes = myListings.fold<int>(0, (sum, item) => sum + 12); // Mock data

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
                  onTap: () => Navigator.of(context).push(
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
              Expanded(child: _buildStatCard(Icons.visibility_rounded, totalViews.toString(), 'Total Views', const Color(0xFF2196F3))),
              SizedBox(width: 12.w),
              Expanded(child: _buildStatCard(Icons.favorite_rounded, totalLikes.toString(), 'Total Likes', Colors.red.shade400)),
              SizedBox(width: 12.w),
              Expanded(child: _buildStatCard(Icons.trending_up_rounded, '${(totalViews * 0.15).toInt()}', 'Engagement', Colors.green.shade400)),
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
                // å•†å“å›¾ç‰‡
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

                // å•†å“ä¿¡æ¯
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
                          _buildEnhancedStatItem(Icons.visibility_rounded, '234', Colors.blue.shade400),
                          SizedBox(width: 16.w),
                          _buildEnhancedStatItem(Icons.favorite_rounded, '12', Colors.red.shade400),
                          SizedBox(width: 16.w),
                          _buildEnhancedStatItem(Icons.chat_bubble_rounded, '3', Colors.green.shade400),
                        ],
                      ),
                    ],
                  ),
                ),

                // èœå•æŒ‰é’®
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
                      _buildMenuItem('view', Icons.visibility_rounded, 'View', Colors.blue.shade600),
                      _buildMenuItem('edit', Icons.edit_rounded, 'Edit', Colors.orange.shade600),
                      _buildMenuItem('delete', Icons.delete_outline_rounded, 'Delete', Colors.red.shade600),
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

  PopupMenuItem<String> _buildMenuItem(String value, IconData icon, String text, Color color) {
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
          Text(text, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500)),
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

  void _handleMenuAction(String action, Map<String, dynamic> item, AppLocalizations l10n) async {
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
              child: Icon(Icons.delete_outline_rounded, color: Colors.red, size: 24.r),
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
            child: Text('Cancel', style: TextStyle(fontSize: 14.sp, color: Colors.grey.shade600)),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.red.shade400, Colors.red.shade600]),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: TextButton(
              onPressed: () {
                Navigator.pop(context);
                _deleteListing(item, l10n);
              },
              child: Text(
                'Delete',
                style: TextStyle(color: Colors.white, fontSize: 14.sp, fontWeight: FontWeight.w600),
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
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 18.r),
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
                Icon(Icons.error_outline_rounded, color: Colors.white, size: 18.r),
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

/* ---------------- Notification Page é€šçŸ¥é¡µ (ç´§å‡‘ç¾ŽåŒ–ç‰ˆæœ¬) ---------------- */

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
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onClearBadge!());
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
      if (kDebugMode) {
        print('Error loading notifications: $e');
      }
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // âœ… ä¿®æ­£ï¼šä½¿ç”¨æ­£ç¡®çš„å‚æ•°è°ƒç”¨
  Future<void> _subscribeToNotifications() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    await NotificationService.subscribeUser(
      user.id,  // ä½ç½®å‚æ•°
      onEvent: (Map<String, dynamic> notification) {  // å‘½åå‚æ•°
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
    final unreadCount = _notifications.where((n) => n['is_read'] != true).length;
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
      if (kDebugMode) {
        print('Error marking notification as read: $e');
      }
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
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 14.sp),
                SizedBox(width: 6.w),
                Text(l10n.notificationDeleted, style: TextStyle(fontSize: 12.sp)),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.r)),
            margin: EdgeInsets.all(8.w),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting notification: $e');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline_rounded, color: Colors.white, size: 14.sp),
              SizedBox(width: 6.w),
              Text('Failed to delete notification', style: TextStyle(fontSize: 12.sp)),
            ],
          ),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.r)),
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
      if (kDebugMode) {
        print('Error marking all as read: $e');
      }
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
      if (kDebugMode) {
        print('Error clearing all notifications: $e');
      }
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
        backgroundColor: isError ? Colors.red.shade600 : const Color(0xFF4CAF50),
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

    // æ·»åŠ è°ƒè¯•æ—¥å¿—
    print('[NotificationPage] ç‚¹å‡»é€šçŸ¥: ${notification.toString()}');

    final type = notification['type']?.toString() ?? '';

    // å°è¯•ä»Žå¤šä¸ªä½ç½®èŽ·å–IDä¿¡æ¯
    String? listingId = notification['listing_id']?.toString();
    String? offerId = notification['offer_id']?.toString();

    // å¦‚æžœç›´æŽ¥å­—æ®µä¸ºç©ºï¼Œå°è¯•ä»Žpayloadä¸­èŽ·å–
    final payload = notification['payload'] as Map<String, dynamic>? ?? {};
    if ((listingId == null || listingId.isEmpty) && payload.isNotEmpty) {
      listingId = payload['listing_id']?.toString();
    }
    if ((offerId == null || offerId.isEmpty) && payload.isNotEmpty) {
      offerId = payload['offer_id']?.toString();
    }

    // ä¹Ÿå°è¯•ä»Žmetadataä¸­èŽ·å–
    final metadata = notification['metadata'] as Map<String, dynamic>? ?? {};
    if ((listingId == null || listingId.isEmpty) && metadata.isNotEmpty) {
      listingId = metadata['listing_id']?.toString();
    }
    if ((offerId == null || offerId.isEmpty) && metadata.isNotEmpty) {
      offerId = metadata['offer_id']?.toString();
    }

    final notificationId = notification['id']?.toString();

    print('[NotificationPage] è§£æžç»“æžœ - Type: $type, ListingId: $listingId, OfferId: $offerId, NotificationId: $notificationId');
    print('[NotificationPage] Payloadæ•°æ®: $payload');
    print('[NotificationPage] Metadataæ•°æ®: $metadata');

    // æ£€æŸ¥æ•°æ®å®Œæ•´æ€§
    if (type.isEmpty) {
      print('[NotificationPage] é”™è¯¯ï¼šé€šçŸ¥ç±»åž‹ä¸ºç©º');
      _showSnack('Notification data is incomplete', isError: true);
      return;
    }

    switch (type) {
      case 'message':
        print('[NotificationPage] å¤„ç†æ¶ˆæ¯ç±»åž‹é€šçŸ¥');
        if (offerId != null && offerId.isNotEmpty) {
          print('[NotificationPage] è·³è½¬åˆ°æŠ¥ä»·è¯¦æƒ…é¡µ: $offerId');
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
          print('[NotificationPage] æ¶ˆæ¯ç±»åž‹é€šçŸ¥ç¼ºå°‘offer_id');
          _showSnack('Cannot open message: missing offer ID', isError: true);
        }
        break;

      case 'offer':
      case 'system':
        print('[NotificationPage] å¤„ç†æŠ¥ä»·/ç³»ç»Ÿç±»åž‹é€šçŸ¥');
        if (offerId != null && offerId.isNotEmpty) {
          print('[NotificationPage] è·³è½¬åˆ°æŠ¥ä»·è¯¦æƒ…é¡µ: $offerId');
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
          print('[NotificationPage] è·³è½¬åˆ°å•†å“è¯¦æƒ…é¡µ: $listingId');
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProductDetailPage(productId: listingId!),
            ),
          );
        } else {
          print('[NotificationPage] æŠ¥ä»·ç±»åž‹é€šçŸ¥ç¼ºå°‘å¿…è¦çš„IDä¿¡æ¯');
          print('[NotificationPage] åŽŸå§‹é€šçŸ¥æ•°æ®: ${notification.toString()}');
          _showSnack('Cannot open notification: missing required IDs', isError: true);
        }
        break;

      case 'wishlist':
      case 'price_drop':
      default:
        print('[NotificationPage] å¤„ç†å…¶ä»–ç±»åž‹é€šçŸ¥: $type');
        if (listingId != null && listingId.isNotEmpty) {
          print('[NotificationPage] è·³è½¬åˆ°å•†å“è¯¦æƒ…é¡µ: $listingId');
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProductDetailPage(productId: listingId!),
            ),
          );
        } else {
          print('[NotificationPage] é€šçŸ¥ç¼ºå°‘listing_id');
          _showSnack('Cannot open notification: missing listing ID', isError: true);
        }
        break;
    }
  }

  Map<String, dynamic>? _buildOfferDataFromNotification(Map<String, dynamic> notification) {
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
          backgroundColor: const Color(0xFF2196F3),
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
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2196F3), Color(0xFF1E88E5)],
                  ),
                  borderRadius: BorderRadius.circular(10.r),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2196F3).withOpacity(0.3),
                      blurRadius: 8.r,
                      offset: Offset(0, 3.h),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginScreen()),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                  ),
                  icon: Icon(Icons.login_rounded, size: 14.r, color: Colors.white),
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

    final unreadCount = _notifications.where((n) => n['is_read'] != true).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2196F3),
        title: Text(
          '${l10n.notifications}${unreadCount > 0 ? ' ($unreadCount)' : ''}',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
        elevation: 0,
        centerTitle: true,
        actions: [
          if (_notifications.isNotEmpty)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, color: Colors.white, size: 18.r),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
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
                      Icon(Icons.done_all_rounded, size: 14.r, color: Colors.grey.shade600),
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
                      Text(l10n.clearAll, style: TextStyle(fontSize: 12.sp, color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
        ],
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
                color: const Color(0xFF2196F3).withOpacity(0.08),
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
                      const Color(0xFF2196F3).withOpacity(0.2),
                      const Color(0xFF2196F3).withOpacity(0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20.r),
                ),
                child: Center(
                  child: SizedBox(
                    width: 20.w,
                    height: 20.w,
                    child: CircularProgressIndicator(
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2196F3)),
                      strokeWidth: 2.5,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 12.h),
              Text(
                'Loading notifications...',
                style: TextStyle(
                  color: const Color(0xFF2196F3),
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
                    const Color(0xFF2196F3).withOpacity(0.1),
                    const Color(0xFF1E88E5).withOpacity(0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(30.r),
                border: Border.all(
                  color: const Color(0xFF2196F3).withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.notifications_none_rounded,
                size: 30.r,
                color: const Color(0xFF2196F3),
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
        color: const Color(0xFF2196F3),
        backgroundColor: Colors.white,
        strokeWidth: 2.w,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: _notifications.length,
          itemBuilder: (context, index) {
            final notification = _notifications[index];
            final isRead = notification['is_read'] == true;
            final type = notification['type']?.toString() ?? '';
            final createdAt = notification['created_at']?.toString() ?? '';

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
                    : const Color(0xFF2196F3).withOpacity(0.03),
                margin: EdgeInsets.only(bottom: 0.5.h),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _handleNotificationTap(notification),
                    splashColor: const Color(0xFF2196F3).withOpacity(0.1),
                    highlightColor: const Color(0xFF2196F3).withOpacity(0.05),
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
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (!isRead)
                                      Container(
                                        width: 6.w,
                                        height: 6.w,
                                        margin: EdgeInsets.only(left: 6.w),
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF2196F3),
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
                                      NotificationService.formatNotificationTime(createdAt),
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

/* ---------------- 公共：无边缘光晕滚动 & UI 基座 ---------------- */

class NoGlowScrollBehavior extends ScrollBehavior {
  @override
  Widget buildViewportChrome(BuildContext context, Widget child, AxisDirection axisDirection) {
    return child;
  }
}
const _kPrivacyUrl = 'https://www.swaply.cc/privacy';
const _kDeleteUrl  = 'https://www.swaply.cc/delete-account';
/* ---------------- Profile Page 个人资料页 ---------------- */
class ProfilePage extends StatefulWidget {
  final bool isGuest;
  const ProfilePage({Key? key, this.isGuest = false}) : super(key: key);

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
  bool _loading = true;

  /// 基础资料（显示名/头像/时间等）
  Map<String, dynamic>? _profile;

  /// 只读的 profiles 行（仅含 verification_type 等）
  Map<String, dynamic>? _profileRow;

  final _svc = ProfileService();

  // ✅ 新增：认证服务与状态（仅看 user_verifications）
  final _verifySvc = EmailVerificationService();
  bool _verified = false;
  vt.VerificationBadgeType _badge = vt.VerificationBadgeType.none;
  Map<String, dynamic>? _verificationRow;
  bool _verifyLoading = false;

  bool _uploadingAvatar = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController =
        AnimationController(duration: const Duration(milliseconds: 800), vsync: this);
    _fadeAnimation =
        CurvedAnimation(parent: _animationController, curve: Curves.easeInOut);

    // 基础资料
    if (!widget.isGuest) {
      _load();
    } else {
      _animationController.forward();
    }

    // ✅ 首次进入拉取认证状态 & 监听登录态变化自动刷新
    _reloadUserVerificationStatus();
    Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      _reloadUserVerificationStatus();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  /// ✅ 只读加载：仅加载资料（用于显示），不再用 profiles/appMetadata 计算认证
  Future<void> _load() async {
    try {
      // 基础资料用于页面显示（名字/头像/时间等）
      final base = await _svc.getUserProfile();
      final map =
      base == null ? <String, dynamic>{} : Map<String, dynamic>.from(base);

      if (!mounted) return;
      setState(() {
        _profile = map;
        _loading = false;
      });
      _animationController.forward();

      if (kDebugMode) {
        debugPrint('[Profile] load: base loaded');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error loading profile: $e');
      if (!mounted) return;
      setState(() => _loading = false);
      _animationController.forward();
    }
  }

  // ✅ 仅查 user_verifications，一次性计算 _verified/_badge，并更新到状态
  Future<void> _reloadUserVerificationStatus() async {
    setState(() => _verifyLoading = true);

    final row = await _verifySvc.fetchVerificationRow(); // 仅查 user_verifications
    final user = Supabase.instance.client.auth.currentUser;

    final verified = vutils.computeIsVerified(verificationRow: row, user: user);
    final badge = vutils.computeBadgeType(verificationRow: row, user: user);

    if (!mounted) return;
    setState(() {
      _verificationRow = row;
      _verified = verified;
      _badge = badge;
      _verifyLoading = false;
    });

    if (kDebugMode) {
      debugPrint('[ProfilePage] _reloadUserVerificationStatus(): '
          'verified=$_verified badge=$_badge row=${_verificationRow?['verification_type']}');
    }
  }

  Future<void> _editNamePhone() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    try {
      final p = await ProfileService.instance.getUserProfile();
      if (p != null) {
        nameCtrl.text = (p['display_name'] ?? p['full_name'] ?? '').toString();
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
                        style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(fontSize: 16),
                  decoration: InputDecoration(
                    labelText: 'Full name',
                    labelStyle: const TextStyle(fontSize: 14),
                    prefixIcon:
                    const Icon(Icons.person_outline_rounded, size: 20),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: Theme.of(context).primaryColor, width: 2),
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
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: Theme.of(context).primaryColor, width: 2),
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12)),
                      child:
                      const Text('Cancel', style: TextStyle(fontSize: 15)),
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 28, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Save',
                            style:
                            TextStyle(fontSize: 15, color: Colors.white)),
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
          fullName:
          nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
          phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Profile updated successfully',
                    style: TextStyle(fontSize: 14)),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                    child: Text('Update failed: $e',
                        style: const TextStyle(fontSize: 14))),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }

    nameCtrl.dispose();
    phoneCtrl.dispose();
  }

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
      final path =
          '${user.id}/avatar_${DateTime.now().millisecondsSinceEpoch}.$ext';

      await Supabase.instance.client.storage
          .from('avatars')
          .uploadBinary(path, bytes, fileOptions: const FileOptions(upsert: true));

      final publicUrl =
      Supabase.instance.client.storage.from('avatars').getPublicUrl(path);
      await ProfileService.instance.updateUserProfile(avatarUrl: publicUrl);

      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.check_circle_rounded,
                  color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('Avatar updated successfully',
                  style: TextStyle(fontSize: 14)),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ),
      );
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
                  child: Text('Upload failed: $e',
                      style: const TextStyle(fontSize: 14))),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final languageProvider = Provider.of<LanguageProvider>(context);

    final media = MediaQuery.of(context);
    final clamp = media.copyWith(textScaler: const TextScaler.linear(1.0));

    // Guest user interface
    if (widget.isGuest) {
      return MediaQuery(
        data: clamp,
        child: Scaffold(
          backgroundColor: const Color(0xFFF8F9FA),
          body: ScrollConfiguration(
            behavior: const ScrollBehavior(),
            child: CustomScrollView(
              slivers: [
                const SliverAppBar(
                  backgroundColor: Color(0xFF2563EB),
                  pinned: false,
                  elevation: 0,
                  toolbarHeight: 0,
                ),
                SliverToBoxAdapter(
                  child: _buildEnhancedHeader(
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
        data: clamp,
        child: const Scaffold(
          backgroundColor: Color(0xFFF8F9FA),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(strokeWidth: 3)),
                SizedBox(height: 16),
                Text('Loading profile...',
                    style: TextStyle(color: Color(0xFF666666), fontSize: 15)),
              ],
            ),
          ),
        ),
      );
    }

    final fullName = (_profile?['full_name'] ?? 'User').toString();
    final phone = (_profile?['phone'] ?? '').toString();
    final email =
    phone.isNotEmpty ? phone : (_profile?['email'] ?? '').toString();
    final avatarUrl = (_profile?['avatar_url'] ?? '') as String?;
    final memberSince = _profile?['created_at']?.toString();
    String? memberSinceText;
    if (memberSince != null && memberSince.isNotEmpty) {
      final cut =
      memberSince.length >= 10 ? memberSince.substring(0, 10) : memberSince;
      memberSinceText = cut;
    }

    return MediaQuery(
      data: clamp,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        body: Stack(
          children: [
            ScrollConfiguration(
              behavior: const ScrollBehavior(),
              child: CustomScrollView(
                slivers: [
                  const SliverAppBar(
                    backgroundColor: Color(0xFF2563EB),
                    pinned: false,
                    elevation: 0,
                    toolbarHeight: 0,
                  ),
                  SliverToBoxAdapter(
                    child: _buildEnhancedHeader(
                      isGuest: false,
                      name: fullName,
                      email: email,
                      avatarUrl:
                      (avatarUrl != null && avatarUrl.isNotEmpty)
                          ? avatarUrl
                          : null,
                      memberSince: memberSinceText,
                      // ✅ 头像叠加徽章：仅在 verified 时传入，否则传 none（未验证就不显示）
                      verificationType:
                      _verified ? _badge : vt.VerificationBadgeType.none,
                    ),
                  ),
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
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF6B7280),
                                    letterSpacing: 0.5)),
                            const SizedBox(height: 14),
                            _ProfileOptionEnhanced(
                              icon: Icons.edit_rounded,
                              title: l10n.editProfile,
                              color: Colors.blue,
                              onTap: _editNamePhone,
                            ),
                            const SizedBox(height: 14),

                            // ✅ 认证入口：图标/文案绑定 _verified；点击进入验证并返回后【总是】刷新
                            _VerificationTileCard(
                              isVerified: _verified,
                              isLoading: _verifyLoading, // ✅ 新增：刷新时给出反馈
                              onTap: () async {
                                await Navigator.of(context).push<bool>(
                                  MaterialPageRoute(
                                      builder: (_) => const VerificationPage()),
                                );
                                // ✅ 无条件刷新（避免验证页未 pop(true) 的情况）
                                await _reloadUserVerificationStatus();
                              },
                            ),

                            const SizedBox(height: 28),
                            const Text('Rewards & Activities',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF6B7280),
                                    letterSpacing: 0.5)),
                            const SizedBox(height: 14),
                            const MyRewardsTile(),
                            const SizedBox(height: 14),

                            _ProfileOptionEnhanced(
                              icon: Icons.inventory_2_rounded,
                              title: l10n.myListings,
                              color: Colors.indigo,
                              onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                      const MyListingsPage())),
                            ),
                            const SizedBox(height: 14),
                            _ProfileOptionEnhanced(
                              icon: Icons.favorite_rounded,
                              title: l10n.wishlist,
                              color: Colors.pink,
                              onTap: () {
                                final user = Supabase
                                    .instance.client.auth.currentUser;
                                if (user == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Please sign in to view Wishlist')),
                                  );
                                  return;
                                }
                                Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) =>
                                        const WishlistPage()));
                              },
                            ),
                            const SizedBox(height: 14),

                            _ProfileOptionEnhanced(
                              icon: Icons.person_add_alt_1_rounded,
                              title: 'Invite Friends',
                              subtitle: 'Earn coupons by inviting friends',
                              color: Colors.orange,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                    const InviteFriendsPage()),
                              ),
                            ),
                            const SizedBox(height: 14),

                            _ProfileOptionEnhanced(
                              icon: Icons.local_activity_rounded,
                              title: 'My Coupons',
                              subtitle: 'View and manage your coupons',
                              color: Colors.purple,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => CouponManagementPage()),
                              ),
                            ),
                            const SizedBox(height: 28),
                            const Text('Support',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF6B7280),
                                    letterSpacing: 0.5)),
                            const SizedBox(height: 14),

                            // ✅ 新增：Account 入口（先到账户设置页，再含删除账号等）
                            _ProfileOptionEnhanced(
                              icon: Icons.manage_accounts,
                              title: 'Account',
                              subtitle: 'Password, devices, delete',
                              color: Colors.cyan,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const AccountSettingsPage(),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // ✅ 新增：隐私政策外链
                            _ProfileOptionEnhanced(
                              icon: Icons.privacy_tip_outlined,
                              title: 'Privacy Policy',
                              color: Colors.blueGrey,
                              onTap: () => launchUrl(
                                Uri.parse(_kPrivacyUrl),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // ✅ 新增：数据删除说明外链
                            _ProfileOptionEnhanced(
                              icon: Icons.delete_outline,
                              title: 'Data Deletion / How to delete my account',
                              color: Colors.deepOrange,
                              onTap: () => launchUrl(
                                Uri.parse(_kDeleteUrl),
                              ),
                            ),
                            const SizedBox(height: 14),

                            _ProfileOptionEnhanced(
                              icon: Icons.help_outline_rounded,
                              title: l10n.helpSupport,
                              color: Colors.teal,
                              onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => HelpSupportPage())),
                            ),
                            const SizedBox(height: 14),
                            _ProfileOptionEnhanced(
                              icon: Icons.info_outline_rounded,
                              title: l10n.about,
                              color: Colors.blueGrey,
                              onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => AboutPage())),
                            ),
                            const SizedBox(height: 28),
                            _ProfileOptionEnhanced(
                              icon: Icons.logout_rounded,
                              title: l10n.logout,
                              color: Colors.red,
                              onTap: () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                        BorderRadius.circular(18)),
                                    title: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                              color:
                                              Colors.red.withOpacity(0.1),
                                              borderRadius:
                                              BorderRadius.circular(8)),
                                          child: const Icon(
                                              Icons.logout_rounded,
                                              color: Colors.red,
                                              size: 20),
                                        ),
                                        const SizedBox(width: 12),
                                        const Text('Logout',
                                            style: TextStyle(
                                                fontSize: 18,
                                                fontWeight:
                                                FontWeight.w600)),
                                      ],
                                    ),
                                    content: const Text(
                                        'Are you sure you want to logout?',
                                        style: TextStyle(
                                            fontSize: 15, height: 1.4)),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.of(ctx).pop(false),
                                          child: Text('Cancel',
                                              style: TextStyle(
                                                  fontSize: 15,
                                                  color: Colors.grey[600]))),
                                      Container(
                                        decoration: BoxDecoration(
                                            color: Colors.red,
                                            borderRadius:
                                            BorderRadius.circular(8)),
                                        child: TextButton(
                                          onPressed: () =>
                                              Navigator.of(ctx).pop(true),
                                          child: const Text('Logout',
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 15,
                                                  fontWeight:
                                                  FontWeight.w600)),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed == true) {
                                  try {
                                    await Supabase.instance.client.auth
                                        .signOut();
                                    RewardService.clearCache();
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Row(
                                            children: [
                                              const Icon(
                                                  Icons.error_outline_rounded,
                                                  color: Colors.white,
                                                  size: 18),
                                              const SizedBox(width: 8),
                                              Text('Logout failed: $e',
                                                  style: const TextStyle(
                                                      fontSize: 14)),
                                            ],
                                          ),
                                          backgroundColor: Colors.red,
                                          behavior:
                                          SnackBarBehavior.floating,
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                              BorderRadius.circular(10)),
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
            if (_uploadingAvatar)
              Container(
                color: Colors.black54,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16)),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                            width: 36,
                            height: 36,
                            child: CircularProgressIndicator()),
                        SizedBox(height: 16),
                        Text('Uploading avatar...',
                            style: TextStyle(
                                color: Color(0xFF616161), fontSize: 15)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // 头像区域：右下角仅在 verified 时展示徽章（VerifiedAvatar 内部已处理）
  Widget _buildEnhancedHeader({
    required bool isGuest,
    required String name,
    required String email,
    String? avatarUrl,
    String? memberSince,
    vt.VerificationBadgeType verificationType = vt.VerificationBadgeType.none,
  }) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2563EB), Color(0xFF3B82F6), Color(0xFF60A5FA)],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Hero(
                tag: 'profile_avatar',
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [
                      Colors.white.withOpacity(0.9),
                      Colors.white.withOpacity(0.3)
                    ]),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 10))
                    ],
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // VerifiedAvatar 内部会根据 verificationType==none 决定是否展示角标
                      VerifiedAvatar(
                        avatarUrl: avatarUrl,
                        radius: 45,
                        verificationType: verificationType,
                        onTap: !isGuest ? _uploadAvatarSimple : null,
                        defaultIcon:
                        isGuest ? Icons.person_outline : Icons.person,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  shadows: [
                    Shadow(
                        offset: Offset(0, 2),
                        blurRadius: 4,
                        color: Color(0x40000000))
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(24),
                  border:
                  Border.all(color: Colors.white.withOpacity(0.3), width: 1),
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
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              if (!isGuest && memberSince != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.calendar_today_outlined,
                          size: 12, color: Colors.white),
                      SizedBox(width: 4),
                      Text('Member since ',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------------- Verification Tile（精简版：灰/绿 + chevron） ---------------- */
class _VerificationTileCard extends StatelessWidget {
  final bool isVerified;
  final bool isLoading; // ✅ 新增：刷新中的可视反馈
  final VoidCallback? onTap;

  const _VerificationTileCard({
    required this.isVerified,
    required this.isLoading, // ✅ 新增
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color badgeColor = isVerified ? Colors.green : Colors.grey;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          // 与其它通用项保持一致的内边距与阴影
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // ✅ 左侧与其它项完全一致的“彩色圆角方块”
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.verified, color: badgeColor, size: 26),
              ),
              const SizedBox(width: 18),
              // 文案
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isVerified ? 'Verified' : 'Verification',
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text(isVerified ? 'Status: Verified' : 'Status: Not verified',
                        style:
                        TextStyle(fontSize: 14, color: Colors.grey[600])),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // 右侧与其它项统一：加载圈/小三角
              isLoading
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : Icon(Icons.arrow_forward_ios,
                  size: 18, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------------- 通用列表项（其余项仍用你的卡片样式；不再渲染任何小徽章） ---------------- */
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w600)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(subtitle!,
                          style:
                          TextStyle(fontSize: 14, color: Colors.grey[600])),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.arrow_forward_ios,
                  size: 18, color: Colors.grey[400]),
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
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => HelpSupportPage())),
        ),
        const SizedBox(height: 12),
        _ProfileOptionEnhanced(
          icon: Icons.info_outline_rounded,
          title: l10n.about,
          color: Colors.indigo,
          onTap: () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => AboutPage())),
        ),
      ],
    );
  }
}

/* ---------------- Help & Support Page ---------------- */
class HelpSupportPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(l10n.helpSupport),
        backgroundColor: const Color(0xFF2563EB),
        elevation: 0,
      ),
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
                boxShadow: [
                  BoxShadow(
                      color: Colors.blue.withOpacity(0.3),
                      blurRadius: 24,
                      offset: const Offset(0, 12))
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
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.9), fontSize: 15)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('Contact Information',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[800])),
            const SizedBox(height: 14),
            _buildContactCard(
              icon: Icons.email_outlined,
              title: 'Email Support',
              subtitle: 'swaply@swaply.cc',
              color: Colors.blue,
              onTap: () =>
                  launchUrl(Uri(scheme: 'mailto', path: 'swaply@swaply.cc')),
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
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[800])),
                      const SizedBox(height: 3),
                      Text(subtitle,
                          style:
                          TextStyle(fontSize: 14, color: Colors.grey[600])),
                    ]),
              ),
              if (onTap != null)
                Icon(Icons.arrow_forward_ios,
                    size: 16, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------------- About Page ---------------- */
class AboutPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('About'),
        backgroundColor: const Color(0xFF2563EB),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 4))
                ],
              ),
              child: Column(
                children: const [
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
                    style: TextStyle(
                        fontSize: 15,
                        color: Color(0xFF6B7280),
                        height: 1.5),
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
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 4))
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.copyright_rounded,
                      size: 18, color: Colors.grey[600]),
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
}
