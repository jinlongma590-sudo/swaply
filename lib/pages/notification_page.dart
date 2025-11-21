import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:swaply/core/l10n/app_localizations.dart';
import 'package:swaply/router/root_nav.dart'; // navPush / navReplaceAll
import 'package:swaply/theme/constants.dart'; // kPrimaryBlue / kCustomHeaderHeight
import 'package:swaply/services/notification_service.dart';

class NotificationPage extends StatefulWidget {
  final VoidCallback? onClearBadge;
  final bool isGuest;
  final Function(int)? onNotificationCountChanged;

  const NotificationPage({
    super.key,
    this.onClearBadge,
    this.isGuest = false,
    this.onNotificationCountChanged,
  });

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;

  // 统一蓝色大标题头
  Widget _buildCustomHeader(String title) {
    final l10n = AppLocalizations.of(context)!;
    final unreadCount =
        _notifications.where((n) => n['is_read'] != true).length;
    final displayTitle =
        '$title${unreadCount > 0 ? ' ($unreadCount)' : ''}';

    return Container(
      color: kPrimaryBlue,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 16.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      displayTitle,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24.sp,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_notifications.isNotEmpty)
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert_rounded,
                          color: Colors.white, size: 18.r),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.r),
                      ),
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
                              Icon(Icons.done_all_rounded,
                                  size: 14.r,
                                  color: Colors.grey.shade600),
                              SizedBox(width: 8.w),
                              Text(l10n.markAllAsRead,
                                  style: TextStyle(fontSize: 12.sp)),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'clear_all',
                          child: Row(
                            children: [
                              Icon(Icons.clear_all_rounded,
                                  color: Colors.red, size: 14.r),
                              SizedBox(width: 8.w),
                              Text(
                                l10n.clearAll,
                                style: TextStyle(
                                    fontSize: 12.sp, color: Colors.red),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            SizedBox(height: 16.h),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    if (!widget.isGuest) {
      _loadNotifications();
      _subscribeToNotifications();
    } else {
      _isLoading = false;
    }

    // 清空角标（如果底栏需要）
    if (widget.onClearBadge != null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => widget.onClearBadge!());
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

      if (!mounted) return;
      setState(() {
        _notifications = notifications;
        _isLoading = false;
      });
      _updateUnreadCount();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Notifications] _loadNotifications error: $e');
      }
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _subscribeToNotifications() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    await NotificationService.subscribeUser(
      user.id,
      onEvent: (Map<String, dynamic> notification) {
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
    final unreadCount =
        _notifications.where((n) => n['is_read'] != true).length;
    widget.onNotificationCountChanged?.call(unreadCount);
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
          _notifications[index]['read_at'] =
              DateTime.now().toIso8601String();
        });
        _updateUnreadCount();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Notifications] _markAsRead error: $e');
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
                Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 14.sp),
                SizedBox(width: 6.w),
                Text(l10n.notificationDeleted,
                    style: TextStyle(fontSize: 12.sp)),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6.r)),
            margin: EdgeInsets.all(8.w),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Notifications] _deleteNotification error: $e');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline_rounded,
                  color: Colors.white, size: 14.sp),
              SizedBox(width: 6.w),
              Text('Failed to delete notification',
                  style: TextStyle(fontSize: 12.sp)),
            ],
          ),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6.r)),
          margin: EdgeInsets.all(8.w),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      final success = await NotificationService.markAllNotificationsAsRead();

      if (success && mounted) {
        setState(() {
          for (var n in _notifications) {
            n['is_read'] = true;
            n['read_at'] = DateTime.now().toIso8601String();
          }
        });
        _updateUnreadCount();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Notifications] _markAllAsRead error: $e');
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
        debugPrint('[Notifications] _clearAll error: $e');
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
        backgroundColor:
        isError ? Colors.red.shade600 : const Color(0xFF4CAF50),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6.r)),
        margin: EdgeInsets.all(8.w),
        duration: Duration(seconds: isError ? 3 : 2),
      ),
    );
  }

  // 点击通知 → 解析并路由（统一根导航）
  void _handleNotificationTap(Map<String, dynamic> notification) async {
    final index = _notifications.indexOf(notification);
    if (index >= 0) {
      _markAsRead(index);
    }

    final type = notification['type']?.toString() ?? '';

    String? listingId = notification['listing_id']?.toString();
    String? offerId = notification['offer_id']?.toString();

    final payload = notification['payload'] as Map<String, dynamic>? ?? {};
    if ((listingId == null || listingId.isEmpty) && payload.isNotEmpty) {
      listingId = payload['listing_id']?.toString();
    }
    if ((offerId == null || offerId.isEmpty) && payload.isNotEmpty) {
      offerId = payload['offer_id']?.toString();
    }

    final metadata = notification['metadata'] as Map<String, dynamic>? ?? {};
    if ((listingId == null || listingId.isEmpty) && metadata.isNotEmpty) {
      listingId = metadata['listing_id']?.toString();
    }
    if ((offerId == null || offerId.isEmpty) && metadata.isNotEmpty) {
      offerId = metadata['offer_id']?.toString();
    }

    if (type.isEmpty) {
      _showSnack('Notification data is incomplete', isError: true);
      return;
    }

    switch (type) {
      case 'message':
        if (offerId != null && offerId.isNotEmpty) {
          await navPush('/offer', arguments: offerId);
        } else {
          _showSnack('Cannot open message: missing offer ID', isError: true);
        }
        break;

      case 'offer':
      case 'system':
        if (offerId != null && offerId.isNotEmpty) {
          await navPush('/offer', arguments: offerId);
        } else if (listingId != null && listingId.isNotEmpty) {
          await navPush('/listing', arguments: listingId);
        } else {
          _showSnack('Cannot open notification: missing required IDs',
              isError: true);
        }
        break;

      case 'wishlist':
      case 'price_drop':
      default:
        if (listingId != null && listingId.isNotEmpty) {
          await navPush('/listing', arguments: listingId);
        } else {
          _showSnack('Cannot open notification: missing listing ID',
              isError: true);
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (widget.isGuest) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          backgroundColor: kPrimaryBlue,
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
                  gradient: LinearGradient(
                    colors: [kPrimaryBlue, const Color(0xFF1E88E5)],
                  ),
                  borderRadius: BorderRadius.circular(10.r),
                  boxShadow: [
                    BoxShadow(
                      color: kPrimaryBlue.withOpacity(0.3),
                      blurRadius: 8.r,
                      offset: Offset(0, 3.h),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await navReplaceAll('/welcome'); // 统一路由
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: EdgeInsets.symmetric(
                        horizontal: 20.w, vertical: 10.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                  ),
                  icon: Icon(Icons.login_rounded,
                      size: 14.r, color: Colors.white),
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

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kCustomHeaderHeight),
        child: _buildCustomHeader(l10n.notifications),
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
                color: kPrimaryBlue.withOpacity(0.08),
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
                      kPrimaryBlue.withOpacity(0.2),
                      kPrimaryBlue.withOpacity(0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20.r),
                ),
                child: Center(
                  child: SizedBox(
                    width: 20.w,
                    height: 20.w,
                    child: const CircularProgressIndicator(
                      valueColor:
                      AlwaysStoppedAnimation<Color>(kPrimaryBlue),
                      strokeWidth: 2.5,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 12.h),
              Text(
                'Loading notifications...',
                style: TextStyle(
                  color: kPrimaryBlue,
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
                    kPrimaryBlue.withOpacity(0.1),
                    const Color(0xFF1E88E5).withOpacity(0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(30.r),
                border: Border.all(
                  color: kPrimaryBlue.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.notifications_none_rounded,
                size: 30.r,
                color: kPrimaryBlue,
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
        color: kPrimaryBlue,
        backgroundColor: Colors.white,
        strokeWidth: 2.w,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: _notifications.length,
          itemBuilder: (context, index) {
            final notification = _notifications[index];
            final isRead = notification['is_read'] == true;
            final type = notification['type']?.toString() ?? '';
            final createdAt =
                notification['created_at']?.toString() ?? '';

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
                    : kPrimaryBlue.withOpacity(0.03),
                margin: EdgeInsets.only(bottom: 0.5.h),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _handleNotificationTap(notification),
                    splashColor:
                    kPrimaryBlue.withOpacity(0.1),
                    highlightColor:
                    kPrimaryBlue.withOpacity(0.05),
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
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
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
                                        overflow:
                                        TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (!isRead)
                                      Container(
                                        width: 6.w,
                                        height: 6.w,
                                        margin: EdgeInsets.only(
                                            left: 6.w),
                                        decoration:
                                        const BoxDecoration(
                                          color: kPrimaryBlue,
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
                                      NotificationService
                                          .formatNotificationTime(
                                          createdAt),
                                      style: TextStyle(
                                        fontSize: 10.sp,
                                        color: Colors
                                            .grey.shade400,
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

class NoGlowScrollBehavior extends ScrollBehavior {
  @override
  Widget buildOverscrollIndicator(
      BuildContext context,
      Widget child,
      ScrollableDetails details, // 新签名
      ) {
    return child;
  }
}

const _kPrivacyUrl = 'https://www.swaply.cc/privacy';
const _kDeleteUrl = 'https://www.swaply.cc/delete-account';
