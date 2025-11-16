// lib/services/welcome_dialog_service.dart
//
// Backward-compatible Welcome dialog service.
//
// ✅ Public API for旧代码兼容：`WelcomeDialogService.maybeShow(context)`
// ✅ 新逻辑修复：
//   1) “已弹过”会话标记按 **uid 维度** 存储（不会误伤新账号）。
//   2) 仅在 **对话框真正关闭后** 才写入本地“已展示”标记（防止误判）。
//   3) 先轻量确保欢迎券存在（RewardService），再查询；查询优先 user_coupons，缺省回退 coupons。
//   4) 同时兼容两种历史本地键：`welcome_gift_shown_$uid` 与 `welcome_dialog_shown_$uid`。
//   5) 提供 `scheduleCheck(context)` 便于首帧后调用，避免与首页构建竞争。
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

  /// 会话级去重（按 uid 维度）
  static final Map<String, bool> _shownForUid = <String, bool>{};

  /// 防并发重复弹
  static bool _isShowing = false;

  /// 旧代码兼容入口：HomePage 里可直接调用
  static Future<void> maybeShow(BuildContext context) async {
    await showWelcomeDialogIfNeeded(context);
  }

  /// 首帧后安排检查（推荐放在拿到 context 的地方调用）
  static void scheduleCheck(BuildContext context, {bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // fire-and-forget
      showWelcomeDialogIfNeeded(context, force: force);
    });
  }

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

    // 会话级去重（按 uid）
    if (!force && (_shownForUid[uid] == true)) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[WelcomeDialog] already shown this session for $uid');
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    // 兼容两种历史本地键（任一为 true 即视为已展示过）
    final keyGift = 'welcome_gift_shown_$uid';
    final keyDialog = 'welcome_dialog_shown_$uid';
    final alreadyShownEver =
        (prefs.getBool(keyGift) ?? false) || (prefs.getBool(keyDialog) ?? false);

    if (!force && alreadyShownEver) {
      _shownForUid[uid] = true; // 同步会话位，减少重复判断
      if (kDebugMode) {
        // ignore: avoid_print
        print('[WelcomeDialog] already shown historically for $uid');
      }
      return;
    }

    // 1) 轻量确保服务端存在欢迎券（若已存在，此调用为 no-op；失败不阻断）
    try {
      await RewardService.ensureWelcomeGiftFor(uid);
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[WelcomeDialog] ensure welcome gift failed: $e');
      }
    }

    // 2) 查询是否存在“welcome”券（优先 user_coupons，失败回退 coupons）
    List<dynamic> rows = const [];
    try {
      rows = await client
          .from('user_coupons')
          .select('id, code, title, description, expires_at, created_at, type, status')
          .eq('user_id', uid)
          .eq('type', 'welcome')
          .limit(1);
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[WelcomeDialog] query user_coupons failed, fallback to coupons: $e');
      }
      try {
        rows = await client
            .from('coupons')
            .select('id, code, title, description, expires_at, created_at, type, status, user_id')
            .eq('user_id', uid)
            .eq('type', 'welcome')
        // 某些库里存在 status 字段；如果没有也能工作（忽略 eq）
            .maybeEq('status', 'active')
            .limit(1);
      } catch (e2) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[WelcomeDialog] fallback coupons query failed: $e2');
        }
        return;
      }
    }

    if (rows.isEmpty) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[WelcomeDialog] no welcome coupon row yet for $uid');
      }
      return;
    }

    if (_isShowing) return;
    _isShowing = true;

    // 稍等首页首帧完成，降低竞争（可按需调整/删除）
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!context.mounted) {
      _isShowing = false;
      return;
    }

    if (kDebugMode) {
      // ignore: avoid_print
      print('[WelcomeDialog] found welcome coupon -> showing dialog');
    }

    // 3) 真正弹出（仅在关闭后才写“已展示”）
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => WelcomeCouponDialog(
        couponData: rows.first as Map<String, dynamic>,
      ),
    );

    // 4) 关闭后记录“已展示”：两种键都写，保持向后兼容
    await prefs.setBool(keyGift, true);
    await prefs.setBool(keyDialog, true);
    _shownForUid[uid] = true;
    _isShowing = false;
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
    await prefs.remove('welcome_gift_shown_$userId');
    await prefs.remove('welcome_dialog_shown_$userId');
    if (kDebugMode) {
      // ignore: avoid_print
      print('[WelcomeDialog] cleared shown flags for user $userId');
    }
  }

  /// 调试：清除“已展示”历史标记（所有用户）
  static Future<void> clearAllShownFlags() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) =>
    k.startsWith('welcome_gift_shown_') ||
        k.startsWith('welcome_dialog_shown_')).toList();
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
