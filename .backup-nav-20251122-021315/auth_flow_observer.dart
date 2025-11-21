// lib/services/auth_flow_observer.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:swaply/router/root_nav.dart';
import 'package:swaply/services/notification_service.dart';
import 'package:swaply/services/oauth_entry.dart';

/// 全局鉴权/路由观察者：
/// - 严格单例 & 惰性启动
/// - 与 OAuthEntry 打通：在任何 onAuthStateChange 里先尝试清除 OAuth 防重入锁
/// - 统一导航：/home、/welcome、/login（带节流与并发保护）
/// - “登出快车道”：手动触发登出后 3 秒内，立刻切 /login
/// - 登出默认短抖动（120ms），避免 userUpdated/signedIn 的闪烁
class AuthFlowObserver {
  AuthFlowObserver._();
  static final AuthFlowObserver I = AuthFlowObserver._();

  StreamSubscription<AuthState>? _sub;
  bool _started = false;

  // 并发/节流保护
  bool _navigating = false;
  String? _lastRoute;
  DateTime? _lastAt;

  // 退出轻缓冲
  Timer? _signOutDebounce;

  // ✅ 手动登出“快车道”时间戳（由调用方在点击“退出登录”时标记）
  DateTime? _manualSignOutAt;

  /// 由外部在“点击退出登录”时调用，标记手动登出时间点
  void markManualSignOut() {
    _manualSignOutAt = DateTime.now();
  }

  // ---------------- helpers ----------------
  bool _throttle(String route, {int ms = 800}) {
    final now = DateTime.now();
    if (_lastRoute == route && _lastAt != null && now.difference(_lastAt!) < Duration(milliseconds: ms)) {
      if (kDebugMode) debugPrint('[AuthFlow] throttle hit -> $route');
      return true;
    }
    _lastRoute = route;
    _lastAt = now;
    return false;
  }

  Future<void> _go(String route) async {
    if (_navigating || _throttle(route)) return;
    _navigating = true;
    try {
      // 下一帧切路由，避免和 overlay/popup 竞争
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (kDebugMode) debugPrint('[AuthFlow] navigate -> $route');
        navReplaceAll(route);
      });
    } finally {
      // 给一次让步时间，避免极端条件下重复进来
      await Future<void>.delayed(const Duration(milliseconds: 20));
      _navigating = false;
    }
  }

  // ---------------- lifecycle ----------------
  void start() {
    if (_started) return;
    _started = true;

    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      if (kDebugMode) {
        debugPrint('[AuthFlow] event=${data.event} session=${data.session != null}');
      }

      // ✅ 先尝试清除 OAuth 防重入锁（signedIn / 携带有效 session 的 initialSession/userUpdated）
      OAuthEntry.clearGuardIfSignedIn(data);

      switch (data.event) {
        case AuthChangeEvent.signedIn:
        // 登录成功：取消 pending 的 signOut，订阅通知 → 去 /home
          _signOutDebounce?.cancel();
          final u = Supabase.instance.client.auth.currentUser;
          if (u != null) {
            try {
              await NotificationService.subscribeUser(u.id);
            } catch (e) {
              if (kDebugMode) debugPrint('[AuthFlow] subscribeUser error: $e');
            }
          }
          await _go('/');
          break;

        case AuthChangeEvent.initialSession:
        // ✅ 最小改动：不再强制跳到 /welcome
        //    - 有会话：依旧去 /home
        //    - 无会话：仅清一次 OAuth 残锁，让按钮可点，保持当前页（交给路由决定展示）
          final hasSession = Supabase.instance.client.auth.currentSession != null;
          if (hasSession) {
            await _go('/home');
          } else {
            try {
              OAuthEntry.finish(); // 清理可能遗留的 inFlight，避免按钮锁死
            } catch (_) {}
          }
          break;

        case AuthChangeEvent.signedOut:
        case AuthChangeEvent.userDeleted:
        // ✅ “登出快车道”：手动登出 3 秒内直接切 /login
          _signOutDebounce?.cancel();
          final now = DateTime.now();
          final isFastLane = _manualSignOutAt != null &&
              now.difference(_manualSignOutAt!).inSeconds <= 3;

          if (isFastLane) {
            _manualSignOutAt = null; // 只生效一次
            // 让出一帧再切，避免与 SnackBar/对话框竞争
            SchedulerBinding.instance.addPostFrameCallback((_) async {
              await _go('/login');
            });
            break;
          }

          // 否则：给极短抖动，避免 userUpdated/signedIn 抖动
          _signOutDebounce = Timer(const Duration(milliseconds: 120), () async {
            await _go('/login');
          });
          break;

        case AuthChangeEvent.tokenRefreshed:
        case AuthChangeEvent.userUpdated:
        default:
        // 其他事件无需路由动作
          break;
      }
    });
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _signOutDebounce?.cancel();
    _signOutDebounce = null;
    _started = false;
  }
}
