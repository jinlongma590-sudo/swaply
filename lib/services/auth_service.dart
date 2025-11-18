// lib/services/auth_service.dart
// 鐧诲綍/娉ㄥ唽/OAuth 缁熶竴锛氬洖璋?URI銆佹渶灏忔潈闄愩€侀伩鍏嶄簩娆＄‘璁わ紱profile 鍒涘缓涓庢杩庡脊绐楀鎵?ProfileService
// 2.1 鍓嶇涓嶅啀鐩存帴鍐?profiles 鐨勨€滈獙璇佺浉鍏斥€濆瓧娈碉紙email_verified / is_verified / verification_type 鐢?DB 璐熻矗锛?
// 2.2 onEmailCodeVerified 浠呭埛鏂版湰鍦颁細璇濓紝涓嶅啓 DB
// 2.3 UI/妯″瀷浠?auth 涓哄噯锛宲rofiles 浠呭仛鍩虹淇℃伅锛堣 verification_utils.dart锛?

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint, kDebugMode;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:swaply/services/profile_service.dart'; // 缁熶竴鍒涘缓 profile / 娆㈣繋寮圭獥
import 'package:swaply/config/auth_config.dart';

// 缁熶竴绉诲姩绔洖璋冿紙宸插湪 iOS Info.plist / Android Manifest 閰嶅ソ锛?
const String _kMobileRedirect = 'cc.swaply.app://login-callback';

class AuthService {
  SupabaseClient get supabase => Supabase.instance.client;

  User? get currentUser => supabase.auth.currentUser;
  bool get isSignedIn => currentUser != null;

  // legacy: 閭楠岃瘉鐘舵€佷氦鐢?DB 涓庢湇鍔＄鍒ゅ畾锛岃繖閲屼笉鍐嶇淮鎶ゆ湰鍦板竷灏?
  bool get isEmailVerified => false;

  // ====== 浼氳瘽鎵嬪姩鍒锋柊锛堜繚鎸佹帴鍙ｏ紝浣嗛粯璁や笉鐢紝浜ょ敱 Supabase 鑷姩鍒锋柊锛?======
  DateTime? _lastRefresh;

  Future<void> refreshSession({Duration minInterval = const Duration(seconds: 30)}) async {
    debugPrint('[AuthService] refreshSession() disabled. Using Supabase auto-refresh.');
    return;
  }
  // ============================================================================

  Future<bool> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      await supabase.auth.signInWithPassword(email: email, password: password);
      final user = supabase.auth.currentUser;
      if (user == null) throw const AuthException('Login failed');

      // 鍒ゆ柇鏄惁鏂扮敤鎴凤紙浠?profiles 鏄惁瀛樺湪涓哄噯锛?
      final existing = await supabase
          .from('profiles')
          .select('id')
          .eq('id', user.id)
          .maybeSingle();
      final isNew = existing == null;

      // 缁熶竴浜ょ粰 ProfileService锛氫繚璇?profile 瀛樺湪 + 娆㈣繋寮圭獥
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
        emailRedirectTo: kAuthRedirectUri, // 缁熶竴鍥炶皟
      );

      final user = supabase.auth.currentUser;
      if (user == null) throw const AuthException('Registration failed');

      // 鏂版敞鍐岀敤鎴凤細鍒濆鍖?profile + 娆㈣繋寮圭獥锛堥獙璇佸瓧娈典粛浜ょ敱 DB锛?
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

  // --- 鐩存帴浣跨敤 Supabase OAuth锛坕OS/Android/Web 缁熶竴鍥炶皟锛?---

  Future<bool> signInWithGoogle() async {
    try {
      await supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? 'https://swaply.cc/auth/callback' : _kMobileRedirect,
        authScreenLaunchMode: LaunchMode.externalApplication,
        // 鏄惧紡鎻愮ず璐﹀彿閫夋嫨锛岄伩鍏嶉潤榛橀€変腑瀵艰嚧閲嶅寰€杩?
        queryParams: const {'prompt': 'select_account'},
      );

      final user = supabase.auth.currentUser;
      if (user == null) return false;

      final existing = await supabase
          .from('profiles')
          .select('id')
          .eq('id', user.id)
          .maybeSingle();
      final isNew = existing == null;

      await ProfileService.instance.ensureProfileAndWelcome(
        userId: user.id,
        email: user.email,
        fullName: user.userMetadata?['full_name'] ?? user.userMetadata?['name'],
        avatarUrl: user.userMetadata?['avatar_url'] ?? user.userMetadata?['picture'],
      );

      return isNew;
    } catch (e) {
      throw Exception('Google login failed: $e');
    }
  }

  Future<bool> signInWithFacebook() async {
    try {
      await supabase.auth.signInWithOAuth(
        OAuthProvider.facebook,
        redirectTo: kIsWeb ? 'https://swaply.cc/auth/callback' : _kMobileRedirect,
        authScreenLaunchMode: LaunchMode.externalApplication,
        // 绮剧畝鍒版渶甯哥敤鏉冮檺锛屾惌閰?display=popup锛屽噺灏戔€滀袱娆＄‘璁も€?
        scopes: 'public_profile,email',
        queryParams: const {'display': 'popup'},
      );

      final user = supabase.auth.currentUser;
      if (user == null) return false;

      final existing = await supabase
          .from('profiles')
          .select('id')
          .eq('id', user.id)
          .maybeSingle();
      final isNew = existing == null;

      await ProfileService.instance.ensureProfileAndWelcome(
        userId: user.id,
        email: user.email,
        fullName: user.userMetadata?['name'] ?? user.userMetadata?['full_name'],
        avatarUrl: user.userMetadata?['avatar_url'] ?? user.userMetadata?['picture'],
      );

      return isNew;
    } on AuthException catch (e) {
      throw Exception('Facebook login failed: ${e.message}');
    } catch (e) {
      throw Exception('Facebook login failed: $e');
    }
  }

  // 鈥斺€?鍙鐢ㄧ殑 profile 鍐欏叆宸ュ叿锛堜笉鍐欓獙璇佺浉鍏冲瓧娈碉級 鈥斺€?//
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
        // 鈿狅笍 涓嶅啓 email_verified / is_verified / verification_type
      };

      if (email?.isNotEmpty == true) {
        data['email'] = email!.trim().toLowerCase();
      }
      if (fullName?.isNotEmpty == true) data['full_name'] = fullName;
      if (phone?.isNotEmpty == true) data['phone'] = phone;
      if (avatarUrl?.isNotEmpty == true) data['avatar_url'] = avatarUrl;

      await supabase.from('profiles').upsert(data, onConflict: 'id');

      if (kDebugMode) {
        print('[AuthService] New user profile created (verification fields by DB defaults)');
      }
    } catch (e) {
      if (kDebugMode) print('Failed to upsert user profile: $e');
    }
  }

  Future<void> _createOrUpdateUserProfile({
    required String userId,
    String? email,
    String? fullName,
    String? phone,
    String? avatarUrl,
  }) async {
    try {
      // 浠呮鏌ユ槸鍚﹀瓨鍦?
      await supabase.from('profiles').select('id').eq('id', userId).maybeSingle();

      final data = <String, dynamic>{
        'id': userId,
        'updated_at': DateTime.now().toIso8601String(),
        // 鈿狅笍 涓嶅啓楠岃瘉瀛楁
      };

      if (email?.isNotEmpty == true) {
        data['email'] = email!.trim().toLowerCase();
      }
      if (fullName?.isNotEmpty == true) data['full_name'] = fullName;
      if (phone?.isNotEmpty == true) data['phone'] = phone;
      if (avatarUrl?.isNotEmpty == true) data['avatar_url'] = avatarUrl;

      await supabase.from('profiles').upsert(data, onConflict: 'id');
    } catch (e) {
      if (kDebugMode) print('Failed to upsert user profile: $e');
    }
  }

  // 灞€閮ㄦ洿鏂帮紙涓嶈Е纰伴獙璇佸瓧娈碉級
  Future<void> _upsertProfilePartial(Map<String, dynamic> patch) async {
    final u = currentUser;
    if (u == null) return;
    await supabase.from('profiles').upsert({
      'id': u.id,
      'updated_at': DateTime.now().toIso8601String(),
      ...patch,
    }, onConflict: 'id');
  }

  /// 楠岃瘉鐮侀獙璇佸悗鐨勫洖璋冿細浠呭埛鏂颁細璇濓紝鎷夊彇鏈€鏂?app_metadata锛屼笉鍐?DB
  Future<void> onEmailCodeVerified() async {
    try {
      await Supabase.instance.client.auth.refreshSession();
    } catch (_) {}
  }

  /// 鍚屾鏈湴 session锛圢O-OP锛氫笉鍐?profiles 鐨?email_verified锛?
  Future<void> syncEmailVerificationStatus() async {
    try {
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

  // 缁熶竴鍥炶皟 URI 鍙戦€侀噸缃偖浠?
  Future<void> resetPassword(String email) async {
    try {
      await supabase.auth.resetPasswordForEmail(
        email.trim().toLowerCase(),
        redirectTo: kIsWeb ? 'https://swaply.cc/auth/callback' : _kMobileRedirect,
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
          emailRedirectTo: kAuthRedirectUri, // 缁熶竴鍥炶皟
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

        // 涓嶄慨鏀归獙璇佺姸鎬?
        await supabase.from('profiles').upsert(patch, onConflict: 'id');
      }
    } on AuthException catch (e) {
      throw Exception('User update failed: ${e.message}');
    } catch (e) {
      throw Exception('User update failed: $e');
    }
  }

  // ====== 闃查噸澶嶇櫥鍑?======
  static bool _signingOut = false;

  Future<void> signOut() async {
    if (_signingOut) return;
    _signingOut = true;
    try {
      await supabase.auth.signOut(scope: SignOutScope.global);
    } catch (e) {
      throw Exception('Sign out failed: $e');
    } finally {
      _signingOut = false;
    }
  }
  // ======================

  Future<void> deleteAccount() async {
    try {
      final user = currentUser;
      if (user == null) throw Exception('No user signed in');

      await Future.wait<void>([
        supabase.from('profiles').delete().eq('id', user.id).then((_) {}),
        supabase.from('coupons').delete().eq('user_id', user.id).then((_) {}),
        supabase.from('user_tasks').delete().eq('user_id', user.id).then((_) {}),
        supabase.from('reward_logs').delete().eq('user_id', user.id).then((_) {}),
        supabase.from('user_invitations').delete().eq('inviter_id', user.id).then((_) {}),
        supabase.from('pinned_ads').delete().eq('user_id', user.id).then((_) {}),
      ]);

      await signOut();
    } catch (e) {
      throw Exception('Account deletion failed: $e');
    }
  }

  // 澶栭儴浣跨敤 Supabase 鐨勫師鐢熶簨浠舵祦锛堟澶勪笉鑷缓鐩戝惉锛?
  Stream<AuthState> get authStateChanges => supabase.auth.onAuthStateChange;
}

