// lib/pages/home_page.dart
// 使用Facebook亮蓝色和Jiji风格的自动图片调整功能

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

import 'dart:async'; // ✅ 新增
import 'package:swaply/services/listing_events_bus.dart'; // ✅ 新增

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _trendingKey = GlobalKey();
  final TextEditingController _searchCtrl = TextEditingController();

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  String _selectedLocation = 'All Zimbabwe';

  // 趋势数据
  List<Map<String, dynamic>> _trendingRemote = [];
  bool _loadingTrending = false;

  StreamSubscription? _listingPubSub; // ✅ 新增：订阅句柄

  // Facebook亮蓝色配色方案
  static const Color _primaryBlue = Color(0xFF1877F2); // Facebook亮蓝色
  static const Color _lightBlue = Color(0xFFE3F2FD);
  static const Color _successGreen = Color(0xFF4CAF50);

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

  // ✅ 仅调整了排序；文件名/ID/label 均保持不变
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
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _loadTrending();

    // ✅ [MODIFIED] 按照要求 1) 确保监听并触发刷新
    _listingPubSub = ListingEventsBus.instance.stream.listen((e) {
      if (e is ListingPublishedEvent) {
        // ✅ 加这两行
        // ignore: avoid_print
        print('[Home] Received ListingPublishedEvent -> refresh(bypassCache: true)');
        _loadTrending(bypassCache: true); // ✅ 适配：调用 _loadTrending
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchCtrl.dispose();
    _fadeController.dispose();
    _listingPubSub?.cancel(); // ✅ 新增
    super.dispose();
  }

  /* ===================== 仅 iOS：头部向下“轻微”整体位移 ===================== */
  double _iosBump(BuildContext context) {
    if (!Platform.isIOS) return 0;
    final top = MediaQuery.of(context).padding.top; // 灵动岛/状态栏安全区
    // ⬇️ 保持你文件中的 +17 设置
    return top + 17;
  }

  /* ===================== 数据加载 ===================== */

  /// 修复的价格格式化函数
  String _formatPrice(dynamic priceData) {
    if (priceData == null) return '';

    if (priceData is num) {
      if (priceData == 0) return 'Free';
      return '\$${priceData.toStringAsFixed(0)}';
    }

    if (priceData is String) {
      if (priceData.toLowerCase().contains('free') || priceData == '0') {
        return 'Free';
      }

      final cleanPrice = priceData.replaceAll(RegExp(r'[^\d.]'), '');
      final parsedPrice = num.tryParse(cleanPrice);

      if (parsedPrice != null) {
        if (parsedPrice == 0) return 'Free';
        return '\$${parsedPrice.toStringAsFixed(0)}';
      } else {
        if (priceData.contains('\$') || priceData.contains('USD')) {
          return priceData;
        } else {
          return '\$${priceData}';
        }
      }
    }

    return priceData.toString();
  }

  /// 混合趋势：置顶优先 + 最新填充
  /// ✅ [MODIFIED] 按照要求 2) 确保 bypassCache 被接收并透传
  Future<List<Map<String, dynamic>>> _fetchTrendingMixed({
    String? city,
    int pinnedLimit = 6,
    int latestLimit = 36,
    int total = 12,
    bool bypassCache = false, // ✅ 接收
  }) async {
    // 1) 置顶广告 -> 列表（仅趋势类型）
    final pinnedAds = await CouponService.getTrendingPinnedAds(
      city: city,
      limit: pinnedLimit,
      // (按要求，bypassCache 仅传递给 ListingApi)
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

    // 2) 最新列表
    // ✅ [MODIFIED] 按照要求 2) 确保 bypassCache (即 forceNetwork) 被透传
    final latest = await ListingApi.fetchListings(
      city: city,
      limit: latestLimit,
      offset: 0,
      orderBy: 'created_at',
      ascending: false,
      status: 'active',
      forceNetwork: bypassCache, // ✅ 把 bypassCache 透传给 API
    );

    // 3) 去重并填充
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
      if (list.length >= total) break;
    }
    return list.take(total).toList();
  }

  /// ✅ [MODIFIED] 按照要求 2) 适配 _refresh，即 _loadTrending
  Future<void> _loadTrending({bool bypassCache = false}) async {
    setState(() => _loadingTrending = true);
    try {
      final city =
      _selectedLocation == 'All Zimbabwe' ? null : _selectedLocation;
      // ✅ [MODIFIED] 按照要求 2) 确保 bypassCache 被透传
      final rows = await _fetchTrendingMixed(
        city: city,
        pinnedLimit: 6,
        latestLimit: 36,
        total: 12,
        bypassCache: bypassCache, // ✅ 透传参数
      );
      if (mounted) {
        setState(() => _trendingRemote = rows);
        // [FIX] 修复：仅在首次加载时（非 bypassCache）或数据为空时才播放动画
        if (!bypassCache || _trendingRemote.isEmpty) {
          _fadeController.forward();
        }
      }
    } catch (e) {
      // 失败稳态：仅打印日志，UI依靠 _trendingRemote.isEmpty (或 _loadingTrending) 展示
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
      Navigator.of(context).push(
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
    Navigator.of(context).push(
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            SearchResultsPage(keyword: keyword, location: _selectedLocation),
      ),
    );
  }

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
        // ✅ 关键修复：把登录页推到“根 Navigator”，避免落到 Tab 的子 Navigator 里
        await Navigator.of(context, rootNavigator: true).pushNamed('/login');
      }
      if (Supabase.instance.client.auth.currentUser == null) return;
    }
    if (!mounted) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SellFormPage()));
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

                  // 紧凑分类网格
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

  // =================================================================
  // ⬇️ 唯一修改的函数 ⬇️
  // =================================================================

  /// 关键修复：分类网格单元用“比例切分”，防 1~2px 溢出（模拟器专属）
  Widget _buildCompactCategoriesGrid() {
    return Padding(
      padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 16.h),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          childAspectRatio: 1.0,
          crossAxisSpacing: 6.w,
          mainAxisSpacing: 6.h,
        ),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final isTrending = index == 0;

          return GestureDetector(
            onTap: () => _navigateToCategory(cat['id']!, cat['label']!),
            // ✅ 修复 2: 添加保险剪裁，裁剪掉 0.5px 的渲染毛刺
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10.r),
              child: Container(
                decoration: BoxDecoration(
                  color: isTrending ? Colors.orange.shade50 : Colors.grey[50],
                  // borderRadius: BorderRadius.circular(10.r), // ClipRRect 已处理
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
                // ✅ 修复 1 & 3: 使用 LayoutBuilder 进行比例切分
                child: LayoutBuilder(
                  builder: (ctx, c) {
                    // 按单元格高度拆分：图标区 58%、间隔 8%、文字区 34%
                    final double h = c.maxHeight;
                    final double iconBoxH = h * 0.58;
                    final double gapH = h * 0.08;
                    final double textBoxH = h * 0.34;

                    // ✅ 修复 1: 图标尺寸也使用比例计算，替换固定的 44/28
                    final double iconContainerSize = iconBoxH * 0.75;
                    final double iconImageSize = iconBoxH * 0.45;

                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 1. 图标容器 (比例高度)
                        SizedBox(
                          height: iconBoxH,
                          child: Center(
                            child: Container(
                              width: iconContainerSize,
                              height: iconContainerSize,
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
                                  width: iconImageSize,
                                  height: iconImageSize,
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
                                          size: iconImageSize, // 使用比例尺寸
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
                          ),
                        ),
                        // 2. 间隔 (比例高度)
                        SizedBox(height: gapH),
                        // 3. 文本容器 (比例高度 + FittedBox 兜底)
                        SizedBox(
                          height: textBoxH,
                          child: Center(
                            // ✅ 修复 1: 缩放兜底
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 2.w),
                                child: Text(
                                  cat['label']!,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  // ✅ 修复 1: 去掉多余的下伸空间
                                  textHeightBehavior: const TextHeightBehavior(
                                    applyHeightToFirstAscent: false,
                                    applyHeightToLastDescent: false,
                                  ),
                                  style: TextStyle(
                                    fontSize: 11.sp,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey[700],
                                    height: 1.1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // =================================================================
  // ⬆️ 唯一修改的函数 ⬆️
  // =================================================================

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

  Widget _buildTrendingLoading() {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.85,
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
            Container(
              height: 50.h,
              padding: EdgeInsets.all(6.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 10.h,
                    width: 50.w,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(3.r),
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Container(
                    height: 8.h,
                    width: 80.w,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(3.r),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendingGrid() {
    // 稳态展示：即使 _loadTrending 失败，_trendingRemote 也会是 []，展示空态
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
          // 分离置顶广告和普通内容
          if (_trendingRemote.where((r) => r['pinned'] == true).isNotEmpty) ...[
            // 置顶广告部分
            _buildFeaturedTrendingSection(),
            SizedBox(height: 16.h),
          ],

          // 普通trending内容
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
        // 特色标题
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

        // 特色广告网格
        GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 8.h,
            crossAxisSpacing: 8.w,
            childAspectRatio: 0.75, // 调整为更高的比例以显示完整图片
          ),
          itemCount: pinnedItems.length,
          itemBuilder: (context, i) {
            final r = pinnedItems[i];
            return _buildPremiumCard(r);
          },
        ),

        // 分隔线
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
        childAspectRatio: 0.85,
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
            // 图片区域
            Expanded(
              child: Stack(
                children: [
                  _buildImageWidget(img),
                  // 置顶标签
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

            // 内容区域
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
            // 图片区域
            Expanded(
              child: _buildImageWidget(img),
            ),

            // 内容区域
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
                        color:
                        priceText == 'Free' ? _successGreen : _successGreen,
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

    // Jiji风格的自动图片调整 - 完全填充容器
    final imgWidget = src.startsWith('http')
        ? Image.network(
      src,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover, // 完全覆盖容器
      alignment: Alignment.center,
      // 稳态处理：确保网络图片加载失败时 UI 不崩溃
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
                style:
                TextStyle(fontSize: 8.sp, color: Colors.grey[500]),
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
                style:
                TextStyle(fontSize: 8.sp, color: Colors.grey[500]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(10.r)),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        child: imgWidget,
      ),
    );
  }
}