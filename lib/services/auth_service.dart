// lib/services/auth_service.dart
// 登录/注册/OAuth 后自动 upsert profile；不再自动同步邮箱验证状态与徽章
// 2.2：onEmailCodeVerified 仅刷新会话，不写 DB
// 2.1：前端任何地方都不更新 profiles 的认证字段（email_verified / is_verified / verification_type）
// 2.3：UI/模型需按 auth 优先、profiles 兜底判定（见 verification_utils.dart）

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:swaply/services/profile_service.dart'; // 统一创建profile/欢迎券入口

// --- 新增 Import ---
import 'package:swaply/config/auth_config.dart';
import 'package:swaply/services/oauth_service.dart';
// -----------------

class AuthService {
  SupabaseClient get supabase => Supabase.instance.client;

  User? get currentUser => supabase.auth.currentUser;
  bool get isSignedIn => currentUser != null;

  bool get isEmailVerified => false; // legacy removed。需要认证请查 user_verifications

  // ====== 刷新会话的节流与重入保护（保留占位，当前不启用） ======
  DateTime? _lastRefresh;

  /// 安全刷新：默认 30s 内至多刷新一次（当前禁用，沿用 Supabase 自动刷新）
  Future<void> refreshSession(
      {Duration minInterval = const Duration(seconds: 30)}) async {
    debugPrint(
        '[AuthService] refreshSession() disabled. Using Supabase auto-refresh.');
    return;
  }
  // =======================================================

  Future<bool> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      await supabase.auth.signInWithPassword(email: email, password: password);
      final user = supabase.auth.currentUser;
      if (user == null) throw const AuthException('Login failed');

      // 判断是否新用户（基于 profiles 表是否存在）
      final existing = await supabase
          .from('profiles')
          .select('id')
          .eq('id', user.id)
          .maybeSingle();
      final isNew = existing == null;

      // 统一交给 ProfileService：确保有 profile（verification_type 默认由 DB 处理）、发欢迎券
      await ProfileService.instance.ensureProfileAndWelcome(
        userId: user.id,
        email: email.trim().toLowerCase(),
        fullName: user.userMetadata?['full_name'],
        avatarUrl: user.userMetadata?['avatar_url'],
      );

      return isNew;
    } on AuthException catch (e) {
      throw Exception('Login failed: ${e.message}');
    } catch (e) {
      throw Exception('Login failed: $e');
    }
  }

  Future<bool> signUpWithEmailPassword({
    required String email,
    required String password,
    String? fullName,
    String? phone,
  }) async {
    try {
      final meta = <String, dynamic>{};
      if (fullName?.isNotEmpty == true) meta['full_name'] = fullName;
      if (phone?.isNotEmpty == true) meta['phone'] = phone;

      await supabase.auth.signUp(
        email: email.trim().toLowerCase(),
        password: password,
        data: meta.isEmpty ? null : meta,
        emailRedirectTo: kAuthRedirectUri, // <- 统一回调
      );

      final user = supabase.auth.currentUser;
      if (user == null) throw const AuthException('Registration failed');

      // 新注册用户：profile 初始化 + 欢迎券（认证状态字段交给 DB 默认）
      await ProfileService.instance.ensureProfileAndWelcome(
        userId: user.id,
        email: email.trim().toLowerCase(),
        fullName: fullName,
        avatarUrl: user.userMetadata?['avatar_url'],
      );

      return true;
    } on AuthException catch (e) {
      throw Exception('Registration failed: ${e.message}');
    } catch (e) {
      throw Exception('Registration failed: $e');
    }
  }

  // --- 修改：使用 OAuthService ---
  Future<bool> signInWithGoogle() async {
    try {
      // await supabase.auth
      //     .signInWithOAuth(OAuthProvider.google, redirectTo: redirectTo);
      await OAuthService.signInWithGoogle(); // <- 替换

      final user = supabase.auth.currentUser;
      if (user == null) return false;

      final existing = await supabase
          .from('profiles')
          .select('id')
          .eq('id', user.id)
          .maybeSingle();
      final isNew = existing == null;

      // Google 登录后确保 profile + 欢迎券
      await ProfileService.instance.ensureProfileAndWelcome(
        userId: user.id,
        email: user.email,
        fullName: user.userMetadata?['full_name'] ?? user.userMetadata?['name'],
        avatarUrl:
        user.userMetadata?['avatar_url'] ?? user.userMetadata?['picture'],
      );

      return isNew;
    } catch (e) {
      throw Exception('Google login failed: $e');
    }
  }

  // --- 修改：使用 OAuthService ---
  Future<bool> signInWithFacebook() async {
    try {
      // await supabase.auth
      //     .signInWithOAuth(OAuthProvider.facebook, redirectTo: redirectTo);
      await OAuthService.signInWithFacebook(); // <- 替换

      final user = supabase.auth.currentUser;
      if (user == null) return false;

      final existing = await supabase
          .from('profiles')
          .select('id')
          .eq('id', user.id)
          .maybeSingle();
      final isNew = existing == null;

      // Facebook 登录后确保 profile + 欢迎券
      await ProfileService.instance.ensureProfileAndWelcome(
        userId: user.id,
        email: user.email,
        fullName: user.userMetadata?['name'] ?? user.userMetadata?['full_name'],
        avatarUrl:
        user.userMetadata?['avatar_url'] ?? user.userMetadata?['picture'],
      );

      return isNew;
    } on AuthException catch (e) {
      throw Exception('Facebook login failed: ${e.message}');
    } catch (e) {
      throw Exception('Facebook login failed: $e');
    }
  }

  // ✅ 新用户专用：创建/更新基本资料（不写任何认证字段）
  Future<void> _createOrUpdateUserProfileForNewUser({
    required String userId,
    String? email,
    String? fullName,
    String? phone,
    String? avatarUrl,
  }) async {
    try {
      final data = <String, dynamic>{
        'id': userId,
        'updated_at': DateTime.now().toIso8601String(),
        // ⚠️ 不写 email_verified / is_verified / verification_type（交给 DB 默认）
      };

      if (email?.isNotEmpty == true)
        data['email'] = email!.trim().toLowerCase();
      if (fullName?.isNotEmpty == true) data['full_name'] = fullName;
      if (phone?.isNotEmpty == true) data['phone'] = phone;
      if (avatarUrl?.isNotEmpty == true) data['avatar_url'] = avatarUrl;

      await supabase.from('profiles').upsert(data, onConflict: 'id');

      if (kDebugMode) {
        print(
            '[AuthService] New user profile created (verification fields by DB defaults)');
      }
    } catch (e) {
      if (kDebugMode) print('Failed to upsert user profile: $e');
    }
  }

  // ✅ 现有用户更新：不改变验证状态（也不写认证字段）
  Future<void> _createOrUpdateUserProfile({
    required String userId,
    String? email,
    String? fullName,
    String? phone,
    String? avatarUrl,
  }) async {
    try {
      // 只检查是否存在
      await supabase
          .from('profiles')
          .select('id')
          .eq('id', userId)
          .maybeSingle();

      final data = <String, dynamic>{
        'id': userId,
        'updated_at': DateTime.now().toIso8601String(),
        // ⚠️ 不写认证字段
      };

      if (email?.isNotEmpty == true)
        data['email'] = email!.trim().toLowerCase();
      if (fullName?.isNotEmpty == true) data['full_name'] = fullName;
      if (phone?.isNotEmpty == true) data['phone'] = phone;
      if (avatarUrl?.isNotEmpty == true) data['avatar_url'] = avatarUrl;

      await supabase.from('profiles').upsert(data, onConflict: 'id');
    } catch (e) {
      if (kDebugMode) print('Failed to upsert user profile: $e');
    }
  }

  // 通用的 profile 部分更新（仅在不涉及认证字段时使用）
  Future<void> _upsertProfilePartial(Map<String, dynamic> patch) async {
    final u = currentUser;
    if (u == null) return;
    await supabase.from('profiles').upsert({
      'id': u.id,
      'updated_at': DateTime.now().toIso8601String(),
      ...patch,
    }, onConflict: 'id');
  }

  /// 2.2：验证码通过后的回调：只刷新会话（拿到最新 app_metadata），不写 DB / 不改 auth metadata
  Future<void> onEmailCodeVerified() async {
    try {
      await Supabase.instance.client.auth.refreshSession();
    } catch (_) {}
  }

  /// （已改为 NO-OP，不再写 profiles 的 email_verified）
  Future<void> syncEmailVerificationStatus() async {
    try {
      // 仅确保本地 user 最新；不再落库
      await supabase.auth.refreshSession();
      await supabase.auth.getUser();
      if (kDebugMode) {
        debugPrint('[AuthService] session refreshed');
      }
    } catch (e) {
      if (kDebugMode) print('syncEmailVerificationStatus failed: $e');
    }
  }

  Future<void> signInAnonymously() async {
    try {
      await supabase.auth.signInAnonymously();
      if (supabase.auth.currentUser == null) {
        throw Exception('Anonymous login failed');
      }
    } on AuthException catch (e) {
      throw Exception('Anonymous login failed: ${e.message}');
    }
  }

  // --- 修改：使用 kAuthRedirectUri ---
  Future<void> resetPassword(String email) async {
    try {
      await supabase.auth.resetPasswordForEmail(
        email.trim().toLowerCase(),
        redirectTo: kAuthRedirectUri, // <- 统一回调
      );
    } on AuthException catch (e) {
      throw Exception('Password reset failed: ${e.message}');
    }
  }

  Future<void> updatePassword(String newPassword) async {
    try {
      await supabase.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (e) {
      throw Exception('Password update failed: ${e.message}');
    }
  }

  Future<void> updateUserData({
    String? email,
    String? fullName,
    String? phone,
    String? avatarUrl,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final meta = <String, dynamic>{};
      if (fullName != null) meta['full_name'] = fullName;
      if (phone != null) meta['phone'] = phone;
      if (metadata != null) meta.addAll(metadata);

      if (meta.isNotEmpty || email != null) {
        await supabase.auth.updateUser(
          UserAttributes(
            email: email?.trim().toLowerCase(),
            data: meta.isEmpty ? null : meta,
          ),
          emailRedirectTo: kAuthRedirectUri, // <- 统一回调
        );
      }

      final user = currentUser;
      if (user != null) {
        final patch = <String, dynamic>{
          'id': user.id,
          'updated_at': DateTime.now().toIso8601String(),
        };
        if (email != null) patch['email'] = email.trim().toLowerCase();
        if (fullName != null) patch['full_name'] = fullName;
        if (phone != null) patch['phone'] = phone;
        if (avatarUrl != null) patch['avatar_url'] = avatarUrl;

        // ✅ 不改变验证状态，也不触碰 verification 字段
        await supabase.from('profiles').upsert(patch, onConflict: 'id');
      }
    } on AuthException catch (e) {
      throw Exception('User update failed: ${e.message}');
    } catch (e) {
      throw Exception('User update failed: $e');
    }
  }

  // ====== 防重复登出的节流机制 ======
  static bool _signingOut = false;

  Future<void> signOut() async {
    if (_signingOut) return;
    _signingOut = true;
    try {
      await supabase.auth.signOut();
    } catch (e) {
      throw Exception('Sign out failed: $e');
    } finally {
      _signingOut = false;
    }
  }
  // =================================

  Future<void> deleteAccount() async {
    try {
      final user = currentUser;
      if (user == null) throw Exception('No user signed in');

      await Future.wait<void>([
        supabase.from('profiles').delete().eq('id', user.id).then((_) {}),
        supabase.from('coupons').delete().eq('user_id', user.id).then((_) {}),
        supabase
            .from('user_tasks')
            .delete()
            .eq('user_id', user.id)
            .then((_) {}),
        supabase
            .from('reward_logs')
            .delete()
            .eq('user_id', user.id)
            .then((_) {}),
        supabase
            .from('user_invitations')
            .delete()
            .eq('inviter_id', user.id)
            .then((_) {}),
        supabase
            .from('pinned_ads')
            .delete()
            .eq('user_id', user.id)
            .then((_) {}),
      ]);

      await signOut();
    } catch (e) {
      throw Exception('Account deletion failed: $e');
    }
  }

  // 对外暴露 Supabase 的原始事件流（不在本文件内自建监听）
  Stream<AuthState> get authStateChanges => supabase.auth.onAuthStateChange;
}