// lib/services/welcome_dialog_service.dart
//
// Backward-compatible Welcome dialog service.
//
// ✅ 公共兼容入口：WelcomeDialogService.maybeShow(context)
// ✅ 新逻辑：
//   1) “会话去重”按 uid 存储（_shownForUid）。
//   2) 只在对话框真正关闭后才写本地“已展示”标记（历史两种 key 都写）。
//   3) **彻底移除 user_coupons 查询**，只保留对 coupons 的轻量校验。
//   4) 与 main.dart 新逻辑联动：优先读取 `new_user_welcome_pending_<uid>` 决定是否弹窗，
//      这个 pending 位由 `RewardService.ensureWelcomeForCurrentUser()` 计算并在登录时写入。
//   5) 提供 scheduleCheck(context) 便于首帧后触发，降低与首页首帧竞争。
//
// 依赖：
//   shared_preferences: ^2.0.0+
//   supabase_flutter: any
//
// 可选 UI 依赖（你已有）：
//   import 'package:swaply/widgets/welcome_coupon_dialog.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:swaply/services/reward_service.dart';
import 'package:swaply/widgets/welcome_coupon_dialog.dart';

class WelcomeDialogService {
  WelcomeDialogService._();

  /// 会话级去重（按 uid）
  static final Map<String, bool> _shownForUid = <String, bool>{};

  /// 防并发重复弹
  static bool _isShowing = false;

  /// 旧代码兼容入口
  static Future<void> maybeShow(BuildContext context) async {
    await showWelcomeDialogIfNeeded(context);
  }

  /// 首帧后安排检查（推荐）
  static void scheduleCheck(BuildContext context, {bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // fire-and-forget
      showWelcomeDialogIfNeeded(context, force: force);
    });
  }

  static String _pendingKey(String uid) => 'new_user_welcome_pending_$uid';
  static String _shownGiftKey(String uid) => 'welcome_gift_shown_$uid';
  static String _shownDialogKey(String uid) => 'welcome_dialog_shown_$uid';

  /// 核心：检查并弹出欢迎券对话框
  static Future<void> showWelcomeDialogIfNeeded(
      BuildContext context, {
        bool force = false,
      }) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[WelcomeDialog] no user id (not signed in)');
      }
      return;
    }

    final uid = user.id;

    // —— 1) 会话级去重（按 uid）
    if (!force && (_shownForUid[uid] == true)) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[WelcomeDialog] already shown this session for $uid');
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    // —— 2) 历史“已展示”位（兼容两种 key）
    final alreadyShownEver =
        (prefs.getBool(_shownGiftKey(uid)) ?? false) ||
            (prefs.getBool(_shownDialogKey(uid)) ?? false);
    if (!force && alreadyShownEver) {
      _shownForUid[uid] = true;
      if (kDebugMode) {
        // ignore: avoid_print
        print('[WelcomeDialog] already shown historically for $uid');
      }
      return;
    }

    // —— 3) 与 main.dart 联动的 pending 位
    // main.dart 的 wireAuthHook 在 signedIn/initialSession 时会调用
    // RewardService.ensureWelcomeForCurrentUser()，当 shouldPopup=true 就置位此 pending。
    final hasPending = prefs.getBool(_pendingKey(uid)) == true;

    if (!force && !hasPending) {
      // 未置位则不打扰用户、也不做多余查询
      if (kDebugMode) {
        // ignore: avoid_print
        print('[WelcomeDialog] no pending flag -> skip');
      }
      return;
    }

    // —— 4) 轻量校验 coupons 表，确认确有 welcome 券（不涉及 user_coupons）
    List<Map<String, dynamic>> rows = [];
    try {
      rows = await client
          .from('coupons')
          .select(
        'id, code, title, description, expires_at, created_at, type, status, user_id',
      )
          .eq('user_id', uid)
          .eq('type', 'welcome')
          .limit(1);
      if (rows.isEmpty) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[WelcomeDialog] no welcome coupon -> clear pending & skip');
        }
        // 安全起见：没有券就清掉 pending，避免下次仍判定要弹
        await prefs.setBool(_pendingKey(uid), false);
        return;
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[WelcomeDialog] query coupons failed: $e');
      }
      // 查询失败也清 pending，避免反复尝试；如你希望保留，可改成不清
      await prefs.setBool(_pendingKey(uid), false);
      return;
    }

    // —— 5) 防并发 & 小延迟，降低与首帧竞争
    if (_isShowing) return;
    _isShowing = true;

    await Future<void>.delayed(const Duration(milliseconds: 300));
    // （根据你的 Flutter 版本，如果不支持 context.mounted，可以删掉此判断）
    // ignore: use_build_context_synchronously
    // （你的工程之前使用过此写法，说明版本已支持）
    if (!(context.mounted)) {
      _isShowing = false;
      return;
    }

    if (kDebugMode) {
      // ignore: avoid_print
      print('[WelcomeDialog] found welcome coupon -> showing dialog');
    }

    // —— 6) 真正弹出；关闭后再写已展示
    // ignore: use_build_context_synchronously
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => WelcomeCouponDialog(
        couponData: rows.first,
      ),
    );

    // 关闭后落盘：两种历史键都写，保证向后兼容
    await prefs.setBool(_shownGiftKey(uid), true);
    await prefs.setBool(_shownDialogKey(uid), true);

    // 清掉 pending（只弹一次）
    await prefs.setBool(_pendingKey(uid), false);

    _shownForUid[uid] = true;
    _isShowing = false;

    // —— 7) 保险：若你希望“确保券一定存在”，也可在此补一次无害 Ensure（可选）
    try {
      await RewardService.ensureWelcomeGiftFor(uid);
    } catch (_) {
      // 忽略，保证 UI 不受影响
    }
  }

  /// 调试：清除某个 uid 的会话标记
  static void resetFor(String uid) {
    _shownForUid.remove(uid);
    if (kDebugMode) {
      // ignore: avoid_print
      print('[WelcomeDialog] session flag reset for $uid');
    }
  }

  /// 调试：清除“已展示”历史标记（单用户）
  static Future<void> clearShownFlag(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_shownGiftKey(userId));
    await prefs.remove(_shownDialogKey(userId));
    if (kDebugMode) {
      // ignore: avoid_print
      print('[WelcomeDialog] cleared shown flags for user $userId');
    }
  }

  /// 调试：清除“已展示”历史标记（所有用户）
  static Future<void> clearAllShownFlags() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs
        .getKeys()
        .where((k) =>
    k.startsWith('welcome_gift_shown_') ||
        k.startsWith('welcome_dialog_shown_') ||
        k.startsWith('new_user_welcome_pending_'))
        .toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
    if (kDebugMode) {
      // ignore: avoid_print
      print('[WelcomeDialog] cleared all shown flags (${keys.length} keys)');
    }
  }
}

/// 给 PostgrestFilterBuilder 增加一个安全的 maybeEq 扩展（若列不存在或无该字段，调用方捕获异常后继续）
/// 仅用于本文件“回退查询”的便捷处理；项目里有更完善的封装可替换掉。
extension _MaybeEq on PostgrestFilterBuilder {
  PostgrestFilterBuilder maybeEq(String column, dynamic value) {
    try {
      return eq(column, value);
    } catch (_) {
      // 忽略，返回自身
      return this;
    }
  }
}
