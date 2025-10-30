// lib/services/profile_service.dart
// 以 profiles.verification_type 为唯一可信来源；不再用 email_verified 推断“已认证”
// ✅ 不再写 verification_type / email_verified / is_verified（连初始化也不手写，交给 DB 默认）

import 'dart:io';
import 'dart:math' as math;
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

  // ========== 核心方法：返回是否本次新发了欢迎券 ==========
  Future<bool> ensureProfileAndWelcome({
    required String userId,
    String? email,
    String? fullName,
    String? avatarUrl,
  }) async {
    final supa = Supabase.instance.client;
    bool grantedNow = false;

    try {
      final nowIso = DateTime.now().toIso8601String();
      print('🔄 开始处理用户档案和欢迎券: $userId');

      // 1) 查是否已有 profile
      final existing = await supa
          .from('profiles')
          .select('id, welcome_reward_granted')
          .eq('id', userId)
          .maybeSingle();

      final isNew = existing == null;

      // 2) upsert 同步资料（⚠️ 不写 verification_type / email_verified / is_verified）
      final upsertData = <String, dynamic>{
        'id': userId,
        'updated_at': nowIso,
      };

      if (isNew) {
        // 仅做非认证相关的初始化
        upsertData['welcome_reward_granted'] = false;
        upsertData['is_official'] = false;
        upsertData['created_at'] = nowIso;
        // verification_type / email_verified / is_verified 交给 DB 默认
      }

      if (email != null) upsertData['email'] = email;
      if (fullName != null) upsertData['full_name'] = fullName;
      if (avatarUrl != null) upsertData['avatar_url'] = avatarUrl;

      await supa.from('profiles').upsert(upsertData, onConflict: 'id');

      if (isNew) {
        print('✅ 新用户档案创建或初始化成功: $userId');
      }

      // 3) 读取欢迎券标记（使用 maybeSingle 防止抛错）
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
            print('🎁 欢迎券发放成功: ${result['code']}');
          } else {
            print('⚠️ 欢迎券发放失败: ${result['message']}');
          }
        } catch (e) {
          print('❌ 欢迎券发放异常: $e');
        }

        // 4.3 标记已发券（仅更新欢迎券相关字段）
        await supa.from('profiles').update({
          'welcome_reward_granted': true,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', userId);

        grantedNow = true;
        print('🎉 新用户欢迎券发放流程完成: $userId');
      }

      return grantedNow;
    } on PostgrestException catch (e) {
      print('❌ Profile/Welcome setup Postgrest error: ${e.message} (code: ${e.code})');
      return false;
    } catch (e) {
      print('❌ Profile/Welcome setup error: $e');
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
          'created_at': DateTime.now().toIso8601String(),
        });
        print('🔮 邀请码生成成功: $code');
        return;
      } on PostgrestException catch (e) {
        if (e.code == '23505') {
          if (i == maxTries - 1) {
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
    final id = uid;
    if (id == null) return null;

    try {
      final data = await _sb
          .from('profiles')
          .select('*, verification_type')
          .eq('id', id)
          .maybeSingle();
      return data == null ? null : Map<String, dynamic>.from(data);
    } catch (e) {
      print('Error in getMyProfile: $e');
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
    } catch (e) {
      throw Exception('Failed to update user profile: $e');
    }
  }

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
        'id': id,
        'full_name': fullName,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (phone != null) updateData['phone'] = phone;
      if (avatarUrl != null) updateData['avatar_url'] = avatarUrl;
      if (isOfficial != null) updateData['is_official'] = isOfficial;
      if (verificationStatus != null) {
        updateData['verification_status'] = verificationStatus;
      }

      await _sb.from('profiles').upsert(updateData);
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

      await _sb.storage
          .from('avatars')
          .upload(storagePath, file, fileOptions: const FileOptions(upsert: true));

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
      await _sb.from('profiles').update({
        'is_official': isOfficial,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);
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
  Future<Map<String, dynamic>?> getUserProfileWithVerification([String? userId]) async {
    final targetId = userId ?? uid;
    if (targetId == null) return null;

    try {
      final profile = await _sb
          .from('profiles')
          .select('*, verification_type, is_official')
          .eq('id', targetId)
          .maybeSingle();

      if (profile == null) return null;

      final data = Map<String, dynamic>.from(profile);
      final raw = data['verification_type']?.toString();
      var normalized = _normalizeVerificationType(raw);

      if (normalized == 'none') {
        // 不再用 email_verified / is_verified 推断
        normalized = (data['is_official'] == true) ? 'official' : 'none';
      }

      data['verification_type'] = normalized;
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
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
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
          'created_at': DateTime.now().toIso8601String(),
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
