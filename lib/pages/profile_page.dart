// lib/pages/profile_page.dart

import 'dart:async'; // ✅ 用于 StreamSubscription, unawaited
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:swaply/router/safe_navigator.dart';
// 鈥斺€?浣犻」鐩噷鐨勪緷璧栵紙鏍规嵁浣犲綋鍓嶄唬鐮佺‘瀹氳繖浜涙槸鐢ㄥ埌鐨勶級鈥斺€?
import 'package:swaply/router/safe_navigator.dart';
import 'package:swaply/router/root_nav.dart'; // ✅ 新增导航
import 'package:swaply/services/auth_flow_observer.dart'; // ✅ 新增 Observer
import 'package:swaply/models/verification_types.dart' as vt;

import 'package:swaply/services/profile_service.dart';
import 'package:swaply/services/email_verification_service.dart';
import 'package:swaply/services/reward_service.dart';
import 'package:swaply/utils/verification_utils.dart' as vutils;

import 'package:swaply/widgets/verified_avatar.dart';
import 'package:swaply/widgets/my_rewards_tile.dart';

import 'package:swaply/pages/my_listings_page.dart';
import 'package:swaply/pages/wishlist_page.dart';
import 'package:swaply/pages/invite_friends_page.dart';
import 'package:swaply/pages/coupon_management_page.dart';
import 'package:swaply/pages/account_settings_page.dart';
import 'package:swaply/pages/verification_page.dart';
// ==== required after moving ProfilePage out of main.dart ====
import 'package:flutter/foundation.dart' show kDebugMode; // for kDebugMode
import 'package:provider/provider.dart';                  // for Provider<T>

// 涓存椂浠?main.dart 寮曠敤鏈湴鍖栦笌璇█ Provider锛堝悗闈㈠啀鎶藉埌鐙珛鏂囦欢鏇翠紭锛?
import 'package:swaply/core/l10n/app_localizations.dart';
import 'package:swaply/providers/language_provider.dart'; // 濡傛灉浣犳湁杩欎釜鏂囦欢

// 鉁?杩欎簺甯搁噺鍦?main.dart 閲岀敤杩囷紱涓洪伩鍏嶅惊鐜緷璧栵紝杩欓噷鍏堝唴鑱斾竴浠?
const _kPrivacyUrl = 'https://www.swaply.cc/privacy';
const _kDeleteUrl  = 'https://www.swaply.cc/delete';

// 鉁?鍏滃簳鐗?l10n锛堥伩鍏嶄粠 main.dart 寮?AppLocalizations 閫犳垚寰幆渚濊禆锛?
class _L10n {
  const _L10n();
  String get helpSupport => 'Help & Support';
  String get about => 'About';
  String get guestUser => 'Guest user';
  String get browseWithoutAccount => 'Browsing without an account';
  String get myListings => 'My Listings';
  String get wishlist => 'Wishlist';
  String get editProfile => 'Edit Profile';
  String get logout => 'Logout';
}

/* ---------------- Profile Page 娑擃亙姹夌挧鍕灐妞?---------------- */
class ProfilePage extends StatefulWidget {
  final bool isGuest;
  const ProfilePage({super.key, this.isGuest = false});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
  // ✅ A. 标记销毁状态
  bool _dead = false;
  // ✅ 订阅句柄，用于在 dispose 时取消
  StreamSubscription<AuthState>? _authSubscription;

  bool _loading = true;

  /// 閸╄櫣顢呯挧鍕灐閿涘牊妯夌粈鍝勬倳/婢舵潙鍎?閺冨爼妫跨粵澶涚礆
  Map<String, dynamic>? _profile;

  /// 閸欘亣顕伴惃?profiles 鐞涘矉绱欐禒鍛儓 verification_type 缁涘绱?
  Map<String, dynamic>? _profileRow;

  final _svc = ProfileService();

  // 閴?閺傛澘顤冮敍姘愁吇鐠囦焦婀囬崝鈥茬瑢閻樿埖鈧緤绱欐禒鍛箙 user_verifications閿?
  final _verifySvc = EmailVerificationService();
  bool _verified = false;
  vt.VerificationBadgeType _badge = vt.VerificationBadgeType.none;
  Map<String, dynamic>? _verificationRow;
  bool _verifyLoading = false;

  bool _uploadingAvatar = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // ✅ B. 安全 setState 包装 (State after dispose 护栏)
  void _safeSetState(VoidCallback fn) {
    if (!mounted || _dead) return;
    setState(fn);
  }

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
        duration: const Duration(milliseconds: 800), vsync: this);
    _fadeAnimation =
        CurvedAnimation(parent: _animationController, curve: Curves.easeInOut);

    // 閸╄櫣顢呯挧鍕灐
    if (!widget.isGuest) {
      _load();
    } else {
      _animationController.forward();
    }

    // 閴?妫ｆ牗顐兼潻娑樺弳閹峰褰囩拋銈堢槈閻樿埖鈧?& 閻╂垵鎯夐惂璇茬秿閹礁褰夐崠鏍殰閸斻劌鍩涢弬?
    _reloadUserVerificationStatus();
    // ✅ 记录订阅，防止内存泄漏
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      // 回调里也要防止已销毁
      if (!mounted || _dead) return;
      _reloadUserVerificationStatus();
    });
  }

  // ✅ D. dispose 里彻底清理
  @override
  void dispose() {
    _dead = true; // 标记死亡
    _authSubscription?.cancel(); // 取消监听
    _animationController.dispose();
    super.dispose();
  }

  /// 閴?閸欘亣顕伴崝鐘烘祰閿涙矮绮庨崝鐘烘祰鐠у嫭鏋￠敍鍫㈡暏娴滃孩妯夌粈鐚寸礆閿涘奔绗夐崘宥囨暏 profiles/appMetadata 鐠侊紕鐣荤拋銈堢槈
  Future<void> _load() async {
    try {
      // 閸╄櫣顢呯挧鍕灐閻劋绨い鐢告桨閺勫墽銇氶敍鍫濇倳鐎?婢舵潙鍎?閺冨爼妫跨粵澶涚礆
      final base = await _svc.getUserProfile();

      // ✅ C. await 后立即判断
      if (!mounted || _dead) return;

      final map =
      base == null ? <String, dynamic>{} : Map<String, dynamic>.from(base);

      // ✅ B. 使用 _safeSetState
      _safeSetState(() {
        _profile = map;
        _loading = false;
      });
      _animationController.forward();

      if (kDebugMode) {
        debugPrint('[Profile] load: base loaded');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error loading profile: $e');
      if (!mounted || _dead) return;
      _safeSetState(() => _loading = false);
      _animationController.forward();
    }
  }

  // 閴?娴犲懏鐓?user_verifications閿涘奔绔村▎鈩冣偓褑顓哥粻?_verified/_badge閿涘苯鑻熼弴瀛樻煀閸掓壆濮搁幀?
  Future<void> _reloadUserVerificationStatus() async {
    _safeSetState(() => _verifyLoading = true);

    final row = await _verifySvc.fetchVerificationRow(); // 娴犲懏鐓?user_verifications

    // ✅ C. await 后立即判断
    if (!mounted || _dead) return;

    final user = Supabase.instance.client.auth.currentUser;

    final verified = vutils.computeIsVerified(verificationRow: row, user: user);
    final badge = vutils.computeBadgeType(verificationRow: row, user: user);

    // ✅ B. 使用 _safeSetState
    _safeSetState(() {
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
      // ✅ await 后判断
      if (!mounted || _dead) {
        nameCtrl.dispose();
        phoneCtrl.dispose();
        return;
      }

      if (p != null) {
        nameCtrl.text = (p['display_name'] ?? p['full_name'] ?? '').toString();
        phoneCtrl.text = (p['phone'] ?? '').toString();
      }
    } catch (_) {}

    if (!mounted || _dead) {
      nameCtrl.dispose();
      phoneCtrl.dispose();
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return Dialog(
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w600)),
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

    // ✅ 这里也要判断
    if (result == true && mounted && !_dead) {
      try {
        await ProfileService.instance.updateUserProfile(
          fullName: nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
          phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
        );

        if (!mounted || _dead) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
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
        if (!mounted || _dead) return;
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
    if (!mounted || _dead) return;
    _safeSetState(() => _uploadingAvatar = true);

    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );

      // await 后判断
      if (!mounted || _dead) return;
      if (image == null) return;

      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final bytes = await File(image.path).readAsBytes();
      // await 后判断
      if (!mounted || _dead) return;

      final ext = image.path.split('.').last;
      final path =
          '${user.id}/avatar_${DateTime.now().millisecondsSinceEpoch}.$ext';

      await Supabase.instance.client.storage.from('avatars').uploadBinary(
          path, bytes,
          fileOptions: const FileOptions(upsert: true));

      // await 后判断
      if (!mounted || _dead) return;

      final publicUrl =
      Supabase.instance.client.storage.from('avatars').getPublicUrl(path);
      await ProfileService.instance.updateUserProfile(avatarUrl: publicUrl);

      // await 后判断
      if (!mounted || _dead) return;

      await _load();

      if (!mounted || _dead) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
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
      if (!mounted || _dead) return;
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
      _safeSetState(() => _uploadingAvatar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const l10n = _L10n();
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
        extendBody: true,
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
                      avatarUrl: (avatarUrl != null && avatarUrl.isNotEmpty)
                          ? avatarUrl
                          : null,
                      memberSince: memberSinceText,
                      // 閴?婢舵潙鍎氶崣鐘插瀵扮晫鐝烽敍姘矌閸?verified 閺冩湹绱堕崗銉礉閸氾箑鍨导?none閿涘牊婀宀冪槈鐏忓彉绗夐弰鍓с仛閿?
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

                            // 閴?鐠併倛鐦夐崗銉ュ經閿涙艾娴橀弽?閺傚洦顢嶇紒鎴濈暰 _verified閿涙稓鍋ｉ崙鏄忕箻閸忋儵鐛欑拠浣歌嫙鏉╂柨娲栭崥搴涒偓鎰偓缁樻Ц閵嗘垵鍩涢弬?
                            _VerificationTileCard(
                              isVerified: _verified,
                              isLoading: _verifyLoading, // 閴?閺傛澘顤冮敍姘煕閺傜増妞傜紒娆忓毉閸欏秹顩?
                              onTap: () async {
                                await SafeNavigator.push<bool>(
                                  MaterialPageRoute(
                                      builder: (_) => const VerificationPage()),
                                );
                                // 閴?閺冪姵娼禒璺哄煕閺傚府绱欓柆鍨帳妤犲矁鐦夋い鍨弓 pop(true) 閻ㄥ嫭鍎忛崘纰夌礆
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
                              onTap: () => SafeNavigator.push(
                                  MaterialPageRoute(
                                      builder: (_) => const MyListingsPage())),
                            ),
                            const SizedBox(height: 14),
                            _ProfileOptionEnhanced(
                              icon: Icons.favorite_rounded,
                              title: l10n.wishlist,
                              color: Colors.pink,
                              onTap: () {
                                final user =
                                    Supabase.instance.client.auth.currentUser;
                                if (user == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Please sign in to view Wishlist')),
                                  );
                                  return;
                                }
                                SafeNavigator.push(
                                    MaterialPageRoute(
                                        builder: (_) => const WishlistPage()));
                              },
                            ),
                            const SizedBox(height: 14),

                            _ProfileOptionEnhanced(
                              icon: Icons.person_add_alt_1_rounded,
                              title: 'Invite Friends',
                              subtitle: 'Earn coupons by inviting friends',
                              color: Colors.orange,
                              onTap: () => SafeNavigator.push(
                                MaterialPageRoute(
                                    builder: (_) => const InviteFriendsPage()),
                              ),
                            ),
                            const SizedBox(height: 14),

                            _ProfileOptionEnhanced(
                              icon: Icons.local_activity_rounded,
                              title: 'My Coupons',
                              subtitle: 'View and manage your coupons',
                              color: Colors.purple,
                              onTap: () => SafeNavigator.push(
                                MaterialPageRoute(
                                    builder: (_) =>
                                    const CouponManagementPage()),
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

                            // 閴?閺傛澘顤冮敍娆癱count 閸忋儱褰涢敍鍫濆帥閸掓媽澶勯幋鐤啎缂冾噣銆夐敍灞藉晙閸氼偄鍨归梽銈堝閸欓鐡戦敍?
                            _ProfileOptionEnhanced(
                              icon: Icons.manage_accounts,
                              title: 'Account',
                              subtitle: 'Password, devices, delete',
                              color: Colors.cyan,
                              onTap: () => SafeNavigator.push(
                                MaterialPageRoute(
                                  builder: (_) => const AccountSettingsPage(),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // 閴?閺傛澘顤冮敍姘舵缁変焦鏂傜粵鏍ь樆闁?
                            _ProfileOptionEnhanced(
                              icon: Icons.privacy_tip_outlined,
                              title: 'Privacy Policy',
                              color: Colors.blueGrey,
                              onTap: () => launchUrl(
                                Uri.parse(_kPrivacyUrl),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // 閴?閺傛澘顤冮敍姘殶閹诡喖鍨归梽銈堫嚛閺勫骸顦婚柧?
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
                              onTap: () => SafeNavigator.push(
                                  MaterialPageRoute(
                                      builder: (_) => const HelpSupportPage())),
                            ),
                            const SizedBox(height: 14),
                            _ProfileOptionEnhanced(
                              icon: Icons.info_outline_rounded,
                              title: l10n.about,
                              color: Colors.blueGrey,
                              onTap: () => SafeNavigator.push(
                                  MaterialPageRoute(
                                      builder: (_) => const AboutPage())),
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
                                                fontWeight: FontWeight.w600)),
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
                                                  fontWeight: FontWeight.w600)),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed == true) {
                                  // 1) 标记“手动登出”
                                  AuthFlowObserver.I.markManualSignOut();

                                  // 2) 先切换到登录页
                                  navReplaceAll('/login');

                                  // 3) 清理本地缓存
                                  RewardService.clearCache();

                                  // 4) 后台发起 signOut（无须 await，避免阻塞 UI）
                                  unawaited(Supabase.instance.client.auth
                                      .signOut(scope: SignOutScope.global));
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

  // 婢舵潙鍎氶崠鍝勭厵閿涙碍婀穱顔芥暭閿涘牏鏁ゆ担鐘冲絹娓氭稓娈戦崢鐔奉潗娴狅絿鐖滈敍?
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
                      // VerifiedAvatar 閸愬懘鍎存导姘壌閹?verificationType==none 閸愬啿鐣鹃弰顖氭儊鐏炴洜銇氱憴鎺撶垼
                      VerifiedAvatar(/* ---------------- 閸忣剙鍙￠敍姘￥鏉堝湱绱崗澶嬫濠婃艾濮?& UI 閸╁搫楠?---------------- */

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
                padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.3), width: 1),
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
                    children: [
                      const Icon(Icons.calendar_today_outlined,
                          size: 12, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(memberSince,
                          style: const TextStyle(
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

/* ---------------- Verification Tile閿涘牏绨跨粻鈧悧鍫窗閻?缂?+ chevron閿?---------------- */
class _VerificationTileCard extends StatelessWidget {
  final bool isVerified;
  final bool isLoading; // 閴?閺傛澘顤冮敍姘煕閺傞鑵戦惃鍕讲鐟欏棗寮芥＃?
  final VoidCallback? onTap;

  const _VerificationTileCard({
    required this.isVerified,
    required this.isLoading, // 閴?閺傛澘顤?
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
          // 娑撳骸鍙剧€瑰啴鈧氨鏁ゆい閫涚箽閹镐椒绔撮懛瀵告畱閸愬懓绔熺捄婵呯瑢闂冩潙濂?
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
              // 閴?瀹革缚鏅舵稉搴″従鐎瑰啴銆嶇€瑰苯鍙忔稉鈧懛瀵告畱閳ユ粌鍍甸懝鎻掓妇鐟欐帗鏌熼崸妞烩偓?
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.verified, color: badgeColor, size: 26),
              ),
              const SizedBox(width: 18),
              // 閺傚洦顢?
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isVerified ? 'Verified' : 'Verification',
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text(
                        isVerified
                            ? 'Status: Verified'
                            : 'Status: Not verified',
                        style:
                        TextStyle(fontSize: 14, color: Colors.grey[600])),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // 閸欏厖鏅舵稉搴″従鐎瑰啴銆嶇紒鐔剁閿涙艾濮炴潪钘夋箑/鐏忓繋绗佺憴?
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

/* ---------------- 闁氨鏁ら崚妤勩€冩い鐧哥礄閸忔湹缍戞い閫涚矝閻劋缍橀惃鍕幢閻楀洦鐗卞蹇ョ幢娑撳秴鍟€濞撳弶鐓嬫禒璁充綍鐏忓繐绐樼粩鐙剁礆 ---------------- */
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
              Icon(Icons.arrow_forward_ios, size: 18, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------------- Guest 闁銆嶉敍鍫㈢暆閻楀牞绱?---------------- */
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
          onTap: () => SafeNavigator.push( MaterialPageRoute(builder: (_) => const HelpSupportPage())),
        ),
        const SizedBox(height: 12),
        _ProfileOptionEnhanced(
          icon: Icons.info_outline_rounded,
          title: l10n.about,
          color: Colors.indigo,
          onTap: () => SafeNavigator.push( MaterialPageRoute(builder: (_) => const AboutPage())),
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
  const AboutPage({super.key});

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
                    style: TextStyle(
                        fontSize: 15, color: Color(0xFF6B7280), height: 1.5),
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