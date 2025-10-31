// lib/pages/seller_profile_page.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:swaply/models/verification_types.dart' as vt;
import 'package:swaply/pages/product_detail_page.dart';
import 'package:swaply/widgets/verified_avatar.dart';

// 新增：改为通过 RPC 读取认证状态
import 'package:swaply/services/email_verification_service.dart';

class SellerProfileViewPage extends StatefulWidget {
  final String sellerId;
  final Map<String, dynamic>? initialSellerData;

  /// 可选：从上个页面传入的初始徽章（用于首屏先显示，随后以 RPC 结果覆盖）
  final vt.VerificationBadgeType verificationType;

  const SellerProfileViewPage({
    Key? key,
    required this.sellerId,
    this.initialSellerData,
    this.verificationType = vt.VerificationBadgeType.none,
  }) : super(key: key);

  @override
  State<SellerProfileViewPage> createState() => _SellerProfileViewPageState();
}

class _SellerProfileViewPageState extends State<SellerProfileViewPage> {
  static const Color _primaryBlue = Color(0xFF1877F2);
  static const Color _successGreen = Color(0xFF4CAF50);

  final _verifySvc = EmailVerificationService();

  bool _loading = true;
  Map<String, dynamic>? _fullSellerInfo;
  List<Map<String, dynamic>> _sellerListings = [];
  int _totalListings = 0;

  /// 新方案状态（来自公开 RPC）
  bool _isVerified = false;
  Map<String, dynamic>? _verifyRow;

  @override
  void initState() {
    super.initState();

    // 若有上层传来的初始徽章，先用它决定首屏是否显示徽章；随后以 RPC 结果为准
    _isVerified = widget.verificationType != vt.VerificationBadgeType.none;

    if (widget.initialSellerData != null) {
      _fullSellerInfo = widget.initialSellerData;
    }

    _loadSellerData();

    // 首帧后拉取认证状态（公开 RPC）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSellerVerifyPublic();
    });
  }

  /// 仅负责拉取「认证展示字段」并计算是否认证（不依赖旧工具）
  Future<void> _loadSellerVerifyPublic() async {
    final sellerUserId = widget.sellerId; // 资料页接收到的卖家 user_id
    if (sellerUserId.isEmpty) return;

    try {
      final row = await _verifySvc.fetchPublicVerification(sellerUserId);

      // ignore: avoid_print
      print('[SellerProfile] public verify row = $row');

      final verified = (row?['email_verified_at'] != null) ||
          (row?['badge_type'] == 'verified');

      if (!mounted) return; // 避免 setState after dispose
      setState(() {
        _verifyRow = row;
        _isVerified = verified;
      });
    } catch (e) {
      if (kDebugMode) {
        print('[_loadSellerVerifyPublic] error: $e');
      }
    }
  }

  Future<void> _loadSellerData() async {
    try {
      setState(() => _loading = true);

      if (_fullSellerInfo == null) {
        // ⚠️ 不再 select 旧的认证字段：只拉展示所需
        final profileResponse = await Supabase.instance.client
            .from('profiles')
            .select('id, full_name, avatar_url, created_at')
            .eq('id', widget.sellerId)
            .maybeSingle();

        if (profileResponse != null) {
          _fullSellerInfo = Map<String, dynamic>.from(profileResponse);
        }
      }

      final listingsResponse = await Supabase.instance.client
          .from('listings')
          .select(
              'id, title, price, images, image_urls, city, created_at, views_count')
          .eq('user_id', widget.sellerId)
          .order('created_at', ascending: false)
          .limit(50);

      if (listingsResponse is List) {
        _sellerListings = List<Map<String, dynamic>>.from(
          listingsResponse.map((e) => Map<String, dynamic>.from(e)),
        );
        _totalListings = _sellerListings.length;
      }

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (kDebugMode) print('Error loading seller data: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  String _getMemberSince() {
    final createdAt = _fullSellerInfo?['created_at']?.toString();
    if (createdAt == null || createdAt.isEmpty) return '';
    try {
      final dateTime = DateTime.parse(createdAt);
      final difference = DateTime.now().difference(dateTime);
      if (difference.inDays > 365) {
        final years = (difference.inDays / 365).floor();
        return '$years year${years > 1 ? 's' : ''}';
      } else if (difference.inDays > 30) {
        final months = (difference.inDays / 30).floor();
        return '$months month${months > 1 ? 's' : ''}';
      } else {
        return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''}';
      }
    } catch (_) {
      return '';
    }
  }

  Color _getVerificationColor(vt.VerificationBadgeType type) {
    switch (type) {
      case vt.VerificationBadgeType.none:
        return Colors.grey;
      case vt.VerificationBadgeType.verified:
      case vt.VerificationBadgeType.blue:
        return _successGreen;
      case vt.VerificationBadgeType.official:
      case vt.VerificationBadgeType.government:
        return _primaryBlue;
      case vt.VerificationBadgeType.premium:
      case vt.VerificationBadgeType.gold:
      case vt.VerificationBadgeType.business:
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.grey[800]),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final sellerName = _fullSellerInfo?['full_name'] ?? 'Seller';
    final avatarUrl = _fullSellerInfo?['avatar_url'];
    final memberSince = _getMemberSince();

    // 统一把布尔认证态映射为头像需要的枚举
    final badgeType = _isVerified
        ? vt.VerificationBadgeType.verified
        : vt.VerificationBadgeType.none;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200.h,
            pinned: true,
            backgroundColor: _primaryBlue,
            flexibleSpace: LayoutBuilder(
              builder: (context, constraints) {
                return Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [_primaryBlue, _primaryBlue.withOpacity(0.8)],
                    ),
                  ),
                  child: SafeArea(
                    top: true,
                    bottom: false,
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: 8.h),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(height: 28.h),
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.white, width: 3),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: VerifiedAvatar(
                                avatarUrl: avatarUrl,
                                radius: 40.r,
                                verificationType:
                                    badgeType, // ✅ 使用 _isVerified 映射
                                defaultIcon: Icons.person,
                              ),
                            ),
                            SizedBox(height: 10.h),
                            Text(
                              sellerName,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20.sp,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 4.h),
                            if (memberSince.isNotEmpty)
                              Container(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 12.w, vertical: 4.h),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12.r),
                                ),
                                child: Text(
                                  'Member for $memberSince',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11.sp,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // 统计卡片
          SliverToBoxAdapter(
            child: Container(
              margin: EdgeInsets.all(12.w),
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12.r),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8.r,
                    offset: Offset(0, 2.h),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem(
                    icon: Icons.inventory_2_outlined,
                    label: 'Listings',
                    value: _totalListings.toString(),
                  ),
                  if (_isVerified)
                    _buildStatItem(
                      icon: Icons.verified_outlined,
                      label: 'Status',
                      value: 'Verified',
                      color: _getVerificationColor(badgeType),
                    ),
                ],
              ),
            ),
          ),

          // 标题
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
              child: Text(
                'Seller\'s Listings ($_totalListings)',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
            ),
          ),

          // 列表/网格
          if (_sellerListings.isEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 200.h,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.inventory_2_outlined,
                        size: 48.sp, color: Colors.grey[400]),
                    SizedBox(height: 8.h),
                    Text('No listings yet',
                        style: TextStyle(
                            color: Colors.grey[600], fontSize: 14.sp)),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.all(12.w),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.75,
                  crossAxisSpacing: 12.w,
                  mainAxisSpacing: 12.w,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final listing = _sellerListings[index];
                    return _buildListingCard(listing);
                  },
                  childCount: _sellerListings.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    Color? color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color ?? Colors.grey[700], size: 24.sp),
        SizedBox(height: 4.h),
        Text(
          value,
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.bold,
            color: color ?? Colors.grey[800],
          ),
        ),
        Text(label, style: TextStyle(fontSize: 11.sp, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildListingCard(Map<String, dynamic> listing) {
    final images = listing['images'] ?? listing['image_urls'] ?? [];
    final imageUrl =
        images is List && images.isNotEmpty ? images[0].toString() : '';

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProductDetailPage(
              productId: listing['id'].toString(),
              productData: listing,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12.r),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 6.r,
              offset: Offset(0, 2.h),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 图片
            Container(
              height: 120.h,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.vertical(top: Radius.circular(12.r)),
                color: Colors.grey[200],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.vertical(top: Radius.circular(12.r)),
                child: imageUrl.isNotEmpty
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorBuilder: (context, error, stackTrace) {
                          return Center(
                            child: Icon(Icons.image,
                                size: 32.sp, color: Colors.grey[400]),
                          );
                        },
                      )
                    : Center(
                        child: Icon(Icons.image,
                            size: 32.sp, color: Colors.grey[400]),
                      ),
              ),
            ),
            // 信息
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(10.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      listing['title']?.toString() ?? 'Untitled',
                      style: TextStyle(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          listing['price']?.toString() ?? r'$0',
                          style: TextStyle(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.bold,
                            color: _successGreen,
                          ),
                        ),
                        SizedBox(height: 2.h),
                        Row(
                          children: [
                            Icon(Icons.location_on_outlined,
                                size: 10.sp, color: Colors.grey[600]),
                            SizedBox(width: 2.w),
                            Expanded(
                              child: Text(
                                listing['city']?.toString() ?? 'Unknown',
                                style: TextStyle(
                                    fontSize: 10.sp, color: Colors.grey[600]),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
