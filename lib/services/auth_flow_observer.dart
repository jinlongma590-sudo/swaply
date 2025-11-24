// lib/services/auth_flow_observer.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:swaply/router/root_nav.dart';
import 'package:swaply/services/notification_service.dart';
import 'package:swaply/services/oauth_entry.dart';
import 'package:swaply/services/profile_service.dart'; // ✅ 预热资料缓存
import 'package:swaply/services/reward_service.dart'; // ✅ 邀请码绑定
import 'package:swaply/auth/register_screen.dart'; // ✅ 读取/清理 RegisterScreen.pendingInvitationCode

/// ✅ 冷启动宽限期起点（全局单例进程级时间点）
final _appStart = DateTime.now();

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

  // 手动退出（一次性标记）
  bool _manualSignOutOnce = false;

  // 历史快车道逻辑（保留以兼容旧分支）
  DateTime? _manualSignOutAt;
  Timer? _signOutDebounce;

  // 最近一次登录的用户，用于登出时清理 Profile 缓存
  String? _lastUserId;

  void markManualSignOut() {
    // ✅ 只标记“一次”手动登出；同时保留时间戳以兼容你原来的 fast-path 逻辑
    _manualSignOutOnce = true;
    _manualSignOutAt = DateTime.now();
    debugPrint('[AuthFlowObserver] markManualSignOut=true');
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
    debugPrint('[AuthFlowObserver] NAV -> $route');

    // 放到下一帧，避免与首帧构建竞争
    SchedulerBinding.instance.addPostFrameCallback((_) {
      navReplaceAll(route);
    });

    await Future.delayed(const Duration(milliseconds: 120));
    _navigating = false;
  }

  /// ✅ 登录后立即预热：创建/触摸 profile + 预取到本地缓存，避免进入 ProfilePage 时空白一瞬
  void _preheatProfile(User user) {
    _lastUserId = user.id;
    // 不阻塞登录流：后台跑
    unawaited(ProfileService.i.patchProfileOnLogin());
    unawaited(ProfileService.i.getMyProfile()); // 会把结果写入内部缓存
  }

  void start() {
    if (_started) return;
    _started = true;

    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      // ✅ 冷启动“宽限窗口”：只忽略早期的 signedOut 假信号
      // （不再因为 session==null 而吞掉 initialSession，确保冷启动必然导航）
      final sinceStart = DateTime.now().difference(_appStart);
      if (sinceStart < const Duration(milliseconds: 1200) &&
          data.event == AuthChangeEvent.signedOut) {
        debugPrint('[AuthFlowObserver] grace-window ignore early ${data.event}');
        return;
      }

      final eventName = data.event.name;
      if (_lastEvent == 'signedIn' && eventName == 'initialSession') return;
      if (_lastEvent == 'initialSession' && eventName == 'signedIn') return;
      _lastEvent = eventName;

      // 先清 OAuth 锁
      OAuthEntry.clearGuardIfSignedIn(data);

      switch (data.event) {
      // -------------------- 登录成功 --------------------
        case AuthChangeEvent.signedIn:
        // ✅ 一旦有会话（登录），清掉“一次性手动登出标记”
          _manualSignOutOnce = false;

          _signOutDebounce?.cancel();

          final user = Supabase.instance.client.auth.currentUser;
          if (user != null) {
            try {
              // 订阅通知
              await NotificationService.subscribeUser(user.id);
            } catch (_) {}

            // ✅ 预热 Profile（创建/触摸 + 缓存）
            _preheatProfile(user);

            // ✅ 邀请码绑定（如果注册页留存了待绑定的 code）
            try {
              final code = RegisterScreen.pendingInvitationCode;
              if (code != null && code.isNotEmpty) {
                await RewardService.submitInviteCode(code.trim().toUpperCase());
                RegisterScreen.clearPendingCode();
              }
            } catch (_) {}

            // ✅ 同步 Profile（统一搬到这里）
            try {
              await ProfileService.syncProfileFromAuthUser();
            } catch (_) {}
          }

          await _goOnce('/home');
          break;

      // -------------------- 冷启动 --------------------
        case AuthChangeEvent.initialSession:
        // ✅ 冷启动时清一次标记（以防上次手动登出残留）
          _manualSignOutOnce = false;

          // ⬇⬇⬇ 修复根因：先按会话判断导航，再 break；不再提前 break ⬇⬇⬇
          try {
            final session = Supabase.instance.client.auth.currentSession;
            final user = Supabase.instance.client.auth.currentUser;

            if (session != null && user != null) {
              // ✅ 有会话 → 预热 Profile 再进首页
              try {
                _preheatProfile(user);
              } catch (_) {}
              await _goOnce('/home');
            } else {
              // ✅ 无会话 → 去欢迎/登录（如需直达登录，把 '/welcome' 改成 '/login'）
              await _goOnce('/welcome');
            }
          } catch (e, st) {
            debugPrint('[AuthFlowObserver] initialSession error: $e\n$st');
            await _goOnce('/welcome');
          }
          break;

      // -------------------- 资料更新 --------------------
        case AuthChangeEvent.userUpdated:
        // ✅ 任何 userUpdated 也清一次标记（确保重新登录后不被误判）
          _manualSignOutOnce = false;
          // 其余保持原样（不做导航）
          break;

      // -------------------- 登出 --------------------
        case AuthChangeEvent.signedOut:
        case AuthChangeEvent.userDeleted:
          _signOutDebounce?.cancel();

          // ✅ 清理上一次用户的 Profile 缓存，避免下一位读到旧值
          if (_lastUserId != null) {
            ProfileService.i.invalidateCache(_lastUserId!);
            _lastUserId = null;
          }

          // ✅ 如果是“手动登出触发”的这一次，吞掉导航（ProfilePage等处已自行 navReplaceAll('/login')）
          if (_manualSignOutOnce) {
            debugPrint(
                '[AuthFlowObserver] signedOut fast-path (manual). swallow nav once.');
            _manualSignOutOnce = false; // 只生效一次
            break;
          }

          // —— 以下是你原有的“非手动”登出逻辑（保留） ——
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
