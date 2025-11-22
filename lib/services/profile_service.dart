// lib/services/profile_service.dart
// 以 profiles.verification_type 为唯一可信来源；不再用 email_verified 推断“已认证”
// ✅ 不再写 verification_type / email_verified / is_verified（连初始化也不手写，交给 DB 默认）

import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart'; // kDebugMode
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:swaply/services/coupon_service.dart'; // 发放欢迎券

class ProfileService {
  // ---- 单例：兼容 ProfileService.instance / ProfileService.i / ProfileService() ----
  ProfileService._();
  static final ProfileService instance = ProfileService._();
  static final ProfileService i = instance;
  factory ProfileService() => instance;

  SupabaseClient get _sb => Supabase.instance.client;
  String? get uid => _sb.auth.currentUser?.id;

  // ===== 轻量缓存（可选）=====
  final Map<String, Map<String, dynamic>> _cache = {};
  void invalidateCache(String userId) => _cache.remove(userId);

  // ========== 登录补丁（推荐对外使用这个而不是 syncProfileFromAuthUser） ==========
  /// 仅用于登录态建立时的“资料兜底”：
  /// - 若不存在：插入一行，并允许**仅此一次**用 auth meta 的 full_name/avatar_url 作为默认值；
  /// - 若已存在：只更新 email / updated_at，**绝不覆盖**用户可编辑字段（full_name / avatar_url / phone / bio / city）。
  Future<void> patchProfileOnLogin() async {
    final supa = Supabase.instance.client;
    final user = supa.auth.currentUser;
    if (user == null) return;

    final now = DateTime.now().toUtc().toIso8601String();

    // ⚠️ 当前 Supabase Dart 版本：select() 不带泛型
    final row = await supa
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    final Map<String, dynamic>? rowMap =
    row == null ? null : Map<String, dynamic>.from(row as Map);

    if (rowMap == null) {
      // 首登：允许默认写 full_name / avatar_url（仅此一次）
      final meta = user.userMetadata ?? {};
      final email = (user.email ?? '').trim();
      final fullNameMeta = (meta['full_name'] ?? '').toString().trim();
      final displayName =
      fullNameMeta.isNotEmpty ? fullNameMeta : (email.isNotEmpty ? email : 'User');

      await supa.from('profiles').insert({
        'id': user.id,
        'email': email.isNotEmpty ? email : null,
        'full_name': displayName,
        'avatar_url': meta['avatar_url'],
        'welcome_reward_granted': false,
        'is_official': false,
        // verification_type / email_verified / is_verified 交由 DB 默认
        'created_at': now,
        'updated_at': now,
      });

      if (kDebugMode) print('[Profile] inserted profile for ${user.id}');
    } else {
      // 已有：只更新不会破坏用户编辑的字段
      await supa
          .from('profiles')
          .update({
        'email': user.email,
        'updated_at': now,
      })
          .eq('id', user.id);

      if (kDebugMode) {
        print('[Profile] touched profile (no overwrite) for ${user.id}');
      }
    }

    // 登录后清理缓存，确保后续读取是新值
    invalidateCache(user.id);
  }

  /// （保留）历史接口：现在改为“遵循不覆盖原则”的同步
  /// - 若不存在：插入（同 patchProfileOnLogin 的“首次策略”）
  /// - 若已存在：只更新 email / updated_at
  static Future<void> syncProfileFromAuthUser() async {
    final supa = Supabase.instance.client;
    final user = supa.auth.currentUser;
    if (user == null) return;

    final now = DateTime.now().toUtc().toIso8601String();
    final meta = user.userMetadata ?? {};
    final email = (user.email ?? '').trim();
    final fullNameMeta = (meta['full_name'] ?? '').toString().trim();

    final row = await supa
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    final Map<String, dynamic>? rowMap =
    row == null ? null : Map<String, dynamic>.from(row as Map);

    if (rowMap == null) {
      final displayName =
      fullNameMeta.isNotEmpty ? fullNameMeta : (email.isNotEmpty ? email : 'User');

      await supa.from('profiles').insert({
        'id': user.id,
        'email': email.isNotEmpty ? email : null,
        'full_name': displayName,
        'avatar_url': meta['avatar_url'],
        'welcome_reward_granted': false,
        'is_official': false,
        'created_at': now,
        'updated_at': now,
      });

      if (kDebugMode) {
        print('[ProfileService] synced (insert) for ${user.id} full_name=$displayName');
      }
    } else {
      await supa
          .from('profiles')
          .update({
        'email': email.isNotEmpty ? email : null,
        'updated_at': now,
      })
          .eq('id', user.id);

      if (kDebugMode) {
        print('[ProfileService] synced (touch only) for ${user.id}');
      }
    }
  }

  // ========== 核心方法：返回是否本次新发了欢迎券 ==========
  /// 登录后跑的欢迎券流程 + 资料兜底
  /// - 仅在“新建 profile”时写默认 editable 字段；已有则只更新 email/时间
  Future<bool> ensureProfileAndWelcome({
    required String userId,
    String? email,
    String? fullName,
    String? avatarUrl,
  }) async {
    final supa = Supabase.instance.client;
    bool grantedNow = false;

    try {
      final nowIso = DateTime.now().toUtc().toIso8601String();
      if (kDebugMode) print('🔄 开始处理用户档案和欢迎券: $userId');

      // 1) 查是否已有 profile
      final existing = await supa
          .from('profiles')
          .select('id, welcome_reward_granted')
          .eq('id', userId)
          .maybeSingle();

      final isNew = existing == null;

      // 2) 遵循“不覆盖”原则的 upsert/insert 行为
      if (isNew) {
        // 仅新建时允许带入 full_name/avatar_url 作为默认值
        await supa.from('profiles').insert({
          'id': userId,
          'email': email,
          'full_name': (fullName ?? email ?? 'User'),
          'avatar_url': avatarUrl,
          'welcome_reward_granted': false,
          'is_official': false,
          // verification_type 系列由 DB 默认
          'created_at': nowIso,
          'updated_at': nowIso,
        });
        if (kDebugMode) print('✅ 新用户档案创建或初始化成功: $userId');
      } else {
        // 已存在：只更新 email / updated_at
        await supa
            .from('profiles')
            .update({
          'email': email,
          'updated_at': nowIso,
        })
            .eq('id', userId);
      }

      // 3) 读取欢迎券标记
      final prof = await supa
          .from('profiles')
          .select('welcome_reward_granted')
          .eq('id', userId)
          .maybeSingle();

      final alreadyGranted = (prof?['welcome_reward_granted'] as bool?) ?? false;

      // 4) 未发过 → 发券 + 标记
      if (!alreadyGranted) {
        // 4.1 确保邀请码
        await _ensureInvitationCode(userId);

        // 4.2 发欢迎券
        try {
          final result = await CouponService.createWelcomeCoupon(userId);
          if (result['success'] == true) {
            if (kDebugMode) print('🎁 欢迎券发放成功: ${result['code']}');
          } else {
            if (kDebugMode) print('⚠️ 欢迎券发放失败: ${result['message']}');
          }
        } catch (e) {
          if (kDebugMode) print('❌ 欢迎券发放异常: $e');
        }

        // 4.3 标记已发券（仅更新欢迎券相关字段）
        await supa
            .from('profiles')
            .update({
          'welcome_reward_granted': true,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
            .eq('id', userId);

        grantedNow = true;
        if (kDebugMode) print('🎉 新用户欢迎券发放流程完成: $userId');
      }

      // 登录后清缓存
      invalidateCache(userId);
      return grantedNow;
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        print('❌ Profile/Welcome setup Postgrest error: ${e.message} (code: ${e.code})');
      }
      return false;
    } catch (e) {
      if (kDebugMode) print('❌ Profile/Welcome setup error: $e');
      return false;
    }
  }

  // ========== 邀请码：处理唯一冲突并重试 ==========
  Future<void> _ensureInvitationCode(String userId) async {
    final rec = await _sb
        .from('invitation_codes')
        .select('code')
        .eq('user_id', userId)
        .maybeSingle();
    if (rec != null) return;

    const int maxTries = 6;
    for (int i = 0; i < maxTries; i++) {
      final code = _generateInvitationCode(); // e.g. INV8LKAWQ
      try {
        await _sb.from('invitation_codes').insert({
          'user_id': userId,
          'code': code,
          'status': 'active',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
        if (kDebugMode) print('🔮 邀请码生成成功: $code');
        return;
      } on PostgrestException catch (e) {
        if (e.code == '23505') {
          if (i == maxTries - 1 && kDebugMode) {
            print('❌ 邀请码生成多次冲突，放弃：${e.message}');
          }
          continue;
        }
        rethrow;
      }
    }
  }

  // （可选）保留但忽略未使用提示
  // ignore: unused_element
  String _generateCouponCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = math.Random.secure();
    final b = StringBuffer('WEL');
    for (int i = 0; i < 8; i++) {
      b.write(alphabet[rnd.nextInt(alphabet.length)]);
    }
    return b.toString();
  }

  // 生成"邀请码"（INV + 5位）
  String _generateInvitationCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = math.Random.secure();
    final b = StringBuffer('INV');
    for (int i = 0; i < 5; i++) {
      b.write(alphabet[rnd.nextInt(alphabet.length)]);
    }
    return b.toString();
  }

  // ========== Profiles ==========
  Future<Map<String, dynamic>?> getUserProfile() => getMyProfile();

  Future<Map<String, dynamic>?> getMyProfile() async {
    if (kDebugMode) {
      print('[ProfileService] ==================== getMyProfile START ====================');
    }

    final id = uid;

    if (kDebugMode) {
      print('[ProfileService] User ID: $id');
      print('[ProfileService] Auth session: ${_sb.auth.currentSession != null}');
      print('[ProfileService] Current user: ${_sb.auth.currentUser?.email}');
    }

    if (id == null) {
      if (kDebugMode) {
        print('[ProfileService] ❌ User ID is null! Returning null.');
        print('[ProfileService] ==================== getMyProfile END (NO USER) ====================');
      }
      return null;
    }

    // 先看本地缓存
    final cached = _cache[id];
    if (cached != null) {
      if (kDebugMode) {
        print('[ProfileService] ✅ Returning CACHED profile');
        print('[ProfileService] ==================== getMyProfile END (CACHED) ====================');
      }
      return Map<String, dynamic>.from(cached);
    }

    try {
      if (kDebugMode) print('[ProfileService] 🔍 Querying database for profile...');

      var data = await _sb
          .from('profiles')
          .select('*, verification_type')
          .eq('id', id)
          .maybeSingle();

      if (kDebugMode) {
        print('[ProfileService] Query completed');
        print('[ProfileService] Result: ${data != null ? "✅ FOUND" : "❌ NULL"}');
        if (data != null) {
          print('[ProfileService] Profile data: $data');
        }
      }

      // ✅ 如果没有记录，自动创建
      if (data == null) {
        if (kDebugMode) print('[ProfileService] ⚠️ No profile found, attempting to create default...');

        try {
          final user = _sb.auth.currentUser;
          final now = DateTime.now().toUtc().toIso8601String();

          if (kDebugMode) print('[ProfileService] Inserting new profile record...');

          await _sb.from('profiles').insert({
            'id': id,
            'full_name': 'User',
            'email': user?.email ?? '',
            'phone': user?.phone ?? '',
            'avatar_url': null,
            'welcome_reward_granted': false,
            'is_official': false,
            'created_at': now,
            'updated_at': now,
          });

          if (kDebugMode) print('[ProfileService] ✅ Default profile created, re-querying...');

          data = await _sb
              .from('profiles')
              .select('*, verification_type')
              .eq('id', id)
              .maybeSingle();

          if (kDebugMode) {
            print('[ProfileService] Re-query result: ${data != null ? "✅ FOUND" : "❌ NULL"}');
            if (data != null) {
              print('[ProfileService] New profile data: $data');
            }
          }
        } catch (createError) {
          if (kDebugMode) {
            print('[ProfileService] ❌ Failed to create profile: $createError');
          }
        }
      }

      if (data == null) {
        if (kDebugMode) {
          print('[ProfileService] ❌ Still no profile after all attempts!');
          print('[ProfileService] ==================== getMyProfile END (FAILED) ====================');
        }
        return null;
      }

      final map = Map<String, dynamic>.from(data as Map);
      _cache[id] = map;

      if (kDebugMode) {
        print('[ProfileService] ✅ Profile loaded successfully');
        print('[ProfileService] Name: ${map['full_name']}');
        print('[ProfileService] Email: ${map['email']}');
        print('[ProfileService] ==================== getMyProfile END (SUCCESS) ====================');
      }

      return Map<String, dynamic>.from(map);
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('[ProfileService] ==================== getMyProfile ERROR ====================');
        print('[ProfileService] ❌ Error: $e');
        print('[ProfileService] Stack trace: $stackTrace');
        print('[ProfileService] ==================== getMyProfile END (ERROR) ====================');
      }
      return null;
    }
  }

  Future<void> updateUserProfile({
    String? fullName,
    String? phone,
    String? avatarUrl,
  }) async {
    try {
      final current = await getMyProfile();
      final currentData = current ?? <String, dynamic>{};

      await upsertProfile(
        fullName: fullName ?? (currentData['full_name']?.toString() ?? 'User'),
        phone: phone ?? currentData['phone']?.toString(),
        avatarUrl: avatarUrl ?? currentData['avatar_url']?.toString(),
      );

      // 成功后清缓存
      final id = uid;
      if (id != null) invalidateCache(id);
    } catch (e) {
      throw Exception('Failed to update user profile: $e');
    }
  }

  /// ⚠️ 注意：这里用于“用户主动编辑”的保存，允许更新可编辑字段。
  /// 不用于登录补丁（登录补丁请走 patchProfileOnLogin / ensureProfileAndWelcome）。
  Future<void> upsertProfile({
    required String fullName,
    String? phone,
    String? avatarUrl,
    bool? isOfficial,
    String? verificationStatus, // 非关键字段（若表里不存在也不会触发验证守卫）
  }) async {
    final id = uid;
    if (id == null) throw Exception('Not logged in');

    try {
      final updateData = <String, dynamic>{
        'full_name': fullName,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      if (phone != null) updateData['phone'] = phone;
      if (avatarUrl != null) updateData['avatar_url'] = avatarUrl;
      if (isOfficial != null) updateData['is_official'] = isOfficial;
      if (verificationStatus != null) {
        updateData['verification_status'] = verificationStatus;
      }

      // 用 update 更稳妥（已存在行），避免 upsert 触发行默认值覆盖
      await _sb.from('profiles').update(updateData).eq('id', id);
    } catch (e) {
      throw Exception('Failed to upsert profile: $e');
    }
  }

  Future<String> uploadAvatar(File file) async {
    final id = uid;
    if (id == null) throw Exception('Not logged in');

    try {
      final ext = _fileExt(file.path);
      final storagePath = '$id/avatar$ext';

      await _sb.storage.from('avatars').upload(
        storagePath,
        file,
        fileOptions: const FileOptions(upsert: true),
      );

      // 成功后清缓存
      invalidateCache(id);
      return _sb.storage.from('avatars').getPublicUrl(storagePath);
    } catch (e) {
      throw Exception('Failed to upload avatar: $e');
    }
  }

  // ========== 验证相关（注意：只用于历史/兼容，已不参与“是否已认证”的判断） ==========
  Future<bool> isEmailVerified() async {
    // legacy removed：请使用 EmailVerificationService().fetchVerificationRow()
    // + vutils.computeIsVerified(...) 判定是否已认证
    return false;
  }

  Future<void> sendEmailVerification({String? email}) async {
    final user = _sb.auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    try {
      if (email != null && email != user.email) {
        await _sb.auth.updateUser(UserAttributes(email: email));
      } else if (user.email != null) {
        await _sb.auth.resend(type: OtpType.signup, email: user.email!);
      }
    } catch (e) {
      throw Exception('Failed to send email verification: $e');
    }
  }

  Future<void> refreshUserSession() async {
    try {
      // 留空：统一在上层调用 auth.refreshSession()
    } catch (e) {
      throw Exception('Failed to refresh session: $e');
    }
  }

  Future<void> setOfficialStatus({
    required String userId,
    required bool isOfficial,
  }) async {
    final currentUser = _sb.auth.currentUser;
    if (currentUser == null) throw Exception('Not authenticated');

    try {
      await _sb
          .from('profiles')
          .update({
        'is_official': isOfficial,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      })
          .eq('id', userId);
    } catch (e) {
      throw Exception('Failed to set official status: $e');
    }
  }

  /// 仅返回 profiles.verification_type；做统一规整
  /// - 若为空/null：对非常早期数据仅用 is_official 兜底为 'official'，否则 'none'
  Future<String> getUserVerificationType([String? userId]) async {
    final targetId = userId ?? uid;
    if (targetId == null) return 'none';

    try {
      final profile = await _sb
          .from('profiles')
          .select('verification_type, is_official')
          .eq('id', targetId)
          .maybeSingle();

      if (profile == null) return 'none';

      final vtRaw = profile['verification_type']?.toString();
      final vt = _normalizeVerificationType(vtRaw);

      if (vt != 'none') return vt;

      // 仅为非常早期数据提供兼容
      if (profile['is_official'] == true) return 'official';
      return 'none';
    } catch (_) {
      return 'none';
    }
  }

  /// 读取个人资料；把 verification_type 规整为 {none/verified/official/business/premium}
  /// 若字段为空则只兜底为 official/none
  Future<Map<String, dynamic>?> getUserProfileWithVerification(
      [String? userId]) async {
    final targetId = userId ?? uid;
    if (targetId == null) return null;

    try {
      final profile = await _sb
          .from('profiles')
          .select('*, verification_type, is_official')
          .eq('id', targetId)
          .maybeSingle();

      if (profile == null) return null;

      final data = Map<String, dynamic>.from(profile as Map);
      final raw = data['verification_type']?.toString();
      var normalized = _normalizeVerificationType(raw);

      if (normalized == 'none') {
        // 不再用 email_verified / is_verified 推断
        normalized = (data['is_official'] == true) ? 'official' : 'none';
      }

      data['verification_type'] = normalized;
      // 写入缓存
      _cache[targetId] = Map<String, dynamic>.from(data);
      return data;
    } catch (_) {
      return null;
    }
  }

  // ========== Favorites ==========
  Future<List<Map<String, dynamic>>> getUserFavorites() async {
    final id = uid;
    if (id == null) return [];
    try {
      final rows = await _sb
          .from('favorites')
          .select()
          .eq('user_id', id)
          .order('created_at', ascending: false);
      return rows
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> toggleFavorite({required String listingId}) async {
    final id = uid;
    if (id == null) throw Exception('Not logged in');

    try {
      final exist = await _sb
          .from('favorites')
          .select()
          .eq('user_id', id)
          .eq('listing_id', listingId)
          .maybeSingle();

      if (exist != null) {
        await _sb
            .from('favorites')
            .delete()
            .eq('user_id', id)
            .eq('listing_id', listingId);
        return false;
      } else {
        await _sb.from('favorites').insert({
          'user_id': id,
          'listing_id': listingId,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
        return true;
      }
    } catch (e) {
      throw Exception('Failed to toggle favorite: $e');
    }
  }

  // ========== Helpers ==========
  String _fileExt(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) return '.jpg';
    final ext = path.substring(dot);
    if (ext.length > 5) return '.jpg';
    return ext;
  }

  /// 把任意脏值规整为 5 档：none / verified / official / business / premium
  String _normalizeVerificationType(String? raw) {
    final t = (raw ?? '').trim().toLowerCase();
    switch (t) {
      case 'verified':
      case 'blue':
        return 'verified';
      case 'official':
      case 'government':
        return 'official';
      case 'business':
        return 'business';
      case 'premium':
      case 'gold':
        return 'premium';
      case '':
      case 'none':
      default:
        return 'none';
    }
  }
}
