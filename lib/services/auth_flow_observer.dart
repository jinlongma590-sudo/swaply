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
/// - 登出轻缓冲，避免“先 signOut 再 signedIn”时的闪烁
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
      if (kDebugMode) debugPrint('[AuthFlow] event=${data.event} session=${data.session != null}');

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
          await _go('/home');
          break;

        case AuthChangeEvent.initialSession:
        // 冷启动：有会话进 /home；没会话进 /welcome（或 /login）
          if (Supabase.instance.client.auth.currentSession != null) {
            await _go('/home');
          } else {
            await _go('/welcome');
          }
          break;

        case AuthChangeEvent.signedOut:
        case AuthChangeEvent.userDeleted:
        // 退出统一回登录页（加轻微缓冲，避免紧接着的 signedIn 产生闪烁）
          _signOutDebounce?.cancel();
          _signOutDebounce = Timer(const Duration(milliseconds: 800), () async {
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
