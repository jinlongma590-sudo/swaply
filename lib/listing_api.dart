// lib/listing_api.dart —— 兼容你项目 & 旧版 supabase_dart
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

class ListingApi {
  static final SupabaseClient _sb = Supabase.instance.client;

  /// 和 Dashboard 完全一致的桶名（区分大小写）
  static const String kListingBucket = 'listings';

  /* ========================= 工具 ========================= */

  static String _extOf(String p) {
    final i = p.lastIndexOf('.');
    if (i <= 0 || i == p.length - 1) return '';
    return p.substring(i).toLowerCase();
  }

  static Future<void> debugPrintBuckets() async {
    final bs = await _sb.storage.listBuckets();
    // ignore: avoid_print
    print('Buckets from client: ${bs.map((b) => b.name).toList()}');
  }

  /* ========================= 图片上传 ========================= */

  /// 批量上传图片，返回（public）URL 列表。
  /// 若你的桶不是 public，把 getPublicUrl 换成 createSignedUrl。
  static Future<List<String>> uploadListingImages({
    required List<File> files,
    required String userId,
    void Function(int done, int total)? onProgress,
  }) async {
    final urls = <String>[];

    for (int i = 0; i < files.length; i++) {
      final f = files[i];

      var ext = _extOf(f.path);
      if (ext.isEmpty) ext = '.jpg';

      final objectName = '${DateTime.now().millisecondsSinceEpoch}_$i$ext';
      final objectPath = '$userId/$objectName';

      try {
        await _sb.storage
            .from(kListingBucket)
            .upload(objectPath, f, fileOptions: const FileOptions(upsert: false));

        // public 桶：
        final url = _sb.storage.from(kListingBucket).getPublicUrl(objectPath);

        // 私有桶可改为：
        // final url = await _sb.storage
        //     .from(kListingBucket)
        //     .createSignedUrl(objectPath, 60 * 60 * 24 * 365);

        urls.add(url);
        onProgress?.call(i + 1, files.length);
      } on StorageException catch (e) {
        throw Exception(
          'Upload failed: ${e.message} '
              '(status=${e.statusCode}, bucket=$kListingBucket, path=$objectPath)',
        );
      }
    }

    return urls;
  }

  /* ========================= 新增 / 更新 / 删除 ========================= */

  /// 新增一条 listing（**兼容旧调用**：支持 sellerName / contactPhone / price 为 num?）
  static Future<Map<String, dynamic>> insertListing({
    required String userId,
    required String title,
    num? price, // 兼容你页面传入的 num?
    String? description,
    String? region,
    String? city,
    String? category,
    List<String>? imageUrls,
    String status = 'active',
    Map<String, dynamic>? attributes,
    // 兼容旧参数名（你页面在用）
    String? sellerName,
    String? contactPhone,
    // 新参数名（若你后续统一，也可以直接用 phone）
    String? phone,
  }) async {
    // 兼容：phone 以 contactPhone 为准，未传则用 phone
    final finalPhone = contactPhone ?? phone;

    final payload = <String, dynamic>{
      'user_id': userId,
      'title': title,
      'price': price ?? 0, // 避免可空类型导致插入失败
      'description': description,
      'region': region,
      'city': city,
      'category': category,
      'images': imageUrls,    // jsonb / text[] 均可
      'status': status,
      'attributes': attributes,
      'seller_name': sellerName, // 若表里没有该列可以删掉
      'phone': finalPhone,       // 若你的列名不同，改成对应字段
    }..removeWhere((k, v) => v == null);

    final data = await _sb.from('listings').insert(payload).select().single();
    return Map<String, dynamic>.from(data);
  }

  static Future<Map<String, dynamic>> updateListing({
    required int id,
    Map<String, dynamic>? fields,
  }) async {
    final dataToUpdate = Map<String, dynamic>.from(fields ?? {})
      ..removeWhere((k, v) => v == null);

    final data = await _sb
        .from('listings')
        .update(dataToUpdate)
        .eq('id', id)
        .select()
        .single();

    return Map<String, dynamic>.from(data);
  }

  static Future<void> deleteListing({
    required int id,
    List<String>? storageObjectPaths,
  }) async {
    await _sb.from('listings').delete().eq('id', id);

    if (storageObjectPaths != null && storageObjectPaths.isNotEmpty) {
      try {
        await _sb.storage.from(kListingBucket).remove(storageObjectPaths);
      } catch (_) {
        // 忽略存储删除失败
      }
    }
  }

  /* ========================= 查询 / 搜索 / 计数 ========================= */

  /// 列表查询（分页/筛选/排序）
  static Future<List<Map<String, dynamic>>> fetchListings({
    int limit = 20,
    int offset = 0,
    String? region,
    String? city,
    String? category,
    String? status = 'active',
    String orderBy = 'created_at',
    bool ascending = false,
    String? userId,
  }) async {
    dynamic query = _sb.from('listings').select('*');

    if (status != null) query = query.eq('status', status);
    if (region != null && region.isNotEmpty) query = query.eq('region', region);
    if (city != null && city.isNotEmpty) query = query.eq('city', city);
    if (category != null && category.isNotEmpty) {
      query = query.eq('category', category);
    }
    if (userId != null && userId.isNotEmpty) {
      query = query.eq('user_id', userId);
    }

    query = query.order(orderBy, ascending: ascending).range(
      offset,
      offset + limit - 1,
    );

    final resp = await query as List;
    return resp
        .map<Map<String, dynamic>>(
            (e) => Map<String, dynamic>.from(e as Map<String, dynamic>))
        .toList();
  }

  /// 关键词搜索（简单 ilike）
  static Future<List<Map<String, dynamic>>> searchListings({
    required String keyword,
    int limit = 20,
    int offset = 0,
    String? region,
    String? city,
    String? category,
    String? status = 'active',
    String orderBy = 'created_at',
    bool ascending = false,
  }) async {
    dynamic query = _sb.from('listings').select('*');

    if (status != null) query = query.eq('status', status);
    if (region != null && region.isNotEmpty) query = query.eq('region', region);
    if (city != null && city.isNotEmpty) query = query.eq('city', city);
    if (category != null && category.isNotEmpty) {
      query = query.eq('category', category);
    }

    query = query.or('title.ilike.%$keyword%,description.ilike.%$keyword%');
    query = query.order(orderBy, ascending: ascending).range(
      offset,
      offset + limit - 1,
    );

    final resp = await query as List;
    return resp
        .map<Map<String, dynamic>>(
            (e) => Map<String, dynamic>.from(e as Map<String, dynamic>))
        .toList();
  }

  /// 计数（兼容最旧版 SDK：不再使用 select(count: ...)）
  static Future<int> countListings({
    String? region,
    String? city,
    String? category,
    String? status = 'active',
    String? userId,
  }) async {
    dynamic query = _sb.from('listings').select('id');

    if (status != null) query = query.eq('status', status);
    if (region != null && region.isNotEmpty) query = query.eq('region', region);
    if (city != null && city.isNotEmpty) query = query.eq('city', city);
    if (category != null && category.isNotEmpty) {
      query = query.eq('category', category);
    }
    if (userId != null && userId.isNotEmpty) {
      query = query.eq('user_id', userId);
    }

    final resp = await query;
    if (resp is List) return resp.length;
    if (resp is Map && resp['data'] is List) return (resp['data'] as List).length;
    return 0;
  }

  /* ========================= 维表/下拉 ========================= */

  static Future<List<String>> getRegions({String status = 'active'}) async {
    final resp =
    await _sb.from('listings').select('region').eq('status', status);
    final set = <String>{};
    for (final row in (resp as List? ?? const [])) {
      final v = (row as Map)['region'];
      if (v != null && v.toString().isNotEmpty) set.add(v.toString());
    }
    final list = set.toList()..sort();
    return list;
  }

  static Future<List<String>> getCities({String status = 'active'}) async {
    final resp =
    await _sb.from('listings').select('city').eq('status', status);
    final set = <String>{};
    for (final row in (resp as List? ?? const [])) {
      final v = (row as Map)['city'];
      if (v != null && v.toString().isNotEmpty) set.add(v.toString());
    }
    final list = set.toList()..sort();
    return list;
  }
}
