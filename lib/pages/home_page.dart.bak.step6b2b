import 'package:swaply/router/nav_throttler.dart';
// lib/pages/home_page.dart
// ✅ 功能：基于代码二（保留 Pub/Sub 自动刷新）
// ✅ UI：  应用代码一的“紧凑型”分类网格 UI（44.w 图标）
// ✅ 修复：将 LayoutBuilder 方案正确注入到 44.w 紧凑布局中
// ✅ 修改：Trending(Pinned) = 10, Popular(Latest) = 100, 移除 Total 限制
// ✅ [PATCH B] 登录后首帧调用欢迎弹窗（WelcomeDialogService.maybeShow）
// ✅ [IMAGE BOOST] 放大商品图：降低 childAspectRatio 到 0.66（Featured/Regular 同步），Loading 改 0.70

import 'dart:io' show Platform; // ✅ 仅用于 iOS 判断
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:swaply/pages/category_products_page.dart';
import 'package:swaply/pages/product_detail_page.dart';
import 'package:swaply/pages/search_results_page.dart';
import 'package:swaply/pages/sell_form_page.dart';
import 'package:swaply/services/coupon_service.dart';
import 'package:swaply/listing_api.dart';
import 'dart:async'; // ✅ 功能保留
import 'package:swaply/services/listing_events_bus.dart'; // ✅ 功能保留
import 'package:swaply/services/welcome_dialog_service.dart'; // ✅ [PATCH B] 顶部导入
import 'package:swaply/router/safe_navigator.dart';
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _trendingKey = GlobalKey();
  final TextEditingController _searchCtrl = TextEditingController();
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  String _selectedLocation = 'All Zimbabwe';
  // 趋势数据
  List<Map<String, dynamic>> _trendingRemote = [];
  bool _loadingTrending = false;
  StreamSubscription? _listingPubSub; // ✅ 功能保留
  // Facebook亮蓝色配色方案
  static const Color _primaryBlue = Color(0xFF1877F2); // Facebook亮蓝色
  static const Color _successGreen = Color(0xFF4CAF50);
  // ===== [PATCH B] 仅触发一次欢迎弹窗 =====
  bool _welcomeChecked = false;

  static const List<String> _locations = [
    'All Zimbabwe',
    'Harare',
    'Bulawayo',
    'Chitungwiza',
    'Mutare',
    'Gweru',
    'Kwekwe',
    'Kadoma',
    'Masvingo',
    'Chinhoyi',
    'Chegutu',
    'Bindura',
    'Marondera',
    'Redcliff',
  ];
  // 仅调整了排序；文件名/ID/label 均保持不变
  static const List<Map<String, String>> _categories = [
    {"id": "trending", "icon": "trending", "label": "Trending"},
    // Hot & high-intent first
    {"id": "phones_tablets", "icon": "phones_tablets", "label": "Phones"},
    {"id": "vehicles", "icon": "vehicles", "label": "Vehicles"},
    {"id": "property", "icon": "property", "label": "Property"},
    {"id": "electronics", "icon": "electronics", "label": "Electronics"},
    {"id": "fashion", "icon": "fashion", "label": "Fashion"},
    // Services & Jobs
    {"id": "services", "icon": "services", "label": "Services"},
    {"id": "jobs", "icon": "jobs", "label": "Jobs"},
    {
      "id": "seeking_work_cvs",
      "icon": "seeking_work_cvs",
      "label": "Jobs Seeking"
    },
    // Home & daily life
    {
      "id": "home_furniture_appliances",
      "icon": "home_furniture_appliances",
      "label": "Home & Furniture"
    },
    {
      "id": "beauty_personal_care",
      "icon": "beauty_personal_care",
      "label": "Beauty & Care"
    },
    {"id": "pets", "icon": "pets", "label": "Pets"},
    {"id": "babies_kids", "icon": "babies_kids", "label": "Baby & Kids"},
    // Long-tail / nice-to-have
    {
      "id": "repair_construction",
      "icon": "repair_construction",
      "label": "Repair"
    },
    {
      "id": "leisure_activities",
      "icon": "leisure_activities",
      "label": "Leisure"
    },
    {
      "id": "food_agriculture_drinks",
      "icon": "food_agriculture_drinks",
      "label": "Food & Drinks"
    },
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _loadTrending();
    // ✅ 功能保留: 订阅事件
    _listingPubSub = ListingEventsBus.instance.stream.listen((e) {
      if (e is ListingPublishedEvent) {
        _loadTrending(bypassCache: true);
      }
    });
    // ===== [PATCH B] 登录后首帧真正触发一次欢迎弹窗 =====
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _welcomeChecked) return;
      _welcomeChecked = true;
      await WelcomeDialogService.maybeShow(context);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 保留占位：后续如需前台恢复逻辑可在此追加
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _searchCtrl.dispose();
    _fadeController.dispose();
    _listingPubSub?.cancel(); // ✅ 功能保留: 取消订阅
    super.dispose();
  }

  /* ===================== 仅 iOS：头部向下“轻微”整体位移 ===================== */
  double _iosBump(BuildContext context) {
    if (!Platform.isIOS) return 0;
    final top = MediaQuery.of(context).padding.top; // 灵动岛/状态栏安全区
    return top + 17;
  }

  /* ===================== 数据加载 ===================== */
  String _formatPrice(dynamic priceData) {
    if (priceData == null) return '';
    if (priceData is num) {
      if (priceData == 0) return 'Free';
      return '\$${priceData.toStringAsFixed(0)}';
    }
    if (priceData is String) {
      final lower = priceData.toLowerCase();
      if (lower.contains('free') || priceData == '0') return 'Free';
      final cleanPrice = priceData.replaceAll(RegExp(r'[^\d.]'), '');
      final parsedPrice = num.tryParse(cleanPrice);
      if (parsedPrice != null) {
        if (parsedPrice == 0) return 'Free';
        return '\$${parsedPrice.toStringAsFixed(0)}';
      } else {
        if (priceData.contains('\$') || priceData.contains('USD')) {
          return priceData;
        } else {
          return '\$$priceData';
        }
      }
    }
    return priceData.toString();
  }

  // ✅ [MODIFIED] 遵照指示修改：pinned=10, latest=100, 移除 total 限制
  Future<List<Map<String, dynamic>>> _fetchTrendingMixed({
    String? city,
    int pinnedLimit = 10, // ✅ 1. 改为 10
    int latestLimit = 100, // ✅ 2. 改为 100
    bool bypassCache = false,
  }) async {
    final pinnedAds = await CouponService.getTrendingPinnedAds(
      city: city,
      limit: pinnedLimit,
    );
    final list = <Map<String, dynamic>>[];
    for (final e in pinnedAds) {
      final l = (e['listings'] as Map<String, dynamic>? ?? {});
      if (l.isEmpty) continue;
      final imgs =
          (l['images'] as List?) ?? (l['image_urls'] as List?) ?? const [];
      list.add({
        'id': l['id'],
        'title': l['title'],
        'price': l['price'],
        'images': imgs,
        'city': l['city'],
        'created_at': l['created_at'],
        'pinned': true,
      });
    }
    final latest = await ListingApi.fetchListings(
      city: city,
      limit: latestLimit,
      offset: 0,
      orderBy: 'created_at',
      ascending: false,
      status: 'active',
      forceNetwork: bypassCache, // ✅ 功能保留
    );
    final seen = <String>{...list.map((x) => x['id'].toString())};
    for (final r in latest) {
      final id = r['id']?.toString();
      if (id == null || seen.contains(id)) continue;
      seen.add(id);
      final imgs =
          (r['images'] as List?) ?? (r['image_urls'] as List?) ?? const [];
      list.add({
        'id': r['id'],
        'title': r['title'],
        'price': r['price'],
        'images': imgs,
        'city': r['city'],
        'created_at': r['created_at'],
        'pinned': false,
      });
    }
    return list.toList();
  }

  // ✅ 功能保留: bypassCache
  Future<void> _loadTrending({bool bypassCache = false}) async {
    setState(() => _loadingTrending = true);
    try {
      final city =
      _selectedLocation == 'All Zimbabwe' ? null : _selectedLocation;
      final rows = await _fetchTrendingMixed(
        city: city,
        pinnedLimit: 10, // ✅ 保持与函数定义一致
        latestLimit: 100, // ✅ 保持与函数定义一致
        bypassCache: bypassCache, // ✅ 功能保留
      );
      if (mounted) {
        setState(() => _trendingRemote = rows);
        if (!bypassCache || _trendingRemote.isEmpty) {
          _fadeController.forward();
        }
      }
    } catch (e) {
      debugPrint('Error loading trending: $e');
    } finally {
      if (mounted) setState(() => _loadingTrending = false);
    }
  }

  /* ===================== 导航 ===================== */
  void _navigateToCategory(String categoryId, String categoryName) {
    if (categoryId == "trending") {
      _scrollToTrending();
    } else {
      SafeNavigator.push(
        MaterialPageRoute(
          builder: (_) => CategoryProductsPage(
            categoryId: categoryId,
            categoryName: categoryName,
          ),
        ),
      );
    }
  }

  void _navigateToProductDetail(String productId) {
    SafeNavigator.push(
      MaterialPageRoute(
          builder: (_) => ProductDetailPage(productId: productId)),
    );
  }

  void _scrollToTrending() {
    final ctx = _trendingKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  void _performSearch() {
    final keyword = _searchCtrl.text.trim();
    if (keyword.isEmpty) return;
    SafeNavigator.push(
      MaterialPageRoute(
        builder: (_) =>
            SearchResultsPage(keyword: keyword, location: _selectedLocation),
      ),
    );
  }

  // ✅【已修改】加入 await，并在 ok==true 时刷新（满足 smoke #11）
  Future<void> _onTapPost() async {
    final auth = Supabase.instance.client.auth;
    if (auth.currentUser == null) {
      final goLogin = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
          title: const Text('Login Required'),
          content: const Text('Please login to post listings.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Login')),
          ],
        ),
      );
      if (goLogin == true && mounted) {
        await SafeNavigator.pushNamed('/login');
      }
      if (Supabase.instance.client.auth.currentUser == null) return;
    }
    if (!mounted) return;
    final ok = await SafeNavigator.push(
      MaterialPageRoute(builder: (_) => const SellFormPage()),
    );
    if (ok == true && mounted) {
      await _loadTrending(bypassCache: true);
      _scrollToTrending();
      setState(() {});
    }
  }

  /* ===================== UI构建 ===================== */
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Stack(
        children: [
          ListView(
            controller: _scrollController,
            padding: EdgeInsets.zero,
            children: [
              // 紧凑头部区域
              _buildCompactHeader(),
              // 趋势区域
              _buildTrendingSection(),
              SizedBox(height: 80.h), // 底部FAB的间距
            ],
          ),
          // 紧凑FAB
          Positioned(
            right: 16.w,
            bottom: 16.h,
            child: FloatingActionButton.extended(
              heroTag: 'post-fab',
              onPressed: _onTapPost,
              backgroundColor: _primaryBlue,
              foregroundColor: Colors.white,
              elevation: 2,
              icon: Icon(Icons.add, size: 18.sp),
              label: Text(
                'Post Ad',
                style: TextStyle(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w500,
                ),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.r),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactHeader() {
    final bump = _iosBump(context); // 仅 iOS 有位移，Android 为 0
    return Stack(
      children: [
        // 简化的头部背景（加上 bump，避免白卡片顶到刘海区域）
        Container(
          height: 140.h + bump,
          color: _primaryBlue,
        ),
        Column(
          children: [
            // 顶部整体下移，避免被灵动岛遮住
            SizedBox(height: bump),
            // 紧凑Logo区域
            Container(
              padding: EdgeInsets.only(top: 35.h, bottom: 16.h),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 28.w,
                    height: 28.h,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6.r),
                    ),
                    child: Center(
                      child: Text(
                        'S',
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.bold,
                          color: _primaryBlue,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 10.w),
                  Text(
                    'Swaply',
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            // 紧凑白色卡片
            Container(
              margin: EdgeInsets.symmetric(horizontal: 12.w),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12.r),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding:
                    EdgeInsets.only(left: 16.w, top: 12.h, bottom: 10.h),
                    child: Text(
                      'What are you looking for?',
                      style: TextStyle(
                        fontSize: 16.sp,
                        color: _primaryBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // 紧凑搜索区域
                  _buildCompactSearchSection(),
                  // 紧凑分类网格 (✅ UI: 已修正为 44.w + LayoutBuilder 方案)
                  _buildCompactCategoriesGrid(),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCompactSearchSection() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Container(
              height: 36.h,
              decoration: BoxDecoration(
                border: Border.all(color: _primaryBlue, width: 1),
                borderRadius: BorderRadius.circular(6.r),
              ),
              child: DropdownButtonHideUnderline(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.w),
                  child: DropdownButton<String>(
                    value: _selectedLocation,
                    icon: Icon(Icons.arrow_drop_down,
                        color: Colors.grey[600], size: 18.sp),
                    isExpanded: true,
                    style: TextStyle(fontSize: 11.sp, color: Colors.grey[800]),
                    onChanged: (v) {
                      setState(() => _selectedLocation = v!);
                      _loadTrending();
                    },
                    items: _locations
                        .map((loc) => DropdownMenuItem(
                      value: loc,
                      child: Text(loc,
                          style: TextStyle(fontSize: 11.sp),
                          overflow: TextOverflow.ellipsis),
                    ))
                        .toList(),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: 8.w),
          Expanded(
            flex: 3,
            child: Container(
              height: 36.h,
              decoration: BoxDecoration(
                border: Border.all(color: _primaryBlue, width: 1),
                borderRadius: BorderRadius.circular(6.r),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10.w),
                      child: TextField(
                        controller: _searchCtrl,
                        textInputAction: TextInputAction.search,
                        style: TextStyle(fontSize: 12.sp),
                        decoration: InputDecoration(
                          hintText: 'Search products...',
                          hintStyle: TextStyle(
                              color: Colors.grey[500], fontSize: 11.sp),
                          border: InputBorder.none,
                          isCollapsed: true,
                        ),
                        onSubmitted: (_) => _performSearch(),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _performSearch,
                    child: Container(
                      padding: EdgeInsets.all(6.w),
                      child:
                      Icon(Icons.search, size: 18.sp, color: _primaryBlue),
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

// ✅ 修复版：精确计算网格高度，杜绝底部多余空白
  Widget _buildCompactCategoriesGrid() {
    // 锁定文字缩放，避免不同设备文字放大影响测量
    final media = MediaQuery.of(context);

    return MediaQuery(
      data: media.copyWith(textScaler: const TextScaler.linear(1.0)),
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          // ---- 布局参数（保持与你现在的视觉一致） ----
          const int crossAxisCount = 4;
          final double crossAxisSpacing = 6.w;
          final double mainAxisSpacing  = 6.h;
          const double childAspectRatio = 1.0; // 正方形卡片
          final double padHLeft  = 12.w;
          final double padHRight = 12.w;
          final double padVTop   = 12.h;
          final double padVBottom= 16.h;

          // ---- 计算网格可用宽度/单元格宽高/总高度 ----
          final double usableWidth =
              constraints.maxWidth - padHLeft - padHRight;
          final double tileW = (usableWidth -
              crossAxisSpacing * (crossAxisCount - 1)) /
              crossAxisCount;
          final double tileH = tileW / childAspectRatio;

          final int rows =
          (_categories.length / crossAxisCount).ceil(); // 16 -> 4 行
          final double gridCoreHeight =
              rows * tileH + (rows - 1) * mainAxisSpacing;
          final double gridTotalHeight =
              padVTop + gridCoreHeight + padVBottom;

          return SizedBox(
            height: gridTotalHeight, // ✅ 关键：固定测得高度
            child: GridView.builder(
              padding: EdgeInsets.fromLTRB(padHLeft, padVTop, padHRight, padVBottom),
              // ✅ 关键：关闭 primary，避免额外安全区/滚动补偿
              primary: false,
              shrinkWrap: false,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: childAspectRatio,
                crossAxisSpacing: crossAxisSpacing,
                mainAxisSpacing: mainAxisSpacing,
              ),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final cat = _categories[index];
                final isTrending = index == 0;

                // 下面保持你原来的卡片内容不变
                const double iconBox = 50.0;
                const double iconSize = 34.0;
                const double iconFallbackSize = 26.0;
                const double gap = 8.0;

                return GestureDetector(
                  onTap: () => _navigateToCategory(cat['id']!, cat['label']!),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isTrending ? Colors.orange.shade50 : Colors.grey[50],
                      borderRadius: BorderRadius.circular(10.r),
                      border: Border.all(
                        color: isTrending
                            ? Colors.orange.shade200
                            : Colors.transparent,
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: LayoutBuilder(
                      builder: (ctx, c) {
                        final double H = c.maxHeight;
                        final double labelMax = (H - iconBox - gap).clamp(0.0, 40.h);
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: iconBox,
                              height: iconBox,
                              decoration: BoxDecoration(
                                color: isTrending
                                    ? Colors.orange.shade100
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(10.r),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.03),
                                    blurRadius: 3,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: SizedBox(
                                  width: iconSize,
                                  height: iconSize,
                                  child: Image.asset(
                                    'assets/icons/${cat['icon']}.png',
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) {
                                      return Image.asset(
                                        'assets/icons/${cat['icon']}.jpg',
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) => Icon(
                                          isTrending
                                              ? Icons.local_fire_department
                                              : Icons.category,
                                          size: iconFallbackSize,
                                          color: isTrending
                                              ? Colors.orange
                                              : Colors.grey,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: gap),
                            ConstrainedBox(
                              constraints: BoxConstraints(maxHeight: labelMax),
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 2.w),
                                child: Text(
                                  cat['label']!,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.sp,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey[700],
                                    height: 1.1,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }


  Widget _buildTrendingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 紧凑趋势标题
        Padding(
          key: _trendingKey,
          padding: EdgeInsets.fromLTRB(16.w, 20.h, 16.w, 10.h),
          child: Row(
            children: [
              Text(
                'Trending',
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              SizedBox(width: 6.w),
              Icon(
                Icons.local_fire_department,
                color: Colors.orange[600],
                size: 20.sp,
              ),
            ],
          ),
        ),
        // 趋势内容
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.w),
          child:
          _loadingTrending ? _buildTrendingLoading() : _buildTrendingGrid(),
        ),
      ],
    );
  }

  // ✅ UI: 保留代码二的简化版 Loading（放大占位图：0.70）
  Widget _buildTrendingLoading() {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.70, // 🔶 原 0.85 → 放大图片的卡片比例
        crossAxisSpacing: 8.w,
        mainAxisSpacing: 8.h,
      ),
      itemCount: 6,
      itemBuilder: (_, __) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius:
                  BorderRadius.vertical(top: Radius.circular(10.r)),
                ),
                child: const Center(
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: _primaryBlue),
                ),
              ),
            ),
            SizedBox(height: 8.h),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendingGrid() {
    if (_trendingRemote.isEmpty) {
      return Container(
        height: 100.h,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.trending_up, size: 28.sp, color: Colors.grey[400]),
              SizedBox(height: 6.h),
              Text(
                'No trending items available',
                style: TextStyle(fontSize: 12.sp, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_trendingRemote.where((r) => r['pinned'] == true).isNotEmpty) ...[
            _buildFeaturedTrendingSection(),
            SizedBox(height: 16.h),
          ],
          if (_trendingRemote.where((r) => r['pinned'] != true).isNotEmpty) ...[
            Padding(
              padding: EdgeInsets.only(bottom: 8.h),
              child: Text(
                'Popular Items',
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[800],
                ),
              ),
            ),
            _buildRegularTrendingGrid(),
          ],
        ],
      ),
    );
  }

  Widget _buildFeaturedTrendingSection() {
    final pinnedItems =
    _trendingRemote.where((r) => r['pinned'] == true).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 8.h),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(4.w),
                decoration: BoxDecoration(
                  color: Colors.orange[100],
                  borderRadius: BorderRadius.circular(6.r),
                ),
                child: Icon(Icons.star, color: Colors.orange[600], size: 14.sp),
              ),
              SizedBox(width: 6.w),
              Text(
                'Featured Ads',
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[800],
                ),
              ),
              SizedBox(width: 4.w),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 1.h),
                decoration: BoxDecoration(
                  color: Colors.orange[600],
                  borderRadius: BorderRadius.circular(6.r),
                ),
                child: Text(
                  'PREMIUM',
                  style: TextStyle(
                    fontSize: 6.sp,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
        GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 8.h,
            crossAxisSpacing: 8.w,
            childAspectRatio: 0.66, // 🔶 原 0.75 → 放大图片
          ),
          itemCount: pinnedItems.length,
          itemBuilder: (context, i) {
            final r = pinnedItems[i];
            return _buildPremiumCard(r);
          },
        ),
        Container(
          margin: EdgeInsets.symmetric(vertical: 12.h),
          height: 1.h,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                Colors.orange[300]!,
                Colors.transparent
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRegularTrendingGrid() {
    final regularItems =
    _trendingRemote.where((r) => r['pinned'] != true).toList();
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8.h,
        crossAxisSpacing: 8.w,
        childAspectRatio: 0.66, // 🔶 原 0.85 → 放大图片
      ),
      itemCount: regularItems.length,
      itemBuilder: (context, i) {
        final r = regularItems[i];
        return _buildRegularCard(r);
      },
    );
  }

  Widget _buildPremiumCard(Map<String, dynamic> r) {
    final images = (r['images'] as List?) ?? const [];
    final img = images.isNotEmpty ? images.first.toString() : null;
    final priceText = _formatPrice(r['price']);
    return GestureDetector(
      onTap: () => _navigateToProductDetail(r['id'].toString()),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: Colors.orange.shade300, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.orange.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  _buildImageWidget(img),
                  Positioned(
                    top: 6.h,
                    left: 6.w,
                    child: Container(
                      padding:
                      EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                      decoration: BoxDecoration(
                        color: Colors.orange[600],
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.push_pin, size: 8.sp, color: Colors.white),
                          SizedBox(width: 2.w),
                          Text(
                            'PINNED',
                            style: TextStyle(
                              fontSize: 7.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.all(8.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (priceText.isNotEmpty)
                    Container(
                      padding:
                      EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                      decoration: BoxDecoration(
                        color: _successGreen.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4.r),
                        border:
                        Border.all(color: _successGreen.withOpacity(0.3)),
                      ),
                      child: Text(
                        priceText,
                        style: TextStyle(
                          color: _successGreen,
                          fontWeight: FontWeight.bold,
                          fontSize: 11.sp,
                        ),
                      ),
                    ),
                  SizedBox(height: 4.h),
                  Text(
                    r['title']?.toString() ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                      height: 1.2,
                    ),
                  ),
                  SizedBox(height: 3.h),
                  Row(
                    children: [
                      Icon(Icons.location_on,
                          size: 8.sp, color: Colors.grey[500]),
                      SizedBox(width: 2.w),
                      Expanded(
                        child: Text(
                          r['city']?.toString() ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 8.sp, color: Colors.grey[600]),
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
    );
  }

  Widget _buildRegularCard(Map<String, dynamic> r) {
    final images = (r['images'] as List?) ?? const [];
    final img = images.isNotEmpty ? images.first.toString() : null;
    final priceText = _formatPrice(r['price']);
    return GestureDetector(
      onTap: () => _navigateToProductDetail(r['id'].toString()),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildImageWidget(img),
            ),
            Padding(
              padding: EdgeInsets.all(6.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (priceText.isNotEmpty)
                    Text(
                      priceText,
                      style: TextStyle(
                        color: _successGreen,
                        fontWeight: FontWeight.bold,
                        fontSize: 12.sp,
                      ),
                    ),
                  SizedBox(height: 2.h),
                  Text(
                    r['title']?.toString() ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.sp,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[800],
                      height: 1.2,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Row(
                    children: [
                      Icon(Icons.location_on,
                          size: 8.sp, color: Colors.grey[500]),
                      SizedBox(width: 1.w),
                      Expanded(
                        child: Text(
                          r['city']?.toString() ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 8.sp, color: Colors.grey[600]),
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
    );
  }

  Widget _buildImageWidget(String? src) {
    if (src == null || src.isEmpty) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.vertical(top: Radius.circular(10.r)),
        ),
        child: Center(
          child: Icon(Icons.image, size: 24.sp, color: Colors.grey[400]),
        ),
      );
    }
    final imgWidget = src.startsWith('http')
        ? Image.network(
      src,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius:
            BorderRadius.vertical(top: Radius.circular(10.r)),
          ),
          child: Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _primaryBlue,
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                  loadingProgress.expectedTotalBytes!
                  : null,
            ),
          ),
        );
      },
      errorBuilder: (_, __, ___) => Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius:
          BorderRadius.vertical(top: Radius.circular(10.r)),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.broken_image,
                  size: 20.sp, color: Colors.grey[400]),
              SizedBox(height: 2.h),
              Text(
                'Image failed to load',
                style: TextStyle(fontSize: 8.sp, color: Colors.grey[500]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    )
        : Image.asset(
      src,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      errorBuilder: (_, __, ___) => Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius:
          BorderRadius.vertical(top: Radius.circular(10.r)),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.broken_image,
                  size: 20.sp, color: Colors.grey[400]),
              SizedBox(height: 2.h),
              Text(
                'Image not found',
                style: TextStyle(fontSize: 8.sp, color: Colors.grey[500]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(10.r)),
      child: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: imgWidget,
      ),
    );
  }
}
