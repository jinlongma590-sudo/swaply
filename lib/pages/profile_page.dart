// lib/pages/profile_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// —— 你项目里的依赖（根据你当前代码确定这些是用到的）——
import 'package:swaply/router/safe_navigator.dart';
import 'package:swaply/models/verification_types.dart' as vt;

import 'package:swaply/services/profile_service.dart';
import 'package:swaply/services/email_verification_service.dart';
import 'package:swaply/services/reward_service.dart';
import 'package:swaply/utils/verification_utils.dart' as vutils;

import 'package:swaply/widgets/verified_avatar.dart';
import 'package:swaply/widgets/verification_badge.dart' as vb;
import 'package:swaply/widgets/verification_badge_mini.dart';
import 'package:swaply/widgets/my_rewards_tile.dart';

import 'package:swaply/pages/my_listings_page.dart';
import 'package:swaply/pages/wishlist_page.dart';
import 'package:swaply/pages/invite_friends_page.dart';
import 'package:swaply/pages/coupon_management_page.dart';
import 'package:swaply/pages/account_settings_page.dart';
import 'package:swaply/pages/verification_page.dart';
// ==== required after moving ProfilePage out of main.dart ====
import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode; // for kDebugMode
import 'package:provider/provider.dart';                  // for Provider<T>

// 临时从 main.dart 引用本地化与语言 Provider（后面再抽到独立文件更优）
import 'package:swaply/core/l10n/app_localizations.dart';
import 'package:swaply/providers/language_provider.dart'; // 如果你有这个文件

// ✅ 这些常量在 main.dart 里用过；为避免循环依赖，这里先内联一份
const _kPrivacyUrl = 'https://www.swaply.cc/privacy';
const _kDeleteUrl  = 'https://www.swaply.cc/delete';

// ✅ 兜底版 l10n（避免从 main.dart 引 AppLocalizations 造成循环依赖）
//    这样你文件里原本的 l10n.xxx 写法无需改动，只把 “获取 l10n 的那一行” 改成：
//      final l10n = const _L10n();
//    后面我会告诉你改哪一行。
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
/* ---------------- Profile Page 涓汉璧勬枡椤?---------------- */
class ProfilePage extends StatefulWidget {
  final bool isGuest;
  const ProfilePage({Key? key, this.isGuest = false}) : super(key: key);

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
  bool _loading = true;

  /// 鍩虹璧勬枡锛堟樉绀哄悕/澶村儚/鏃堕棿绛夛級
  Map<String, dynamic>? _profile;

  /// 鍙鐨?profiles 琛岋紙浠呭惈 verification_type 绛夛級
  Map<String, dynamic>? _profileRow;

  final _svc = ProfileService();

  // 鉁?鏂板锛氳璇佹湇鍔′笌鐘舵€侊紙浠呯湅 user_verifications锛?
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
    _animationController = AnimationController(
        duration: const Duration(milliseconds: 800), vsync: this);
    _fadeAnimation =
        CurvedAnimation(parent: _animationController, curve: Curves.easeInOut);

    // 鍩虹璧勬枡
    if (!widget.isGuest) {
      _load();
    } else {
      _animationController.forward();
    }

    // 鉁?棣栨杩涘叆鎷夊彇璁よ瘉鐘舵€?& 鐩戝惉鐧诲綍鎬佸彉鍖栬嚜鍔ㄥ埛鏂?
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

  /// 鉁?鍙鍔犺浇锛氫粎鍔犺浇璧勬枡锛堢敤浜庢樉绀猴級锛屼笉鍐嶇敤 profiles/appMetadata 璁＄畻璁よ瘉
  Future<void> _load() async {
    try {
      // 鍩虹璧勬枡鐢ㄤ簬椤甸潰鏄剧ず锛堝悕瀛?澶村儚/鏃堕棿绛夛級
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

  // 鉁?浠呮煡 user_verifications锛屼竴娆℃€ц绠?_verified/_badge锛屽苟鏇存柊鍒扮姸鎬?
  Future<void> _reloadUserVerificationStatus() async {
    setState(() => _verifyLoading = true);

    final row =
    await _verifySvc.fetchVerificationRow(); // 浠呮煡 user_verifications
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

    if (result == true && mounted) {
      try {
        await ProfileService.instance.updateUserProfile(
          fullName: nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
          phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
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

      await Supabase.instance.client.storage.from('avatars').uploadBinary(
          path, bytes,
          fileOptions: const FileOptions(upsert: true));

      final publicUrl =
      Supabase.instance.client.storage.from('avatars').getPublicUrl(path);
      await ProfileService.instance.updateUserProfile(avatarUrl: publicUrl);

      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
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
    final l10n = const _L10n();
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
                      // 鉁?澶村儚鍙犲姞寰界珷锛氫粎鍦?verified 鏃朵紶鍏ワ紝鍚﹀垯浼?none锛堟湭楠岃瘉灏变笉鏄剧ず锛?
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

                            // 鉁?璁よ瘉鍏ュ彛锛氬浘鏍?鏂囨缁戝畾 _verified锛涚偣鍑昏繘鍏ラ獙璇佸苟杩斿洖鍚庛€愭€绘槸銆戝埛鏂?
                            _VerificationTileCard(
                              isVerified: _verified,
                              isLoading: _verifyLoading, // 鉁?鏂板锛氬埛鏂版椂缁欏嚭鍙嶉
                              onTap: () async {
                                await SafeNavigator.push<bool>(
                                  MaterialPageRoute(
                                      builder: (_) => const VerificationPage()),
                                );
                                // 鉁?鏃犳潯浠跺埛鏂帮紙閬垮厤楠岃瘉椤垫湭 pop(true) 鐨勬儏鍐碉級
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
                                Navigator.push(
                                    context,
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
                              onTap: () => Navigator.push(
                                context,
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

                            // 鉁?鏂板锛欰ccount 鍏ュ彛锛堝厛鍒拌处鎴疯缃〉锛屽啀鍚垹闄よ处鍙风瓑锛?
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

                            // 鉁?鏂板锛氶殣绉佹斂绛栧閾?
                            _ProfileOptionEnhanced(
                              icon: Icons.privacy_tip_outlined,
                              title: 'Privacy Policy',
                              color: Colors.blueGrey,
                              onTap: () => launchUrl(
                                Uri.parse(_kPrivacyUrl),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // 鉁?鏂板锛氭暟鎹垹闄よ鏄庡閾?
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
                                          behavior: SnackBarBehavior.floating,
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

  // 澶村儚鍖哄煙锛氭湭淇敼锛堢敤浣犳彁渚涚殑鍘熷浠ｇ爜锛?
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
                      // VerifiedAvatar 鍐呴儴浼氭牴鎹?verificationType==none 鍐冲畾鏄惁灞曠ず瑙掓爣
                      VerifiedAvatar(/* ---------------- 鍏叡锛氭棤杈圭紭鍏夋檿婊氬姩 & UI 鍩哄骇 ---------------- */

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

/* ---------------- Verification Tile锛堢簿绠€鐗堬細鐏?缁?+ chevron锛?---------------- */
class _VerificationTileCard extends StatelessWidget {
  final bool isVerified;
  final bool isLoading; // 鉁?鏂板锛氬埛鏂颁腑鐨勫彲瑙嗗弽棣?
  final VoidCallback? onTap;

  const _VerificationTileCard({
    required this.isVerified,
    required this.isLoading, // 鉁?鏂板
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
          // 涓庡叾瀹冮€氱敤椤逛繚鎸佷竴鑷寸殑鍐呰竟璺濅笌闃村奖
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
              // 鉁?宸︿晶涓庡叾瀹冮」瀹屽叏涓€鑷寸殑鈥滃僵鑹插渾瑙掓柟鍧椻€?
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.verified, color: badgeColor, size: 26),
              ),
              const SizedBox(width: 18),
              // 鏂囨
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
              // 鍙充晶涓庡叾瀹冮」缁熶竴锛氬姞杞藉湀/灏忎笁瑙?
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

/* ---------------- 閫氱敤鍒楄〃椤癸紙鍏朵綑椤逛粛鐢ㄤ綘鐨勫崱鐗囨牱寮忥紱涓嶅啀娓叉煋浠讳何灏忓窘绔狶級 ---------------- */
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

/* ---------------- Guest 閫夐」锛堢畝鐗堬級 ---------------- */
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
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => AboutPage())),
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
