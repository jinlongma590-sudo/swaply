// lib/pages/wishlist_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:swaply/services/dual_favorites_service.dart';
import 'package:swaply/services/favorites_update_service.dart';
import 'package:swaply/pages/product_detail_page.dart';
import 'package:flutter/foundation.dart';

class WishlistPage extends StatefulWidget {
  const WishlistPage({Key? key}) : super(key: key);

  @override
  State<WishlistPage> createState() => _WishlistPageState();
}

class _WishlistPageState extends State<WishlistPage> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  List<Map<String, dynamic>> _wishlistItems = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;
  Timer? _autoRefreshTimer;
  StreamSubscription<FavoriteUpdateEvent>? _favoritesSubscription;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );

    _loadWishlist();
    // 启动自动刷新定时器（每30秒检查一次）
    _startAutoRefresh();
    // 设置收藏更新监听
    _setupFavoritesListener();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoRefreshTimer?.cancel();
    _animationController.dispose();
    _favoritesSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      // 应用重新激活时刷新数据
      _loadWishlist();
    }
  }

  /// 设置收藏更新监听
  void _setupFavoritesListener() {
    _favoritesSubscription = FavoritesUpdateService().favoritesStream.listen(
          (event) {
        if (!mounted) return;

        if (kDebugMode) {
          print('WishlistPage received favorite update: ${event.listingId}, added: ${event.isAdded}');
        }

        if (event.isAdded && event.listingData != null) {
          // 添加到收藏：立即添加到本地列表
          _addToLocalWishlist(event.listingData!);
        } else if (!event.isAdded) {
          // 从收藏移除：立即从本地列表移除
          _removeFromLocalWishlist(event.listingId);
        }
      },
      onError: (error) {
        if (kDebugMode) print('Error in favorites stream: $error');
      },
    );
  }

  /// 立即添加到本地心愿单列表
  void _addToLocalWishlist(Map<String, dynamic> listingData) {
    try {
      // 检查是否已存在
      final listingId = listingData['id']?.toString();
      if (listingId == null) return;

      final exists = _wishlistItems.any((item) =>
      item['listing_id']?.toString() == listingId ||
          item['listing']?['id']?.toString() == listingId
      );

      if (!exists) {
        // 构造符合心愿单格式的数据
        final wishlistItem = {
          'listing_id': listingId,
          'listing': _safeMapConvert(listingData),
          'created_at': DateTime.now().toIso8601String(),
        };

        setState(() {
          _wishlistItems.insert(0, wishlistItem); // 插入到列表开头
        });

        if (kDebugMode) {
          print('Added item to local wishlist: $listingId');
        }
      }
    } catch (e) {
      if (kDebugMode) print('Error adding to local wishlist: $e');
    }
  }

  /// 立即从本地心愿单列表移除
  void _removeFromLocalWishlist(String listingId) {
    try {
      final initialLength = _wishlistItems.length;

      setState(() {
        _wishlistItems.removeWhere((item) =>
        item['listing_id']?.toString() == listingId ||
            item['listing']?['id']?.toString() == listingId
        );
      });

      if (_wishlistItems.length < initialLength) {
        if (kDebugMode) {
          print('Removed item from local wishlist: $listingId');
        }
      }
    } catch (e) {
      if (kDebugMode) print('Error removing from local wishlist: $e');
    }
  }

  /// 启动自动刷新定时器
  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted && !_isRefreshing) {
        if (kDebugMode) print('自动刷新心愿单列表...');
        _loadWishlist();
      }
    });
  }

  /// 安全的类型转换方法
  Map<String, dynamic> _safeMapConvert(dynamic input) {
    if (input == null) return <String, dynamic>{};

    if (input is Map<String, dynamic>) {
      return input;
    } else if (input is Map) {
      try {
        return Map<String, dynamic>.from(input);
      } catch (e) {
        if (kDebugMode) print('类型转换失败: $e');
        return <String, dynamic>{};
      }
    }

    return <String, dynamic>{};
  }

  /// 加载收藏列表
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

      // 修复：使用 DualFavoritesService 获取心愿单列表
      final rawItems = await DualFavoritesService.getUserWishlist(
        userId: user.id,
        limit: 100,
      );

      if (mounted) {
        // 安全转换数据
        final safeItems = <Map<String, dynamic>>[];
        for (final item in rawItems) {
          final safeItem = _safeMapConvert(item);
          if (safeItem.isNotEmpty) {
            // 确保 listing 数据也是安全转换的
            if (safeItem.containsKey('listing')) {
              safeItem['listing'] = _safeMapConvert(safeItem['listing']);
            }
            safeItems.add(safeItem);
          }
        }

        setState(() {
          _wishlistItems = safeItems;
          _isLoading = false;
        });

        _animationController.forward();

        if (kDebugMode) {
          print('Loaded ${_wishlistItems.length} wishlist items');
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

  /// 刷新收藏列表
  Future<void> _refreshWishlist() async {
    setState(() => _isRefreshing = true);
    await _loadWishlist();
    setState(() => _isRefreshing = false);
  }

  /// 从收藏夹移除商品
  Future<void> _removeFromWishlist(String listingId, int index) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      // 修复：使用 DualFavoritesService 同步移除
      final success = await DualFavoritesService.removeFromFavorites(
        userId: user.id,
        listingId: listingId,
      );

      if (success && mounted) {
        setState(() {
          _wishlistItems.removeAt(index);
        });

        // 发送实时更新通知
        FavoritesUpdateService().notifyFavoriteChanged(
          listingId: listingId,
          isAdded: false,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 12.sp),
                SizedBox(width: 6.w),
                Text('Removed from favorites and wishlist', style: TextStyle(fontSize: 10.sp)),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
            margin: EdgeInsets.all(8.w),
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
              Icon(Icons.error_outline_rounded, color: Colors.white, size: 12.sp),
              SizedBox(width: 6.w),
              Expanded(child: Text('Failed to remove item. Please try again.', style: TextStyle(fontSize: 10.sp))),
            ],
          ),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
          margin: EdgeInsets.all(8.w),
        ),
      );
    }
  }

  /// 获取商品图片 - 安全版本
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

  /// 格式化价格 - 安全版本
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

  /// 安全获取字符串值
  String _safeGetString(Map<String, dynamic> map, String key, {String defaultValue = ''}) {
    try {
      return map[key]?.toString() ?? defaultValue;
    } catch (e) {
      if (kDebugMode) print('Error getting string for key $key: $e');
      return defaultValue;
    }
  }

  /// 构建商品卡片 - 修复版本
  Widget _buildListingCard(Map<String, dynamic> item, int index) {
    try {
      // 安全的类型转换 - 统一使用 'listing' 键
      final safeListing = _safeMapConvert(item['listing'] ?? item['listings'] ?? {});
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

      // 格式化收藏时间
      String timeAdded = 'Recently';
      if (createdAt.isNotEmpty) {
        try {
          final date = DateTime.parse(createdAt);
          final now = DateTime.now();
          final difference = now.difference(date);

          if (difference.inMinutes < 60) {
            timeAdded = '${difference.inMinutes}m ago';
          } else if (difference.inHours < 24) {
            timeAdded = '${difference.inHours}h ago';
          } else if (difference.inDays < 7) {
            timeAdded = '${difference.inDays}d ago';
          } else {
            timeAdded = '${date.day}/${date.month}/${date.year}';
          }
        } catch (e) {
          timeAdded = 'Recently';
        }
      }

      return Container(
        margin: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12.r,
              offset: Offset(0, 2.h),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
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
                  // 从商品详情页返回后刷新列表
                  _loadWishlist();
                });
              }
            },
            borderRadius: BorderRadius.circular(12.r),
            child: Padding(
              padding: EdgeInsets.all(8.w),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 商品图片 - 缩小
                  Hero(
                    tag: 'wishlist_image_$listingId',
                    child: Container(
                      width: 50.w,
                      height: 50.h,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8.r),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 3.r,
                            offset: Offset(0, 1.h),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8.r),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Colors.grey.shade50, Colors.grey.shade100],
                            ),
                          ),
                          child: imageUrl.startsWith('http')
                              ? Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                Icons.image_not_supported_rounded,
                                color: Colors.grey.shade400,
                                size: 20.w,
                              );
                            },
                          )
                              : Image.asset(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                Icons.image_not_supported_rounded,
                                color: Colors.grey.shade400,
                                size: 20.w,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 8.w),

                  // 商品信息 - 缩小字体
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade800,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 2.h),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                            ),
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          child: Text(
                            price,
                            style: TextStyle(
                              fontSize: 10.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        SizedBox(height: 3.h),
                        if (city.isNotEmpty)
                          Row(
                            children: [
                              Icon(
                                Icons.location_on_rounded,
                                size: 10.w,
                                color: Colors.grey.shade500,
                              ),
                              SizedBox(width: 2.w),
                              Expanded(
                                child: Text(
                                  city,
                                  style: TextStyle(
                                    fontSize: 9.sp,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        SizedBox(height: 1.h),
                        Row(
                          children: [
                            Icon(
                              Icons.schedule_rounded,
                              size: 9.w,
                              color: Colors.grey.shade400,
                            ),
                            SizedBox(width: 2.w),
                            Text(
                              'Added $timeAdded',
                              style: TextStyle(
                                fontSize: 8.sp,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // 移除按钮 - 缩小
                  Container(
                    width: 26.w,
                    height: 26.h,
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(6.r),
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.favorite_rounded,
                        color: Colors.red.shade400,
                        size: 14.w,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: () => _showRemoveDialog(listingId, title, index),
                      tooltip: 'Remove from wishlist',
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
        print('Error building listing card at index $index: $e');
        print('Stack trace: $stackTrace');
        print('Item data: $item');
      }
      // 返回错误卡片而不是崩溃
      return Container(
        margin: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12.r),
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

  /// 显示移除确认对话框
  void _showRemoveDialog(String listingId, String title, int index) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
          title: Text(
            'Remove from Wishlist',
            style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Are you sure you want to remove "$title" from your wishlist and favorites?',
            style: TextStyle(fontSize: 11.sp, color: Colors.grey.shade700),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
              ),
              child: Text(
                'Cancel',
                style: TextStyle(fontSize: 11.sp, color: Colors.grey.shade600),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _removeFromWishlist(listingId, index);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade500,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
              ),
              child: Text(
                'Remove',
                style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 构建空状态 - 紧凑版
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.grey.shade50, Colors.grey.shade100],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.favorite_border_rounded,
                size: 48.w,
                color: Colors.grey.shade400,
              ),
            ),
            SizedBox(height: 14.h),
            Text(
              'Your Wishlist is Empty',
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              'Start adding items you like to your wishlist by tapping the heart icon on any listing.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.sp,
                color: Colors.grey.shade600,
                height: 1.3,
              ),
            ),
            SizedBox(height: 16.h),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                ),
                borderRadius: BorderRadius.circular(8.r),
                boxShadow: [
                  BoxShadow(
                    color: Color(0xFF667EEA).withOpacity(0.3),
                    blurRadius: 8.r,
                    offset: Offset(0, 2.h),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
                ),
                child: Text(
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

  /// 构建错误状态 - 紧凑版
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 48.w,
                color: Colors.red.shade400,
              ),
            ),
            SizedBox(height: 14.h),
            Text(
              'Something went wrong',
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              _errorMessage ?? 'Failed to load your wishlist.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.sp,
                color: Colors.grey.shade600,
                height: 1.3,
              ),
            ),
            SizedBox(height: 16.h),
            ElevatedButton(
              onPressed: _loadWishlist,
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF667EEA),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
                elevation: 2.r,
              ),
              child: Text(
                'Try Again',
                style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w600),
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
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(
          'My Wishlist (${_wishlistItems.length})',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 14.sp,
          ),
        ),
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white, size: 16.w),
        actions: [
          if (_wishlistItems.isNotEmpty && !_isLoading)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, color: Colors.white, size: 16.w),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
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
                      Icon(Icons.clear_all_rounded, color: Colors.red, size: 14.w),
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
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667EEA)),
          strokeWidth: 2.w,
        ),
      )
          : _errorMessage != null
          ? _buildErrorState()
          : _wishlistItems.isEmpty
          ? FadeTransition(
        opacity: _fadeAnimation,
        child: _buildEmptyState(),
      )
          : RefreshIndicator(
        onRefresh: _refreshWishlist,
        color: Color(0xFF667EEA),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ListView.builder(
            padding: EdgeInsets.symmetric(vertical: 8.h),
            itemCount: _wishlistItems.length,
            itemBuilder: (context, index) {
              return _buildListingCard(_wishlistItems[index], index);
            },
          ),
        ),
      ),
    );
  }

  /// 显示清空所有确认对话框
  void _showClearAllDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
          title: Text(
            'Clear Wishlist',
            style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Are you sure you want to remove all items from your wishlist and favorites? This action cannot be undone.',
            style: TextStyle(fontSize: 11.sp, color: Colors.grey.shade700),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
              ),
              child: Text(
                'Cancel',
                style: TextStyle(fontSize: 11.sp, color: Colors.grey.shade600),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _clearAllWishlist();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade500,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
              ),
              child: Text(
                'Clear All',
                style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 清空所有收藏
  Future<void> _clearAllWishlist() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      // 修复：使用 DualFavoritesService 同步清空
      final success = await DualFavoritesService.clearUserFavorites(userId: user.id);

      if (success && mounted) {
        setState(() {
          _wishlistItems.clear();
        });

        // 发送实时清空通知
        for (final item in _wishlistItems) {
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
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 12.sp),
                SizedBox(width: 6.w),
                Text('Wishlist and favorites cleared successfully', style: TextStyle(fontSize: 10.sp)),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
            margin: EdgeInsets.all(8.w),
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
              Icon(Icons.error_outline_rounded, color: Colors.white, size: 12.sp),
              SizedBox(width: 6.w),
              Expanded(child: Text('Failed to clear wishlist. Please try again.', style: TextStyle(fontSize: 10.sp))),
            ],
          ),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
          margin: EdgeInsets.all(8.w),
        ),
      );
    }
  }
}