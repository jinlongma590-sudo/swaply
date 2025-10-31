// lib/pages/coupon_management_page.dart - 防循环版本（30s页面级TTL + Future缓存）
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:swaply/services/coupon_service.dart';
import 'package:swaply/models/coupon.dart';
import 'package:swaply/pages/sell_form_page.dart';

class CouponManagementPage extends StatefulWidget {
  const CouponManagementPage({Key? key}) : super(key: key);

  @override
  State<CouponManagementPage> createState() => _CouponManagementPageState();
}

class _CouponManagementPageState extends State<CouponManagementPage>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  // ========== 防循环：TTL + Future缓存 ==========
  static const _ttl = Duration(seconds: 30);
  DateTime? _lastFetchAt;
  bool _loading = false; // 并发锁

  // 缓存的Future，避免每次build重建
  Future<void>? _dataFuture;

  late TabController _tabController;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  bool _isRefreshing = false;

  List<CouponModel> _allCoupons = [];
  List<CouponModel> _activeCoupons = [];
  List<CouponModel> _usedCoupons = [];
  List<CouponModel> _expiredCoupons = [];

  Map<String, dynamic> _trendingQuotaStatus = {};
  Map<String, dynamic> _couponStats = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );

    // ✅ 只触发一次，存储Future
    _dataFuture = _loadDataOnce();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  // ========== 核心：防循环的数据加载 ==========
  Future<void> _loadDataOnce({bool force = false}) async {
    if (_loading) return; // 防并发

    final now = DateTime.now();
    // TTL限流：30s内不重复加载（除非force=true）
    if (!force &&
        _lastFetchAt != null &&
        now.difference(_lastFetchAt!) < _ttl) {
      return;
    }

    _loading = true;
    _lastFetchAt = now;

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      setState(() {
        _allCoupons = [];
        _activeCoupons = [];
        _usedCoupons = [];
        _expiredCoupons = [];
        _trendingQuotaStatus = {};
        _couponStats = {};
      });
      _loading = false;
      return;
    }

    try {
      await Future.wait([
        _loadCoupons(),
        _loadTrendingQuotaStatus(),
      ]);

      await _loadCouponStats();

      if (mounted) {
        _animationController.forward();
      }
    } catch (e) {
      print('Failed to load coupon data: $e');
      if (mounted) {
        _showSnackBar('Failed to load data: $e', isError: true);
      }
    } finally {
      _loading = false;
      if (mounted) setState(() {}); // 仅用于UI刷新，不重新触发请求
    }
  }

  // ========== 手动刷新（强制绕过TTL） ==========
  Future<void> _onPullToRefresh() async {
    setState(() => _isRefreshing = true);

    // 强制刷新，同时更新_dataFuture
    _dataFuture = _loadDataOnce(force: true);
    await _dataFuture;

    setState(() => _isRefreshing = false);
  }

  // ========== 增强版数据加载方法 - 确保包含welcome券 + 健壮性处理 ==========
  Future<void> _loadCoupons() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      // 直接查询数据库，只按 user_id 查询，不限制 source 或 type
      // 移除了 priority 排序，只按创建时间排序
      final rows = await Supabase.instance.client
          .from('coupons')
          .select('*')
          .eq('user_id', user.id) // 只限定 user_id
          .order('created_at', ascending: false) // 按创建时间排序
          .limit(500);

      final list = (rows as List).cast<Map<String, dynamic>>();

      final coupons = <CouponModel>[];
      for (final map in list) {
        try {
          // 确保关键字段不为null，提供默认值
          map['used_count'] ??= 0;
          map['max_uses'] ??= 1;

          // 如果 expires_at 为空，设置为未来30天
          if (map['expires_at'] == null) {
            map['expires_at'] =
                DateTime.now().add(const Duration(days: 30)).toIso8601String();
          }

          final coupon = CouponModel.fromMap(map);
          coupons.add(coupon);
        } catch (e) {
          debugPrint('Failed to parse coupon: $e, data: $map');
          continue; // 跳过解析失败的券，继续处理其他
        }
      }

      debugPrint('Successfully loaded ${coupons.length} coupons from database');

      if (!mounted) return;
      setState(() {
        _allCoupons = coupons;
      });
    } catch (e) {
      // 页面兜底失败 → 回退到 Service（如果存在）
      debugPrint('Direct coupons query failed: $e');

      try {
        final userId = user.id;
        final coupons = await CouponService.getUserCoupons(userId: userId);

        // 简化排序，只按创建时间
        coupons.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        debugPrint(
            'Fallback loaded ${coupons.length} coupons via CouponService');

        if (!mounted) return;
        setState(() => _allCoupons = coupons);
      } catch (e2) {
        debugPrint('Fallback via CouponService failed: $e2');
        // 最终失败，保持空列表
        if (mounted) {
          setState(() => _allCoupons = []);
        }
      }
    }
  }

  Future<void> _loadTrendingQuotaStatus() async {
    try {
      final trendingAds = await CouponService.getTrendingPinnedAds();
      final usedCount = trendingAds.length;
      const maxCount = 20;

      if (mounted) {
        setState(() {
          _trendingQuotaStatus = {
            'used_count': usedCount,
            'max_count': maxCount,
            'available': usedCount < maxCount,
            'remaining': maxCount - usedCount,
          };
        });
      }
    } catch (e) {
      print('Failed to load trending quota status: $e');
      if (mounted) {
        setState(() {
          _trendingQuotaStatus = {
            'used_count': 0,
            'max_count': 20,
            'available': true,
            'remaining': 20,
          };
        });
      }
    }
  }

  // ========== 增强版统计方法 - 添加空值保护 ==========
  Future<void> _loadCouponStats() async {
    final now = DateTime.now();

    try {
      final activeCoupons = <CouponModel>[];
      final usedCoupons = <CouponModel>[];
      final expiredCoupons = <CouponModel>[];

      for (final coupon in _allCoupons) {
        // 健壮的过期判断 - null 视为未过期
        bool isCurrentlyExpired = false;
        try {
          isCurrentlyExpired =
              coupon.expiresAt != null ? now.isAfter(coupon.expiresAt) : false;
        } catch (e) {
          debugPrint('Error checking expiry for coupon ${coupon.id}: $e');
          isCurrentlyExpired = false;
        }

        // 安全的使用次数检查
        final usedCount = coupon.usedCount ?? 0;
        final maxUses = coupon.maxUses ?? 1;

        if (coupon.status == CouponStatus.used) {
          usedCoupons.add(coupon);
        } else if (coupon.status == CouponStatus.expired ||
            isCurrentlyExpired) {
          expiredCoupons.add(coupon);
        } else if (coupon.status == CouponStatus.active &&
            !isCurrentlyExpired &&
            usedCount < maxUses) {
          activeCoupons.add(coupon);
        } else {
          // 其他情况归类为过期
          expiredCoupons.add(coupon);
        }
      }

      // 计算即将过期的券（3天内）
      int expiringSoon = 0;
      for (final coupon in activeCoupons) {
        try {
          if (coupon.daysUntilExpiry <= 3) {
            expiringSoon++;
          }
        } catch (e) {
          // 忽略计算错误
          debugPrint('Error calculating days until expiry: $e');
        }
      }

      if (mounted) {
        setState(() {
          _activeCoupons = activeCoupons;
          _usedCoupons = usedCoupons;
          _expiredCoupons = expiredCoupons;

          _couponStats = {
            'total_coupons': _allCoupons.length,
            'active_coupons': activeCoupons.length,
            'used_coupons': usedCoupons.length,
            'expired_coupons': expiredCoupons.length,
            'expiring_soon': expiringSoon,
          };
        });
      }

      debugPrint(
          'Coupon stats - Total: ${_allCoupons.length}, Active: ${activeCoupons.length}, Used: ${usedCoupons.length}, Expired: ${expiredCoupons.length}');
    } catch (e) {
      print('Failed to calculate coupon stats: $e');
      // 失败时设置默认统计
      if (mounted) {
        setState(() {
          _couponStats = {
            'total_coupons': _allCoupons.length,
            'active_coupons': 0,
            'used_coupons': 0,
            'expired_coupons': 0,
            'expiring_soon': 0,
          };
        });
      }
    }
  }

  // ========== UI构建：修复导航问题 ==========
  @override
  Widget build(BuildContext context) {
    super.build(context); // for AutomaticKeepAliveClientMixin

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          _buildCustomAppBar(),
          _buildTrendingQuotaCard(),
          _buildTabBar(),
          Expanded(
            child: FutureBuilder<void>(
              future: _dataFuture, // ✅ 只包装需要数据的部分
              builder: (context, snapshot) {
                // 首次加载状态
                if (snapshot.connectionState == ConnectionState.waiting &&
                    _allCoupons.isEmpty) {
                  return _buildLoadingState();
                }

                // 错误处理
                if (snapshot.hasError) {
                  return _buildErrorState(snapshot.error.toString());
                }

                // 数据加载完成，显示TabBarView
                return FadeTransition(
                  opacity: _fadeAnimation,
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildCouponList(_activeCoupons, 'No available coupons'),
                      _buildCouponList(_usedCoupons, 'No usage records'),
                      _buildCouponList(_expiredCoupons, 'No expired coupons'),
                      _buildCouponList(_allCoupons, 'No coupons'),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCouponTips,
        icon: const Icon(Icons.help_outline),
        label: const Text('Usage Guide'),
        backgroundColor: const Color(0xFF2196F3),
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildCustomAppBar() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2196F3),
            Color(0xFF1976D2),
            Color(0xFF1565C0),
          ],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'My Coupons',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Manage and use your coupons',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _isRefreshing ? null : _onPullToRefresh,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: _isRefreshing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.refresh,
                              color: Colors.white,
                              size: 18,
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildQuickStats(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrendingQuotaCard() {
    final used = _trendingQuotaStatus['used_count'] as int? ?? 0;
    final max = _trendingQuotaStatus['max_count'] as int? ?? 20;
    final remaining = _trendingQuotaStatus['remaining'] as int? ?? 20;
    final available = _trendingQuotaStatus['available'] as bool? ?? true;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2196F3),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2196F3).withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.local_fire_department,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Today\'s Hot Pinning Quota',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  available
                      ? 'Remaining $remaining free hot pins'
                      : 'Today\'s quota used up, try again tomorrow',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: FractionallySizedBox(
                    widthFactor: (used / max).clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '$used/$max',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    final availableCount = _activeCoupons.length;
    final usedCount = _usedCoupons.length;
    final expiredCount = _expiredCoupons.length;
    final allCount = _allCoupons.length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.grey[600],
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: const Color(0xFF2196F3),
        ),
        labelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.normal,
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorPadding: EdgeInsets.zero,
        dividerColor: Colors.transparent,
        overlayColor: MaterialStateProperty.all(Colors.transparent),
        tabs: [
          Tab(
            height: 56,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Available'),
                const SizedBox(height: 2),
                Text('($availableCount)', style: const TextStyle(fontSize: 10)),
              ],
            ),
          ),
          Tab(
            height: 56,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Used'),
                const SizedBox(height: 2),
                Text('($usedCount)', style: const TextStyle(fontSize: 10)),
              ],
            ),
          ),
          Tab(
            height: 56,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Expired'),
                const SizedBox(height: 2),
                Text('($expiredCount)', style: const TextStyle(fontSize: 10)),
              ],
            ),
          ),
          Tab(
            height: 56,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('All'),
                const SizedBox(height: 2),
                Text('($allCount)', style: const TextStyle(fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStats() {
    final expiringSoon = _couponStats['expiring_soon'] as int? ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildQuickStatItem('Available', _activeCoupons.length.toString(),
              Icons.card_giftcard),
          Container(width: 1, height: 30, color: Colors.white.withOpacity(0.3)),
          _buildQuickStatItem(
              'Used', _usedCoupons.length.toString(), Icons.check_circle),
          Container(width: 1, height: 30, color: Colors.white.withOpacity(0.3)),
          _buildQuickStatItem(
              'Expiring\nSoon', expiringSoon.toString(), Icons.schedule),
        ],
      ),
    );
  }

  Widget _buildQuickStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                const SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFF2196F3),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Loading your coupons...',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 新增错误状态UI
  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red[400],
            ),
            const SizedBox(height: 16),
            const Text(
              'Failed to load coupons',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _onPullToRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2196F3),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCouponList(List<CouponModel> coupons, String emptyMessage) {
    return RefreshIndicator(
      onRefresh: _onPullToRefresh, // ✅ 使用新的刷新方法
      color: const Color(0xFF2196F3),
      child: coupons.isEmpty
          ? _buildEmptyState(emptyMessage)
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: coupons.length,
              itemBuilder: (context, index) {
                return TweenAnimationBuilder<double>(
                  duration: Duration(milliseconds: 300 + (index * 100)),
                  tween: Tween(begin: 0.0, end: 1.0),
                  builder: (context, value, child) {
                    return Transform.translate(
                      offset: Offset(0, 20 * (1 - value)),
                      child: Opacity(
                        opacity: value,
                        child: _buildCouponCard(coupons[index]),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF2196F3).withOpacity(0.1),
                    const Color(0xFF1976D2).withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(50),
              ),
              child: const Icon(
                Icons.card_giftcard_outlined,
                size: 50,
                color: Color(0xFF2196F3),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No coupons',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCouponCard(CouponModel coupon) {
    // 安全的过期检查
    bool isExpiringSoon = false;
    try {
      isExpiringSoon = coupon.daysUntilExpiry <= 3 && coupon.isUsable;
    } catch (e) {
      isExpiringSoon = false;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _getCouponColor(coupon.type).withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: isExpiringSoon
            ? Border.all(color: Colors.red.withOpacity(0.3), width: 2)
            : Border.all(
                color: _getCouponColor(coupon.type).withOpacity(0.2),
                width: 1,
              ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _getCouponColor(coupon.type),
                    _getCouponColor(coupon.type).withOpacity(0.8),
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      _getCouponIcon(coupon.type),
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          coupon.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            coupon.code,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      coupon.statusDescription,
                      style: TextStyle(
                        color: _getCouponColor(coupon.type),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isExpiringSoon) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning,
                              color: Colors.red, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Expiring soon! Use within ${coupon.daysUntilExpiry} days.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.red.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text(
                    coupon.description,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (coupon.isWelcome || coupon.pinScope != null) ...[
                    Row(
                      children: [
                        Icon(Icons.push_pin,
                            size: 16, color: Colors.orange[700]),
                        const SizedBox(width: 6),
                        Text(
                          'Scope: ${coupon.isWelcome ? 'Category Pin' : (coupon.pinScope ?? 'N/A')}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[800],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _copyCouponCode(coupon.code),
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text(
                            'Copy Code',
                            style: TextStyle(fontSize: 14),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _getCouponColor(coupon.type),
                            side:
                                BorderSide(color: _getCouponColor(coupon.type)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      if (coupon.isUsable) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _onUseNow(coupon),
                            icon: Icon(
                              coupon.canPin
                                  ? Icons.post_add
                                  : Icons.info_outline,
                              size: 16,
                            ),
                            label: Text(
                              coupon.canPin ? 'Use Now' : 'How to Use',
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _getCouponColor(coupon.type),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                            ),
                          ),
                        ),
                      ],
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

  Color _getCouponColor(CouponType type) {
    switch (type) {
      case CouponType.trending:
      case CouponType.trendingPin:
        return const Color(0xFFFF6B35);
      case CouponType.category:
      case CouponType.pinned:
      case CouponType.featured:
      case CouponType.premium:
        return const Color(0xFF2196F3);
      case CouponType.boost:
        return const Color(0xFF9C27B0);
      case CouponType.registerBonus:
      case CouponType.welcome:
        return const Color(0xFF4CAF50);
      case CouponType.activityBonus:
        return const Color(0xFFFF9800);
      case CouponType.referralBonus:
        return const Color(0xFFE91E63);
      default:
        return const Color(0xFF2196F3);
    }
  }

  IconData _getCouponIcon(CouponType type) {
    switch (type) {
      case CouponType.trending:
      case CouponType.trendingPin:
        return Icons.local_fire_department;
      case CouponType.category:
      case CouponType.pinned:
      case CouponType.featured:
      case CouponType.premium:
        return Icons.push_pin;
      case CouponType.boost:
        return Icons.rocket_launch;
      case CouponType.registerBonus:
      case CouponType.welcome:
        return Icons.card_giftcard;
      case CouponType.activityBonus:
        return Icons.task_alt;
      case CouponType.referralBonus:
        return Icons.group_add;
      default:
        return Icons.card_giftcard;
    }
  }

  String _readableType(CouponType type) {
    switch (type) {
      case CouponType.trending:
      case CouponType.trendingPin:
        return 'Hot Pin';
      case CouponType.category:
      case CouponType.pinned:
      case CouponType.featured:
      case CouponType.premium:
        return 'Category Pin';
      case CouponType.boost:
        return 'Search Boost';
      case CouponType.registerBonus:
        return 'Register Bonus';
      case CouponType.welcome:
        return 'Welcome Reward';
      case CouponType.activityBonus:
        return 'Activity Bonus';
      case CouponType.referralBonus:
        return 'Referral Bonus';
      default:
        return 'Coupon';
    }
  }

  void _copyCouponCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    _showSnackBar('Coupon code copied: $code');
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red[600] : const Color(0xFF2196F3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _onUseNow(CouponModel coupon) {
    if (coupon.canPin) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const SellFormPage(),
          settings: RouteSettings(arguments: {'couponId': coupon.id}),
        ),
      );
      _showSnackBar(
          'Tip: select this coupon in the posting page to pin your item.');
    } else {
      _showUseCouponDialog(coupon);
    }
  }

  void _showUseCouponDialog(CouponModel coupon) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'How to Use',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (coupon.canPin) ...[
                const Text(
                  'This coupon can pin your item to get more visibility.',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Post an item and choose this coupon during submission.',
                  style: TextStyle(fontSize: 14, color: Colors.black54),
                ),
              ] else ...[
                const Text(
                  'This coupon cannot be used for pinning directly.',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  'Type: ${_readableType(coupon.type)}',
                  style: const TextStyle(fontSize: 14, color: Colors.black54),
                ),
              ],
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      coupon.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Code: ${coupon.code}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (coupon.canPin)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SellFormPage(),
                    settings: RouteSettings(arguments: {'couponId': coupon.id}),
                  ),
                );
              },
              icon: const Icon(Icons.post_add, size: 18),
              label: const Text('Go to Post'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2196F3),
                foregroundColor: Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  void _showCouponTips() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'How to Use Coupons',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTipItem(
                icon: Icons.local_fire_department,
                title: 'Hot Pin Coupons',
                description:
                    'Pin your items to the trending section on homepage for maximum visibility.',
                color: const Color(0xFFFF6B35),
              ),
              const SizedBox(height: 16),
              _buildTipItem(
                icon: Icons.push_pin,
                title: 'Category Pin Coupons',
                description:
                    'Pin your items to the top of specific category pages.',
                color: const Color(0xFF2196F3),
              ),
              const SizedBox(height: 16),
              _buildTipItem(
                icon: Icons.rocket_launch,
                title: 'Boost Coupons',
                description: 'Boost your item ranking in search results.',
                color: const Color(0xFF9C27B0),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF2196F3).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: const Color(0xFF2196F3).withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lightbulb, color: Color(0xFF2196F3), size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tip: Use hot pin coupons during peak hours for best results!',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF1976D2),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _buildTipItem({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  bool get wantKeepAlive => true; // 保持状态，避免Tab切换重建
}
