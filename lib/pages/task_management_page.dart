// lib/pages/task_management_page.dart
// 修复：
// 1) Realtime 订阅使用 PostgresChangeFilterType 枚举；
// 2) 首刷强制刷新；
// 3) 邀请/任务/优惠券/日志变更即刻同步；
// 4) 任务表名改正为 user_tasks（原 reward_tasks 会收不到推送）；
// 5) 更稳健的 UTF-8 乱码与分隔符归一化处理。
// 6) ✅ 历史从 coupon_usages 直接加载，不再依赖 RewardService.getUserRewardHistory
// 7) ✅ Realtime 历史频道改为监听 coupon_usages 表
// 8) ✅ 历史卡片：第一行券标题，第二行友好化 reason（app/system/auto/空隐藏或映射）

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:swaply/services/reward_service.dart';
import 'package:swaply/services/coupon_service.dart';
import 'package:swaply/models/coupon.dart';
import 'package:swaply/pages/sell_form_page.dart';

class TaskManagementPage extends StatefulWidget {
  final int initialTab;

  const TaskManagementPage({Key? key, this.initialTab = 0}) : super(key: key);

  @override
  State<TaskManagementPage> createState() => _TaskManagementPageState();
}

class _TaskManagementPageState extends State<TaskManagementPage>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  // ===== 防循环：TTL + Future缓存 =====
  static const _ttl = Duration(seconds: 30);
  static DateTime? _lastFetchAt;
  static bool _loading = false;

  Future<void>? _dataFuture;

  late TabController _tabController;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  bool _isRefreshing = false;

  // 数据
  List<Map<String, dynamic>> _tasks = []; // 仅活跃任务
  List<Map<String, dynamic>> _rewardHistory = [];
  Map<String, dynamic> _rewardStats = {};
  List<CouponModel> _rewardCoupons = [];

  // Realtime
  RealtimeChannel? _couponChannel;
  RealtimeChannel? _logsChannel;
  RealtimeChannel? _taskChannel;
  RealtimeChannel? _referralChannel;

  // -------- UTF-8 乱码修复 --------
  static const Map<int, int> _cp1252Reverse = {
    0x20AC: 0x80, 0x201A: 0x82, 0x0192: 0x83, 0x201E: 0x84, 0x2026: 0x85,
    0x2020: 0x86, 0x2021: 0x87, 0x02C6: 0x88, 0x2030: 0x89, 0x0160: 0x8A,
    0x2039: 0x8B, 0x0152: 0x8C, 0x017D: 0x8E, 0x2018: 0x91, 0x2019: 0x92,
    0x201C: 0x93, 0x201D: 0x94, 0x2022: 0x95, 0x2013: 0x96, 0x2014: 0x97,
    0x02DC: 0x98, 0x2122: 0x99, 0x0161: 0x9A, 0x203A: 0x9B, 0x0153: 0x9C,
    0x017E: 0x9E, 0x0178: 0x9F,
  };

  /// 更谨慎的修复：仅在明显乱码痕迹出现时才做 cp1252→utf8 的回转
  String _fixUtf8Mojibake(dynamic v) {
    final s = v?.toString() ?? '';
    if (s.isEmpty) return s;

    // 只含 ASCII + 常见分隔符（·/•）等“安全字符”——直接返回，避免误修
    final safe = RegExp(r'^[\x00-\x7F\u00B7\u2022\s\.\,\;\:\!\?\-_/()\[\]&\+\%]*$');
    if (safe.hasMatch(s)) return s;

    // 只有出现这些“明显乱码痕迹”时才尝试修复
    final looksBroken =
        s.contains('Ã') || s.contains('Â') || s.contains('â') || s.contains('ð') || s.contains('�');
    if (!looksBroken) return s;

    try {
      final bytes = <int>[];
      for (final rune in s.runes) {
        final mapped = _cp1252Reverse[rune];
        if (mapped != null) {
          bytes.add(mapped);
        } else if (rune <= 0xFF) {
          bytes.add(rune & 0xFF);
        } else {
          bytes.add(0x3F);
        }
      }
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      try {
        return utf8.decode(latin1.encode(s), allowMalformed: true);
      } catch (_) {
        return s;
      }
    }
  }

  /// 分隔符归一化：把 `Â· / â€¢ / • / �` 等统一成 “ · ”
  String _normalizeSeparators(String s) {
    return s
        .replaceAll('Â·', ' · ')
        .replaceAll('â€¢', ' · ')
        .replaceAll('•', ' · ')
        .replaceAll(RegExp(r'\s\u{FFFD}\s'), ' · ') // U+FFFD
        .replaceAll(RegExp(r'\s{2,}'), ' ');
  }
  // ---------------------------------

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 2).toInt(),
    );

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
      value: 0.0, // 首次进入做淡入
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );

    // 首次进入强制刷新
    _dataFuture = _loadDataOnce(force: true);

    // 建立 Realtime 订阅
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _animationController.dispose();
    _disposeChannel(_couponChannel);
    _disposeChannel(_logsChannel);
    _disposeChannel(_taskChannel);
    _disposeChannel(_referralChannel);
    super.dispose();
  }

  void _disposeChannel(RealtimeChannel? ch) {
    if (ch == null) return;
    try {
      ch.unsubscribe();
      Supabase.instance.client.removeChannel(ch);
    } catch (_) {}
  }

  void _subscribeRealtime() {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;

    // coupons（用户优惠券变化 -> 更新可用券 + 统计）
    _couponChannel = client
        .channel('rewards-coupons-${user.id}')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'coupons',
      filter: PostgresChangeFilter(
        column: 'user_id',
        type: PostgresChangeFilterType.eq,
        value: user.id,
      ),
      callback: (_) {
        _loadRewardCoupons();
        _loadRewardStats();
      },
    )
        .subscribe();

    // ✅ coupon_usages（历史/统计变化 -> 立即刷新）
    _logsChannel = client
        .channel('rewards-logs-${user.id}')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'coupon_usages', // ← 已从 reward_logs 改为 coupon_usages
      filter: PostgresChangeFilter(
        column: 'user_id',
        type: PostgresChangeFilterType.eq,
        value: user.id,
      ),
      callback: (_) {
        _loadRewardHistory();
        _loadRewardStats();
      },
    )
        .subscribe();

    // user_tasks（任务进度）
    _taskChannel = client
        .channel('rewards-tasks-${user.id}')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'user_tasks', // ← 这里
      filter: PostgresChangeFilter(
        column: 'user_id',
        type: PostgresChangeFilterType.eq,
        value: user.id,
      ),
      callback: (_) async {
        await _loadTasks();
        await _loadRewardStats();
      },
    )
        .subscribe();

    // referrals（邀请关系状态变化 -> 刷新统计/奖励券/历史）
    _referralChannel = client
        .channel('rewards-referrals-${user.id}')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'referrals',
      // 监听我作为 inviter 的记录
      filter: PostgresChangeFilter(
        column: 'inviter_id',
        type: PostgresChangeFilterType.eq,
        value: user.id,
      ),
      callback: (_) async {
        // 邀请达成可能触发发券/日志，保险起见三者都刷
        await _loadRewardStats();
        await _loadRewardCoupons();
        await _loadRewardHistory();
      },
    )
        .subscribe();
  }

  // ===== 核心：限流加载 =====
  Future<void> _loadDataOnce({bool force = false}) async {
    if (_loading) return;

    final now = DateTime.now();
    if (!force && _lastFetchAt != null && now.difference(_lastFetchAt!) < _ttl) {
      if (mounted && _animationController.value == 0.0) {
        _animationController.forward();
      }
      return;
    }

    _loading = true;
    _lastFetchAt = now;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      _loading = false;
      return;
    }

    try {
      await Future.wait([
        _loadTasks(),
        _loadRewardHistory(),
        _loadRewardStats(),
        _loadRewardCoupons(),
      ]);

      if (mounted) {
        _animationController.forward();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load data: $e'),
            backgroundColor: Colors.red[600],
          ),
        );
      }
    } finally {
      _loading = false;
    }
  }

  // 手动刷新（强制绕过 TTL）
  Future<void> _refreshData() async {
    setState(() => _isRefreshing = true);
    _dataFuture = _loadDataOnce(force: true);
    await _dataFuture;
    if (mounted) setState(() => _isRefreshing = false);
  }

  Future<void> _loadTasks() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final tasks = await RewardService.getActiveTasks(user.id);
      if (!mounted) return;
      _tasks = tasks;
      setState(() {});
    } catch (_) {}
  }

  /// ✅ 直接从 coupon_usages 加载历史
  Future<void> _loadRewardHistory() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final supabase = Supabase.instance.client;

      // 1) 抓使用记录
      final usages = await supabase
          .from('coupon_usages')
          .select('id,coupon_id,user_id,listing_id,used_at,note,context')
          .eq('user_id', user.id)
          .order('used_at', ascending: false);

      // 2) 可选：抓优惠券标题/类型（没有外键也行，我们用 IN 一次性取回）
      final List<String> ids = usages
          .map((u) => u['coupon_id'])
          .whereType<String>()
          .toSet()
          .toList();

      Map<String, Map<String, dynamic>> couponById = {};
      if (ids.isNotEmpty) {
        final coupons =
        await supabase.from('coupons').select('id,title,type').or(ids.map((id) => 'id.eq.$id').join(','));
        for (final c in coupons) {
          final id = c['id'] as String;
          couponById[id] = (c as Map).map((k, v) => MapEntry(k.toString(), v));
        }
      }

      // 3) 映射成页面需要的字段
      final List<Map<String, dynamic>> history = [];
      for (final u in usages) {
        // 解析 context.source
        final ctx = u['context'];
        String? source;
        try {
          if (ctx is Map) {
            source = ctx['source']?.toString();
          } else if (ctx is String && ctx.isNotEmpty) {
            final parsed = jsonDecode(ctx);
            if (parsed is Map && parsed['source'] != null) {
              source = parsed['source'].toString();
            }
          }
        } catch (_) {}

        final String couponId = (u['coupon_id'] as String?) ?? '';
        final Map<String, dynamic>? c = couponById[couponId];

        final couponTitle = (c?['title'] as String?) ?? 'Coupon Used';
        final rewardType = _mapCouponTypeToRewardType(c?['type'] as String?);

        history.add({
          // 这几个 key 正好是 _buildHistoryCard 用到的
          'created_at': u['used_at'],
          'reward_reason': (source ?? 'coupon_used'),
          'coupon_title': couponTitle,
          'reward_type': rewardType,
        });
      }

      if (!mounted) return;
      setState(() => _rewardHistory = history);
    } catch (_) {
      // 静默失败，避免打断 UI
    }
  }

  Future<void> _loadRewardStats() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final stats = await RewardService.getUserRewardStats(user.id);
      if (!mounted) return;
      setState(() => _rewardStats = stats);
    } catch (_) {}
  }

  /// 关键修复：放宽查询条件，只按 `user_id + status=active` 取数，
  /// 之后在本地用 `_isRewardCoupon` 过滤（避免漏掉 category / trending / boost 等奖励券）
  Future<void> _loadRewardCoupons() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final supabase = Supabase.instance.client;

      final rows = await supabase
          .from('coupons')
          .select('*')
          .eq('user_id', user.id)
          .eq('status', 'active')
          .order('created_at', ascending: false);

      final List<CouponModel> all = [];
      for (final row in rows) {
        try {
          final c = CouponModel.fromMap(row);
          if (_isRewardCoupon(c.type) && !c.isExpired) {
            all.add(c);
          }
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() => _rewardCoupons = all);
    } catch (_) {
      // 回退：走服务封装
      try {
        final user = Supabase.instance.client.auth.currentUser;
        if (user == null) return;
        final coupons = await CouponService.getUserCoupons(
          userId: user.id,
          status: CouponStatus.active,
        );
        final rewardCoupons = coupons
            .where((c) => _isRewardCoupon(c.type) && !c.isExpired)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        if (!mounted) return;
        setState(() => _rewardCoupons = rewardCoupons);
      } catch (_) {}
    }
  }

  String _couponTypeName(CouponType t) {
    final s = t.toString();
    final i = s.indexOf('.');
    return i >= 0 ? s.substring(i + 1) : s;
  }

  bool _isRewardCoupon(CouponType type) {
    final n = _couponTypeName(type);
    const rewardLike = {
      'registerBonus',
      'referralBonus',
      'activityBonus',
      'welcome',
      'trending', // 兼容 hot
      'hot',
      'category',
      'boost', // 兼容 featured
      'featured',
    };
    return rewardLike.contains(n);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return FutureBuilder<void>(
      future: _dataFuture,
      builder: (context, snapshot) {
        final isInitialLoading =
            snapshot.connectionState == ConnectionState.waiting &&
                _lastFetchAt == null;

        return Scaffold(
          backgroundColor: const Color(0xFFF8F9FA),
          appBar: AppBar(
            title: Text(
              'My Rewards',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            backgroundColor: const Color(0xFF4CAF50),
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18.w),
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              Padding(
                padding: EdgeInsets.only(right: 16.w),
                child: GestureDetector(
                  onTap: _isRefreshing ? null : _refreshData,
                  child: Container(
                    padding: EdgeInsets.all(8.r),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: _isRefreshing
                        ? SizedBox(
                      width: 20.r,
                      height: 20.r,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                        : Icon(Icons.refresh, color: Colors.white, size: 20.r),
                  ),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              // 头部统计信息
              Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF4CAF50),
                      Color(0xFF45A049),
                      Color(0xFF2E7D32),
                    ],
                  ),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.all(20.w),
                      child: _buildQuickStats(),
                    ),
                    // Tab导航
                    Container(
                      margin: EdgeInsets.fromLTRB(20.w, 0, 20.w, 20.h),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        labelColor: Colors.white,
                        unselectedLabelColor: Colors.white.withOpacity(0.7),
                        indicator: BoxDecoration(
                          color: Colors.white.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        labelStyle: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w600,
                        ),
                        unselectedLabelStyle: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.normal,
                        ),
                        tabs: [
                          Tab(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.assignment, size: 16.r),
                                SizedBox(width: 6.w),
                                const Text('Tasks'),
                              ],
                            ),
                          ),
                          Tab(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.card_giftcard, size: 16.r),
                                SizedBox(width: 6.w),
                                const Text('Coupons'),
                              ],
                            ),
                          ),
                          Tab(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.history, size: 16.r),
                                SizedBox(width: 6.w),
                                const Text('History'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Tab内容
              Expanded(
                child: isInitialLoading
                    ? _buildLoadingState()
                    : FadeTransition(
                  opacity: _fadeAnimation,
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildActiveTasksTab(),
                      _buildRewardCouponsTab(),
                      _buildHistoryTab(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickStats() {
    final activeTasks = _tasks.length; // 活跃任务
    final completedTasks = (_rewardStats['completed_tasks'] as int?) ?? 0;
    final availableCoupons = _rewardCoupons.length;

    return Container(
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildQuickStatItem('Active\nTasks', activeTasks.toString(), Icons.assignment),
          Container(width: 1, height: 30.h, color: Colors.white.withOpacity(0.3)),
          _buildQuickStatItem('Completed', completedTasks.toString(), Icons.check_circle),
          Container(width: 1, height: 30.h, color: Colors.white.withOpacity(0.3)),
          _buildQuickStatItem('Coupons', availableCoupons.toString(), Icons.card_giftcard),
        ],
      ),
    );
  }

  Widget _buildQuickStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 20.r),
        SizedBox(height: 4.h),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: 16.sp,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 10.sp,
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
            padding: EdgeInsets.all(20.r),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16.r),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20.r,
                  offset: Offset(0, 10.h),
                ),
              ],
            ),
            child: Column(
              children: [
                SizedBox(
                  width: 40.r,
                  height: 40.r,
                  child: const CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4CAF50)),
                  ),
                ),
                SizedBox(height: 16.h),
                Text(
                  'Loading your rewards...',
                  style: TextStyle(
                    fontSize: 16.sp,
                    color: Colors.grey[700],
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

  Widget _buildActiveTasksTab() {
    final activeTasks = _tasks;

    return RefreshIndicator(
      onRefresh: _refreshData,
      color: const Color(0xFF4CAF50),
      child: activeTasks.isEmpty
          ? ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(20.r),
        children: [
          _buildEmptyState(
            icon: Icons.assignment_outlined,
            title: 'No Active Tasks',
            subtitle: 'Complete daily activities to earn rewards',
          ),
        ],
      )
          : ListView.builder(
        padding: EdgeInsets.all(20.r),
        itemCount: activeTasks.length,
        itemBuilder: (context, index) =>
            _buildTaskCard(activeTasks[index], index),
      ),
    );
  }

  Widget _buildRewardCouponsTab() {
    return RefreshIndicator(
      onRefresh: _refreshData,
      color: const Color(0xFF4CAF50),
      child: _rewardCoupons.isEmpty
          ? ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(20.r),
        children: [
          _buildEmptyState(
            icon: Icons.card_giftcard_outlined,
            title: 'No Reward Coupons',
            subtitle: 'Complete tasks to earn reward coupons',
          ),
        ],
      )
          : ListView.builder(
        padding: EdgeInsets.all(20.r),
        itemCount: _rewardCoupons.length,
        itemBuilder: (context, index) =>
            _buildRewardCouponCard(_rewardCoupons[index], index),
      ),
    );
  }

  Widget _buildHistoryTab() {
    return RefreshIndicator(
      onRefresh: _refreshData,
      color: const Color(0xFF4CAF50),
      child: _rewardHistory.isEmpty
          ? ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(20.r),
        children: [
          _buildEmptyState(
            icon: Icons.history_outlined,
            title: 'No History Records',
            subtitle: 'Your reward history will appear here',
          ),
        ],
      )
          : ListView.builder(
        padding: EdgeInsets.all(20.r),
        itemCount: _rewardHistory.length,
        itemBuilder: (context, index) =>
            _buildHistoryCard(_rewardHistory[index], index),
      ),
    );
  }

  Widget _buildTaskCard(Map<String, dynamic> task, int index) {
    final currentCount = task['current_count'] as int? ?? 0;
    final targetCount = task['target_count'] as int? ?? 1;
    final progress = targetCount > 0 ? currentCount / targetCount : 0.0;
    final isCompleted = task['status'] == 'completed';

    return Container(
      margin: EdgeInsets.only(bottom: 16.h),
      padding: EdgeInsets.all(20.r),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 15.r,
            offset: Offset(0, 5.h),
          ),
        ],
        border: isCompleted
            ? Border.all(color: Colors.green.withOpacity(0.3), width: 2)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48.r,
                height: 48.r,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isCompleted
                        ? [Colors.green.shade400, Colors.green.shade600]
                        : [const Color(0xFF4CAF50), const Color(0xFF45A049)],
                  ),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(
                  isCompleted
                      ? Icons.check_circle
                      : _getTaskIcon(task['task_type']),
                  color: Colors.white,
                  size: 24.r,
                ),
              ),
              SizedBox(width: 16.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task['task_name'] ?? _getTaskDisplayName(task['task_type']),
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    if (task['description'] != null) ...[
                      SizedBox(height: 4.h),
                      Text(
                        _normalizeSeparators(_fixUtf8Mojibake(task['description'])),
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 16.h),
          Row(
            children: [
              Text(
                'Progress: $currentCount/$targetCount',
                style: TextStyle(
                  fontSize: 12.sp,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                '${(progress * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 12.sp,
                  color: const Color(0xFF4CAF50),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          ClipRRect(
            borderRadius: BorderRadius.circular(4.r),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(
                isCompleted ? Colors.green : const Color(0xFF4CAF50),
              ),
              minHeight: 6.h,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRewardCouponCard(CouponModel coupon, int index) {
    final fixedTitle = _normalizeSeparators(_fixUtf8Mojibake(coupon.title));
    final fixedDesc  = _normalizeSeparators(_fixUtf8Mojibake(coupon.description));

    return Container(
      margin: EdgeInsets.only(bottom: 16.h),
      padding: EdgeInsets.all(20.r),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: _getCouponColor(coupon.type).withOpacity(0.15),
            blurRadius: 15.r,
            offset: Offset(0, 5.h),
          ),
        ],
        border: Border.all(
          color: _getCouponColor(coupon.type).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48.r,
            height: 48.r,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _getCouponColor(coupon.type),
                  _getCouponColor(coupon.type).withOpacity(0.8),
                ],
              ),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Icon(
              _getCouponIcon(coupon.type),
              color: Colors.white,
              size: 24.r,
            ),
          ),
          SizedBox(width: 16.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fixedTitle,
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 4.h),
                Text(
                  fixedDesc,
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.grey[600],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 8.h),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(6.r),
                  ),
                  child: Text(
                    coupon.code.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10.sp,
                      color: Colors.grey[700],
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (coupon.canPin && coupon.isUsable)
            ElevatedButton(
              onPressed: () => _onUseNowPressed(coupon),
              style: ElevatedButton.styleFrom(
                backgroundColor: _getCouponColor(coupon.type),
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.r),
                ),
              ),
              child: Text(
                'Use Now',
                style: TextStyle(
                  fontSize: 12.sp,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> reward, int index) {
    final createdAt =
        DateTime.tryParse(reward['created_at'] ?? '') ?? DateTime.now();

    // ====== 新逻辑：第一行显示券标题；第二行友好 reason，app/system/auto 隐藏或映射 ======
    final couponTitle = _normalizeSeparators(
      _fixUtf8Mojibake(reward['coupon_title'] ?? 'Coupon Reward'),
    );

    // 友好化 reason：app/system/auto 这类就隐藏；否则做分隔符/乱码修复
    final rawReason = (reward['reward_reason'] ?? '').toString().trim().toLowerCase();
    String prettyReason(String raw, String? type) {
      if (raw.isEmpty || raw == 'app' || raw == 'system' || raw == 'auto') {
        switch ((type ?? '').toLowerCase()) {
          case 'welcome':
            return 'Welcome reward';
          case 'referral_bonus':
            return 'Referral reward';
          case 'activity_bonus':
            return 'Task reward';
          default:
            return ''; // 隐藏
        }
      }
      return _normalizeSeparators(_fixUtf8Mojibake(raw));
    }
    final reason = prettyReason(rawReason, reward['reward_type']);
    // =======================================================================

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10.r,
            offset: Offset(0, 3.h),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40.r,
            height: 40.r,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _getRewardTypeColor(reward['reward_type']),
                  _getRewardTypeColor(reward['reward_type']).withOpacity(0.8),
                ],
              ),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(
              _getRewardTypeIcon(reward['reward_type']),
              color: Colors.white,
              size: 20.r,
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 第一行：券标题
                Text(
                  couponTitle,
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                // 第二行：友好化 reason（可隐藏）
                if (reason.isNotEmpty) ...[
                  SizedBox(height: 2.h),
                  Text(
                    reason,
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: _getRewardTypeColor(reward['reward_type']),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                SizedBox(height: 4.h),
                Text(
                  _formatDateTime(createdAt),
                  style: TextStyle(
                    fontSize: 10.sp,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 80.r,
          height: 80.r,
          decoration: BoxDecoration(
            color: const Color(0xFF4CAF50).withOpacity(0.1),
            borderRadius: BorderRadius.circular(40.r),
          ),
          child: Icon(icon, size: 40.r, color: const Color(0xFF4CAF50)),
        ),
        SizedBox(height: 24.h),
        Text(
          title,
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 8.h),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 32.w),
          child: Text(
            subtitle,
            style: TextStyle(
              fontSize: 14.sp,
              color: Colors.grey[600],
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  void _onUseNowPressed(CouponModel coupon) {
    if (!coupon.canPin || !coupon.isUsable) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SellFormPage(),
        settings: RouteSettings(arguments: {'couponId': coupon.id}),
      ),
    );
  }

  // ===== Helper methods =====
  IconData _getTaskIcon(String? taskType) {
    switch (taskType) {
      case 'publish_items':
        return Icons.publish;
      case 'invite_friends':
        return Icons.group_add;
      case 'daily_check':
        return Icons.check_circle;
      default:
        return Icons.assignment;
    }
  }

  String _getTaskDisplayName(String? taskType) {
    switch (taskType) {
      case 'publish_items':
        return 'Publish Items';
      case 'invite_friends':
        return 'Invite Friends';
      case 'daily_check':
        return 'Daily Check-in';
      default:
        return 'Task';
    }
  }

  IconData _getCouponIcon(CouponType type) {
    final n = _couponTypeName(type);
    switch (n) {
      case 'registerBonus':
      case 'welcome':
        return Icons.card_giftcard;
      case 'activityBonus':
        return Icons.task_alt;
      case 'referralBonus':
        return Icons.group_add;
      case 'hot':
      case 'trending':
        return Icons.local_fire_department;
      case 'category':
        return Icons.push_pin;
      case 'featured':
      case 'boost':
        return Icons.workspace_premium;
      default:
        return Icons.card_giftcard;
    }
  }

  Color _getCouponColor(CouponType type) {
    final n = _couponTypeName(type);
    switch (n) {
      case 'registerBonus':
      case 'welcome':
        return const Color(0xFF4CAF50);
      case 'activityBonus':
        return const Color(0xFF2196F3);
      case 'referralBonus':
        return const Color(0xFFE91E63);
      case 'hot':
      case 'trending':
        return const Color(0xFFFF6B35);
      case 'category':
        return const Color(0xFF2196F3);
      case 'featured':
      case 'boost':
        return const Color(0xFF9C27B0);
      default:
        return const Color(0xFF2196F3);
    }
  }

  Color _getRewardTypeColor(String? rewardType) {
    switch (rewardType) {
      case 'welcome':
      case 'register_bonus':
        return const Color(0xFF4CAF50);
      case 'activity_bonus':
        return const Color(0xFF2196F3);
      case 'referral_bonus':
        return const Color(0xFFE91E63);
      default:
        return Colors.grey;
    }
  }

  IconData _getRewardTypeIcon(String? rewardType) {
    switch (rewardType) {
      case 'welcome':
      case 'register_bonus':
        return Icons.card_giftcard;
      case 'activity_bonus':
        return Icons.task_alt;
      case 'referral_bonus':
        return Icons.group_add;
      default:
        return Icons.card_giftcard;
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    if (difference.inDays < 30) return '${difference.inDays}d ago';
    return '${dateTime.month}/${dateTime.day}';
  }

  /// 将券类型映射为历史卡片用的 reward_type
  String _mapCouponTypeToRewardType(String? t) {
    switch ((t ?? '').toLowerCase()) {
      case 'welcome':
      case 'registerbonus':
        return 'welcome';
      case 'referralbonus':
        return 'referral_bonus';
    // 下面这些都算“活动奖励”
      case 'trending':
      case 'hot':
      case 'category':
      case 'featured':
      case 'boost':
      case 'activitybonus':
        return 'activity_bonus';
      default:
        return 'activity_bonus';
    }
  }

  @override
  bool get wantKeepAlive => true;
}
