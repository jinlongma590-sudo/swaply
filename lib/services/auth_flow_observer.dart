// lib/services/auth_flow_observer.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:swaply/router/root_nav.dart';
import 'package:swaply/services/notification_service.dart';
import 'package:swaply/services/oauth_entry.dart';

class AuthFlowObserver {
  AuthFlowObserver._();
  static final AuthFlowObserver I = AuthFlowObserver._();

  StreamSubscription<AuthState>? _sub;
  bool _started = false;

  // 防重复导航锁
  bool _navigating = false;

  // 防 initialSession + signedIn 双触发
  String? _lastEvent;

  // 防抖动
  String? _lastRoute;
  DateTime? _lastAt;

  // 手动退出（快车道）
  DateTime? _manualSignOutAt;
  Timer? _signOutDebounce;

  void markManualSignOut() {
    _manualSignOutAt = DateTime.now();
  }

  bool _throttle(String route, {int ms = 900}) {
    final now = DateTime.now();
    if (_lastRoute == route &&
        _lastAt != null &&
        now.difference(_lastAt!) < Duration(milliseconds: ms)) {
      return true;
    }
    _lastRoute = route;
    _lastAt = now;
    return false;
  }

  Future<void> _goOnce(String route) async {
    if (_navigating) return;
    if (_throttle(route)) return;

    _navigating = true;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      navReplaceAll(route);
    });

    await Future.delayed(const Duration(milliseconds: 120));
    _navigating = false;
  }

  void start() {
    if (_started) return;
    _started = true;

    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      final eventName = data.event.name;
      if (_lastEvent == 'signedIn' && eventName == 'initialSession') return;
      if (_lastEvent == 'initialSession' && eventName == 'signedIn') return;
      _lastEvent = eventName;

      // 先清 OAuth 锁
      OAuthEntry.clearGuardIfSignedIn(data);

      switch (data.event) {
      // -------------------- 登录成功 --------------------
        case AuthChangeEvent.signedIn:
          _signOutDebounce?.cancel();

          final user = Supabase.instance.client.auth.currentUser;
          if (user != null) {
            try {
              await NotificationService.subscribeUser(user.id);
            } catch (_) {}
          }

          await _goOnce('/home');
          break;

      // -------------------- 冷启动 --------------------
        case AuthChangeEvent.initialSession:
          final hasSession =
              Supabase.instance.client.auth.currentSession != null;

          if (hasSession) {
            await _goOnce('/home');
          } else {
            OAuthEntry.finish();
          }
          break;

      // -------------------- 登出 --------------------
        case AuthChangeEvent.signedOut:
        case AuthChangeEvent.userDeleted:
          _signOutDebounce?.cancel();

          final now = DateTime.now();
          final fast = _manualSignOutAt != null &&
              now.difference(_manualSignOutAt!).inSeconds <= 3;

          if (fast) {
            _manualSignOutAt = null;
            await _goOnce('/login');
            break;
          }

          _signOutDebounce = Timer(const Duration(milliseconds: 150), () async {
            await _goOnce('/login');
          });
          break;

      // -------------------- 其他事件 --------------------
        default:
          break;
      }
    });
  }

  void dispose() {
    _sub?.cancel();
    _signOutDebounce?.cancel();
    _sub = null;
    _signOutDebounce = null;
    _started = false;
  }
}
