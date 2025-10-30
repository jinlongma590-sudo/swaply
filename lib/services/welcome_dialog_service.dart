// lib/services/welcome_dialog_service.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swaply/widgets/welcome_coupon_dialog.dart'; // 添加这行导入

class WelcomeDialogService {
  static bool _welcomeShownThisSession = false;

  /// 检查并显示欢迎券弹窗（带轻量重试）
  static Future<void> showWelcomeDialogIfNeeded(BuildContext context) async {
    // 本次会话已显示过，跳过
    if (_welcomeShownThisSession) {
      if (kDebugMode) print('[WelcomeDialog] Already shown this session');
      return;
    }

    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      if (kDebugMode) print('[WelcomeDialog] No user ID');
      return;
    }

    // 检查本地存储，是否已经显示过
    final prefs = await SharedPreferences.getInstance();
    final shownKey = 'welcome_dialog_shown_$uid';
    if (prefs.getBool(shownKey) == true) {
      if (kDebugMode) print('[WelcomeDialog] Already shown for user $uid');
      return;
    }

    // 小重试：0s / 1s / 3s
    for (final delay in [Duration.zero, const Duration(seconds: 1), const Duration(seconds: 3)]) {
      if (delay > Duration.zero) {
        if (kDebugMode) print('[WelcomeDialog] Retrying after ${delay.inSeconds}s...');
        await Future.delayed(delay);
      }

      try {
        // 查询用户的欢迎券
        final rows = await Supabase.instance.client
            .from('coupons')
            .select('id, code, title, description, expires_at, created_at, type')
            .eq('user_id', uid)
            .eq('type', 'welcome')
            .eq('status', 'active')
            .order('created_at', ascending: false)
            .limit(1);

        if (rows is List && rows.isNotEmpty) {
          if (kDebugMode) print('[WelcomeDialog] Found welcome coupon, showing dialog');

          _welcomeShownThisSession = true;

          // 标记已显示
          await prefs.setBool(shownKey, true);

          // 显示弹窗
          if (context.mounted) {
            await showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => WelcomeCouponDialog(couponData: rows.first),
            );
          }
          break; // 成功显示，退出循环
        } else {
          if (kDebugMode) print('[WelcomeDialog] No welcome coupon found yet');
        }
      } catch (e) {
        if (kDebugMode) print('[WelcomeDialog] Error checking welcome coupon: $e');
        // 继续重试
      }
    }
  }

  /// 重置会话标记（用于测试或切换账号）
  static void resetSessionFlag() {
    _welcomeShownThisSession = false;
    if (kDebugMode) print('[WelcomeDialog] Session flag reset');
  }

  /// 清除特定用户的已显示标记（用于测试）
  static Future<void> clearShownFlag(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final shownKey = 'welcome_dialog_shown_$userId';
    await prefs.remove(shownKey);
    if (kDebugMode) print('[WelcomeDialog] Cleared shown flag for user $userId');
  }

  /// 清除所有已显示标记（用于测试）
  static Future<void> clearAllShownFlags() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((key) => key.startsWith('welcome_dialog_shown_')).toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
    if (kDebugMode) print('[WelcomeDialog] Cleared all shown flags (${keys.length} users)');
  }
}