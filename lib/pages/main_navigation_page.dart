// lib/pages/main_navigation_page.dart

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:swaply/core/l10n/app_localizations.dart';

// 页面 & 服务（已存在的先导入；不存在的我用占位组件临时顶上）
import 'package:swaply/pages/home_page.dart' as swaply;
import 'package:swaply/pages/sell_form_page.dart';
import 'package:swaply/pages/profile_page.dart';
import 'package:swaply/pages/coupon_management_page.dart';
import 'package:swaply/services/notification_service.dart';

// ---------------- MainNavigationPage ----------------

class MainNavigationPage extends StatefulWidget {
  final bool isGuest;
  const MainNavigationPage({Key? key, this.isGuest = false}) : super(key: key);
  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

// 统一 Primary Blue
const Color _PRIMARY_BLUE = Color(0xFF1877F2);

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
          if (mounted) _checkAndShowWelcomeGift();
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

  void _showWelcomeGiftDialog() {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.w)),
        title: Text(l10n.welcomeGiftTitle),
        content: Text(l10n.welcomeGiftContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(),
            child: Text(l10n.later),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dCtx).pop();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => CouponManagementPage()),
              );
            },
            child: Text(l10n.viewCoupons),
          ),
        ],
      ),
    );
  }

  Future<void> _loadNotificationCount() async {
    final isGuest =
        Supabase.instance.client.auth.currentSession == null; // 当前访客态
    if (!isGuest) {
      try {
        final count = await NotificationService.getUnreadNotificationsCount();
        if (mounted) setState(() => _notificationCount = count);
      } catch (e) {
        if (kDebugMode) {}
      }
    }
  }

  // ✅ Android 物理返回：Tab 内回退 -> 切回首页 -> 确认退出
  void _onPopInvokedWithResult(bool didPop, Object? result) async {
    if (didPop) return;

    if (_selectedIndex != 0) {
      if (mounted) setState(() => _selectedIndex = 0);
      return;
    }

    if (Platform.isAndroid) {
      final ok = await _confirmExit(context);
      if (ok == true) {
        SystemNavigator.pop(); // 退出到后台
      }
    }
  }

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
      builder: (BuildContext dCtx) {
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
              onPressed: () => Navigator.of(dCtx).pop(),
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
                  Navigator.of(dCtx)
                      .pushNamedAndRemoveUntil('/welcome', (route) => false);
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

  void _navigateToHome() {
    setState(() => _selectedIndex = 0);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final List<Widget> pages = [
      const IosInsetsGuard(child: _HomeRoot()),
      IosInsetsGuard(
        child: _SavedPlaceholder(onNavigateToHome: _navigateToHome),
      ),
      IosInsetsGuard(
        child: _SellRoot(
          isGuest: Supabase.instance.client.auth.currentSession == null,
        ),
      ),
      IosInsetsGuard(
        child: _NotifPlaceholder(
          onClearBadge: _clearNotifications,
          onNotificationCountChanged: (count) {
            if (mounted) setState(() => _notificationCount = count);
          },
        ),
      ),
      IosInsetsGuard(
        child:
        _ProfileRoot(isGuest: Supabase.instance.client.auth.currentSession == null),
      ),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onPopInvokedWithResult,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: IndexedStack(index: _selectedIndex, children: pages),
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
    final bool isSelected = _selectedIndex == index;

    return GestureDetector(
      onTap: () {
        if (Supabase.instance.client.auth.currentSession == null &&
            (index == 1)) {
          _showLoginRequired(AppLocalizations.of(context)!.saveItems, context);
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
    final bool isSelected = _selectedIndex == index;

    return GestureDetector(
      onTap: () {
        if (Supabase.instance.client.auth.currentSession == null) {
          _showLoginRequired(
              AppLocalizations.of(context)!.receiveNotifications, context);
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
                border: Border.all(color: Colors.white, width: 3.w),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedRotation(
                    turns: isSelected ? 0.125 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.add_rounded, color: Colors.white, size: 22.h),
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
/* =========== ROOT WIDGETS / PLACEHOLDERS ========== */
/* ------------------------------------------------ */

class _HomeRoot extends StatelessWidget {
  const _HomeRoot();
  @override
  Widget build(BuildContext context) => const swaply.HomePage();
}

class _SavedPlaceholder extends StatelessWidget {
  final VoidCallback? onNavigateToHome;
  const _SavedPlaceholder({this.onNavigateToHome});
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Text(
          '${l10n.saved} (refactor step3)',
          style: TextStyle(fontSize: 14.sp, color: Colors.grey[600]),
        ),
      ),
    );
  }
}

class _SellRoot extends StatelessWidget {
  final bool isGuest;
  const _SellRoot({this.isGuest = false});
  @override
  Widget build(BuildContext context) => SellFormPage(isGuest: isGuest);
}

class _NotifPlaceholder extends StatelessWidget {
  final VoidCallback? onClearBadge;
  final Function(int)? onNotificationCountChanged;
  const _NotifPlaceholder({this.onClearBadge, this.onNotificationCountChanged});
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Text(
          '${l10n.notifications} (refactor step4)',
          style: TextStyle(fontSize: 14.sp, color: Colors.grey[600]),
        ),
      ),
    );
  }
}

class _ProfileRoot extends StatelessWidget {
  final bool isGuest;
  const _ProfileRoot({this.isGuest = false});
  @override
  Widget build(BuildContext context) => ProfilePage(isGuest: isGuest);
}

/// iOS 底部安全区守护：把底部留白叠加到 child 外层
class IosInsetsGuard extends StatelessWidget {
  final Widget child;
  const IosInsetsGuard({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).platform != TargetPlatform.iOS) return child;
    final bottom = MediaQuery.of(context).padding.bottom;
    if (bottom <= 0) return child;
    return Padding(padding: EdgeInsets.only(bottom: bottom), child: child);
  }
}

/// 临时 UTF-8 乱码兜底（真实修复在你的工具函数里）
String _fixUtf8Mojibake(String s) => s;
