// lib/services/notification_service.dart - 单例化订阅版本（支持 onEvent 回调）
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef NotificationEventCallback = void Function(
    Map<String, dynamic> notification,
    );

enum NotificationType {
  offer('offer'),
  wishlist('wishlist'),
  system('system'),
  message('message'),
  purchase('purchase'),
  priceDrop('price_drop');

  const NotificationType(this.value);
  final String value;
}

class NotificationService {
  static final SupabaseClient _client = Supabase.instance.client;
  static const String _tableName = 'notifications';

  // ===== 核心订阅管理 =====
  static String? _currentUserId;
  static RealtimeChannel? _channel;

  static bool get isSubscribed => _channel != null && _currentUserId != null;

  static void _debugPrint(String message) {
    if (kDebugMode) {
      print('[NotificationService] $message');
    }
  }

  /// 订阅用户通知（幂等）：
  /// - 若已订阅相同 userId，会直接返回
  /// - 命名参数 [onEvent]：当有新的通知（INSERT）写入时回调
  static Future<void> subscribeUser(
      String userId, {
        NotificationEventCallback? onEvent,
      }) async {
    // 如果已经订阅同一用户，直接返回
    if (_currentUserId == userId && _channel != null) {
      _debugPrint('Already subscribed for user: $userId');
      return;
    }

    // 先清理旧订阅
    await unsubscribe();

    // 创建新订阅
    _currentUserId = userId;
    final ch = _client.channel('notifications:user:$userId');

    ch.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: _tableName,
      // 仅监听该用户的通知
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'recipient_id',
        value: userId,
      ),
      callback: (payload) {
        final rec = payload.newRecord;
        if (rec == null) return;
        final data = Map<String, dynamic>.from(rec);
        _debugPrint('New notification received: $data');
        if (onEvent != null) onEvent(data);
      },
    );

    await ch.subscribe();
    _channel = ch;
    _debugPrint('Subscribed to notifications for user: $userId');
  }

  /// 取消订阅（幂等）
  static Future<void> unsubscribe() async {
    if (_channel != null) {
      try {
        await _client.removeChannel(_channel!);
      } catch (_) {}
      _debugPrint('Unsubscribed from notifications');
    }
    _channel = null;
    _currentUserId = null;
  }

  // ========== 通知创建方法 ==========

  static Future<Map<String, dynamic>?> createNotification({
    required String recipientId,
    String? senderId,
    required NotificationType type,
    required String title,
    required String message,
    String? listingId,
    String? offerId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      _debugPrint('Creating notification: $title for user $recipientId');

      final currentUser = _client.auth.currentUser;
      final data = {
        'recipient_id': recipientId,
        'sender_id': senderId ?? currentUser?.id,
        'type': type.value,
        'title': title,
        'message': message,
        'listing_id': listingId,
        'offer_id': offerId,
        'metadata': metadata ?? <String, dynamic>{},
        'created_at': DateTime.now().toIso8601String(),
        'is_read': false,
        'is_deleted': false,
      };

      final result =
      await _client.from(_tableName).insert(data).select().single();
      _debugPrint('Notification created successfully: ${result['id']}');

      return Map<String, dynamic>.from(result);
    } catch (e) {
      _debugPrint('Error creating notification: $e');
      return null;
    }
  }

  static Future<bool> createMessageNotification({
    required String recipientId,
    required String senderId,
    required String offerId,
    required String senderName,
    required String messageContent,
  }) async {
    try {
      final currentUser = _client.auth.currentUser;
      if (currentUser?.id == recipientId) {
        return true; // 不给自己发通知
      }

      final notification = await createNotification(
        recipientId: recipientId,
        senderId: senderId,
        type: NotificationType.message,
        title: 'New message from $senderName',
        message: messageContent.length > 50
            ? '${messageContent.substring(0, 50)}...'
            : messageContent,
        offerId: offerId,
        metadata: {
          'sender_name': senderName,
          'full_message': messageContent,
        },
      );

      return notification != null;
    } catch (e) {
      _debugPrint('Error creating message notification: $e');
      return false;
    }
  }

  static Future<bool> createOfferNotification({
    required String sellerId,
    required String buyerId,
    required String listingId,
    required double offerAmount,
    required String listingTitle,
    String? buyerName,
    String? buyerPhone,
    String? message,
  }) async {
    try {
      final displayName = buyerName ?? 'Someone';
      final notification = await createNotification(
        recipientId: sellerId,
        senderId: buyerId,
        type: NotificationType.offer,
        title: 'New Offer Received',
        message:
        '$displayName made an offer of \$${offerAmount.toStringAsFixed(0)} for your $listingTitle',
        listingId: listingId,
        metadata: {
          'offer_amount': offerAmount,
          'buyer_name': displayName,
          'buyer_phone': buyerPhone,
          'buyer_message': message,
          'listing_title': listingTitle,
        },
      );
      return notification != null;
    } catch (e) {
      _debugPrint('Error creating offer notification: $e');
      return false;
    }
  }

  static Future<bool> createWishlistNotification({
    required String sellerId,
    required String likerId,
    required String listingId,
    required String listingTitle,
    String? likerName,
  }) async {
    try {
      if (sellerId == likerId) return true; // 不给自己发通知

      final displayName = likerName ?? 'Someone';
      final notification = await createNotification(
        recipientId: sellerId,
        senderId: likerId,
        type: NotificationType.wishlist,
        title: 'Item Added to Wishlist',
        message:
        '$displayName added your $listingTitle to their wishlist',
        listingId: listingId,
        metadata: {
          'liker_name': displayName,
          'listing_title': listingTitle,
        },
      );
      return notification != null;
    } catch (e) {
      _debugPrint('Error creating wishlist notification: $e');
      return false;
    }
  }

  static Future<bool> createSystemNotification({
    required String recipientId,
    required String title,
    required String message,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final notification = await createNotification(
        recipientId: recipientId,
        type: NotificationType.system,
        title: title,
        message: message,
        metadata: metadata,
      );
      return notification != null;
    } catch (e) {
      _debugPrint('Error creating system notification: $e');
      return false;
    }
  }

  // ========== 通知查询方法 ==========

  static Future<List<Map<String, dynamic>>> getUserNotifications({
    String? userId,
    int limit = 50,
    int offset = 0,
    bool includeRead = true,
  }) async {
    try {
      final targetUserId = userId ?? _client.auth.currentUser?.id;
      if (targetUserId == null || targetUserId.isEmpty) {
        _debugPrint('No user ID provided');
        return [];
      }

      _debugPrint('Fetching notifications for user: $targetUserId');

      var query = _client
          .from(_tableName)
          .select('*')
          .eq('recipient_id', targetUserId)
          .eq('is_deleted', false);

      if (!includeRead) {
        query = query.eq('is_read', false);
      }

      final data = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return List<Map<String, dynamic>>.from(
        data.map((e) => Map<String, dynamic>.from(e)),
      );
    } catch (e) {
      _debugPrint('Error fetching notifications: $e');
      return [];
    }
  }

  static Future<int> getUnreadNotificationsCount({String? userId}) async {
    try {
      final targetUserId = userId ?? _client.auth.currentUser?.id;
      if (targetUserId == null || targetUserId.isEmpty) return 0;

      final data = await _client
          .from(_tableName)
          .select('id')
          .eq('recipient_id', targetUserId)
          .eq('is_read', false)
          .eq('is_deleted', false);

      return (data as List).length;
    } catch (e) {
      _debugPrint('Error getting unread count: $e');
      return 0;
    }
  }

  static Future<bool> markNotificationAsRead(String notificationId) async {
    try {
      final currentUserId = _client.auth.currentUser?.id;
      if (currentUserId == null || currentUserId.isEmpty) return false;

      _debugPrint('Marking notification as read: $notificationId');

      await _client
          .from(_tableName)
          .update({
        'is_read': true,
        'read_at': DateTime.now().toIso8601String(),
      })
          .eq('id', notificationId)
          .eq('recipient_id', currentUserId);

      return true;
    } catch (e) {
      _debugPrint('Error marking notification as read: $e');
      return false;
    }
  }

  static Future<bool> markAllNotificationsAsRead({String? userId}) async {
    try {
      final targetUserId = userId ?? _client.auth.currentUser?.id;
      if (targetUserId == null || targetUserId.isEmpty) return false;

      _debugPrint('Marking all notifications as read for user: $targetUserId');

      await _client
          .from(_tableName)
          .update({
        'is_read': true,
        'read_at': DateTime.now().toIso8601String(),
      })
          .eq('recipient_id', targetUserId)
          .eq('is_read', false);

      return true;
    } catch (e) {
      _debugPrint('Error marking all notifications as read: $e');
      return false;
    }
  }

  static Future<bool> deleteNotification(String notificationId) async {
    try {
      final currentUserId = _client.auth.currentUser?.id;
      if (currentUserId == null || currentUserId.isEmpty) return false;

      _debugPrint('Deleting notification: $notificationId');

      await _client
          .from(_tableName)
          .update({'is_deleted': true})
          .eq('id', notificationId)
          .eq('recipient_id', currentUserId);

      return true;
    } catch (e) {
      _debugPrint('Error deleting notification: $e');
      return false;
    }
  }

  static Future<bool> clearAllNotifications({String? userId}) async {
    try {
      final targetUserId = userId ?? _client.auth.currentUser?.id;
      if (targetUserId == null || targetUserId.isEmpty) return false;

      _debugPrint('Clearing all notifications for user: $targetUserId');

      await _client
          .from(_tableName)
          .update({'is_deleted': true})
          .eq('recipient_id', targetUserId);

      return true;
    } catch (e) {
      _debugPrint('Error clearing all notifications: $e');
      return false;
    }
  }

  // ========== 辅助方法 ==========

  static String getNotificationIcon(String type) {
    switch (type) {
      case 'offer':
        return '💰';
      case 'wishlist':
        return '❤️';
      case 'purchase':
        return '🛒';
      case 'message':
        return '💬';
      case 'price_drop':
        return '📉';
      case 'system':
      default:
        return '🔔';
    }
  }

  static int getNotificationColor(String type) {
    switch (type) {
      case 'offer':
        return 0xFF4CAF50;
      case 'wishlist':
        return 0xFFE91E63;
      case 'purchase':
        return 0xFF2196F3;
      case 'message':
        return 0xFFFF9800;
      case 'price_drop':
        return 0xFF9C27B0;
      case 'system':
      default:
        return 0xFF607D8B;
    }
  }

  static String formatNotificationTime(String createdAt) {
    try {
      final date = DateTime.parse(createdAt);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inMinutes < 1) return 'Just now';
      if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
      if (difference.inHours < 24) return '${difference.inHours}h ago';
      if (difference.inDays < 7) return '${difference.inDays}d ago';
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return 'Unknown';
    }
  }

  static Future<bool> sendWelcomeNotification(String userId) async {
    return createSystemNotification(
      recipientId: userId,
      title: 'Welcome to Swaply!',
      message: 'Thank you for joining our marketplace!',
      metadata: {'welcome_notification': true},
    );
  }

  static Future<bool> testConnection() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null || userId.isEmpty) return false;
      await getUnreadNotificationsCount(userId: userId);
      return true;
    } catch (e) {
      _debugPrint('Connection test failed: $e');
      return false;
    }
  }
}
