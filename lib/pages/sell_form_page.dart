// lib/pages/sell_form_page.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// 选图依赖（只用 bytes，不走路径上传）
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'package:swaply/pages/product_detail_page.dart' as pd;
import 'package:swaply/config.dart';
import 'package:swaply/models/listing_store.dart';
import 'package:swaply/listing_api.dart';
import 'package:swaply/services/reward_service.dart';
import 'package:swaply/services/coupon_service.dart';
import 'package:swaply/models/coupon.dart';
// ✅ 关键操作守卫（未验证则引导验证）
import 'package:swaply/services/verification_guard.dart';

class SellFormPage extends StatefulWidget {
  const SellFormPage({super.key});

  @override
  State<SellFormPage> createState() => _SellFormPageState();
}

/* =========================
 * 相册选图：返回内存字节而不是路径
 * ========================= */
Future<({Uint8List bytes, String? name, String? ext, String? mime})?> pickImageBytes() async {
  final res = await FilePicker.platform.pickFiles(
    type: FileType.image,
    withData: true,      // 关键：要 bytes
    allowMultiple: false,
  );
  if (res == null || res.files.isEmpty) return null;

  final f = res.files.single;
  Uint8List? bytes = f.bytes;
  // 有些机型没给 bytes，但给了 path，兜底读一次
  if (bytes == null && f.path != null) {
    bytes = await File(f.path!).readAsBytes();
  }
  if (bytes == null) return null;

  // 猜扩展名/类型（能用就行）
  final ext = f.extension?.toLowerCase();
  final name = f.name;
  final mime = switch (ext) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'jpeg' || 'jpg' => 'image/jpeg',
    _ => 'image/*',
  };

  return (bytes: bytes, name: name, ext: ext, mime: mime);
}

class _SellFormPageState extends State<SellFormPage> with TickerProviderStateMixin {
  /* ------------ Controllers & State ------------ */
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  bool _submitting = false;
  String _progressMsg = '';

  final Map<String, TextEditingController> _dynamicControllers = {};
  final _cameraPicker = ImagePicker();

  // 用 record 存每张图的 bytes + 元信息
  final List<({Uint8List bytes, String? name, String? ext, String? mime})> _images = [];

  String _category = '';
  String _city = 'Harare';
  final Map<String, String> _dynamicValues = {};

  // Coupon related state
  List<CouponModel> _availableCoupons = [];
  CouponModel? _selectedCoupon;
  bool _loadingCoupons = false;
  bool _showCouponSection = false;

  // 若从优惠券页跳转带入 couponId，这里读取并自动预选
  String? _initialCouponIdFromRoute;

  static const _maxPhotos = 10;

  final _cities = const [
    'Harare', 'Bulawayo', 'Chitungwiza', 'Mutare', 'Gweru', 'Kwekwe',
    'Kadoma', 'Masvingo', 'Chinhoyi', 'Chegutu', 'Bindura', 'Marondera', 'Redcliff'
  ];

  final _categories = const [
    'Vehicles', 'Property', 'Beauty and Personal Care', 'Jobs', 'Babies and Kids',
    'Services', 'Leisure Activities', 'Repair and Construction', 'Home Furniture and Appliances',
    'Pets', 'Electronics', 'Phones and Tablets', 'Seeking Work and CVs', 'Fashion', 'Food Agriculture and Drinks'
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
    _loadAvailableCoupons();
    _animationController.forward();
  }

  // 读取来自路由的 couponId（如果有）
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['couponId'] != null) {
      _initialCouponIdFromRoute = args['couponId'].toString();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _titleCtrl.dispose();
    _priceCtrl.dispose();
    _descCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    for (final c in _dynamicControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /* ---------- Load Available Coupons ---------- */
  Future<void> _loadAvailableCoupons() async {
    setState(() => _loadingCoupons = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        // 使用服务端统一过滤的“可用于置顶”的优惠券
        final coupons = await CouponService.getPinningEligibleCoupons(user.id);

        if (mounted) {
          // 仅保留可用，并按优先级排序
          final usable = coupons.where((c) => c.isUsable).toList()
            ..sort((a, b) => b.priority.compareTo(a.priority));

          // 若有路由携带 couponId，则自动选中
          CouponModel? preselect;
          if (_initialCouponIdFromRoute != null) {
            try {
              preselect = usable.firstWhere((c) => c.id == _initialCouponIdFromRoute);
            } catch (_) {
              preselect = null;
            }
          }

          setState(() {
            _availableCoupons = usable;
            _selectedCoupon = preselect;
            _showCouponSection = _availableCoupons.isNotEmpty;
          });
        }
      }
    } catch (e) {
      debugPrint('Failed to load coupons: $e');
    } finally {
      if (mounted) setState(() => _loadingCoupons = false);
    }
  }

  TextEditingController _getController(String key) {
    return _dynamicControllers.putIfAbsent(key, () => TextEditingController());
  }

  /* ---------- Category Specific Fields ---------- */
  List<Widget> _getCategorySpecificFields() {
    switch (_category) {
      case 'Vehicles':
        return [
          _buildCompactDropdown('Vehicle Type *', 'vehicleType', [
            'Car', 'Motorcycle', 'Truck', 'Bus', 'Van', 'Tractor', 'Boat', 'Other'
          ], isRequired: true),
          SizedBox(height: 12.h),
          _buildCompactTextField('make', 'Make/Brand *', 'e.g. Toyota, Honda', isRequired: true),
          SizedBox(height: 12.h),
          _buildCompactTextField('model', 'Model *', 'e.g. Corolla, Civic', isRequired: true),
          SizedBox(height: 12.h),
          _buildCompactTextField('year', 'Year', 'e.g. 2020', keyboardType: TextInputType.number),
          SizedBox(height: 12.h),
          _buildCompactTextField('mileage', 'Mileage (km)', 'e.g. 50000', keyboardType: TextInputType.number),
          SizedBox(height: 12.h),
          _buildCompactDropdown('Fuel Type', 'fuelType', [
            'Petrol', 'Diesel', 'Electric', 'Hybrid', 'LPG', 'Other'
          ]),
          SizedBox(height: 12.h),
          _buildCompactDropdown('Transmission', 'transmission', [
            'Manual', 'Automatic', 'Semi-Automatic'
          ]),
        ];

      case 'Property':
        return [
          _buildCompactDropdown('Property Type *', 'propertyType', [
            'House', 'Apartment', 'Land', 'Commercial', 'Office Space', 'Warehouse', 'Farm'
          ], isRequired: true),
          SizedBox(height: 12.h),
          _buildCompactDropdown('Listing Type *', 'listingType', [
            'For Sale', 'For Rent', 'Lease'
          ], isRequired: true),
          SizedBox(height: 12.h),
          _buildCompactTextField('bedrooms', 'Bedrooms', '', keyboardType: TextInputType.number),
          SizedBox(height: 12.h),
          _buildCompactTextField('bathrooms', 'Bathrooms', '', keyboardType: TextInputType.number),
          SizedBox(height: 12.h),
          _buildCompactTextField('area', 'Area (sq meters)', '', keyboardType: TextInputType.number),
        ];

      case 'Beauty and Personal Care':
        return [
          _buildCompactDropdown('Product Type *', 'beautyType', [
            'Skincare', 'Makeup', 'Hair Care', 'Perfume', 'Tools & Accessories', 'Other'
          ], isRequired: true),
          SizedBox(height: 12.h),
          _buildCompactTextField('brand', 'Brand', ''),
          SizedBox(height: 12.h),
          _buildCompactDropdown('Condition', 'condition', [
            'New', 'Like New', 'Used', 'Sample Size'
          ]),
        ];

      case 'Electronics':
        return [
          _buildCompactDropdown('Product Type *', 'electronicsType', [
            'TV & Audio', 'Computer & Laptop', 'Camera & Photo', 'Gaming', 'Home Appliances', 'Other'
          ], isRequired: true),
          SizedBox(height: 12.h),
          _buildCompactTextField('brand', 'Brand', 'e.g. Samsung, Apple, Sony'),
          SizedBox(height: 12.h),
          _buildCompactTextField('model', 'Model', ''),
          SizedBox(height: 12.h),
          _buildCompactDropdown('Condition', 'condition', [
            'New', 'Like New', 'Good', 'Fair', 'For Parts'
          ]),
        ];

      case 'Fashion':
        return [
          _buildCompactDropdown('Category *', 'fashionCategory', [
            'Men\'s Clothing', 'Women\'s Clothing', 'Shoes', 'Accessories', 'Bags', 'Watches', 'Jewelry'
          ], isRequired: true),
          SizedBox(height: 12.h),
          _buildCompactTextField('brand', 'Brand', ''),
          SizedBox(height: 12.h),
          _buildCompactTextField('size', 'Size', 'e.g. M, L, 42, etc.'),
          SizedBox(height: 12.h),
          _buildCompactDropdown('Condition', 'condition', [
            'New with tags', 'New without tags', 'Very good', 'Good', 'Acceptable'
          ]),
        ];

      default:
        return [];
    }
  }

  Widget _buildCompactTextField(String key, String label, String hint, {
    bool isRequired = false,
    TextInputType? keyboardType,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4.r,
            offset: Offset(0, 1.h),
          ),
        ],
      ),
      child: TextFormField(
        controller: _getController(key),
        keyboardType: keyboardType,
        style: TextStyle(fontSize: 13.sp),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10.r),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.white,
          labelStyle: TextStyle(fontSize: 12.sp, color: Colors.grey.shade600),
          hintStyle: TextStyle(fontSize: 11.sp, color: Colors.grey.shade400),
        ),
        validator: isRequired ? (v) => v!.isEmpty ? 'Required' : null : null,
      ),
    );
  }

  Widget _buildCompactDropdown(String label, String key, List<String> items, {bool isRequired = false}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4.r,
            offset: Offset(0, 1.h),
          ),
        ],
      ),
      child: DropdownButtonFormField<String>(
        decoration: InputDecoration(
          labelText: label,
          contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10.r),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.white,
          labelStyle: TextStyle(fontSize: 12.sp, color: Colors.grey.shade600),
        ),
        value: _dynamicValues[key],
        items: items.map((c) => DropdownMenuItem(
            value: c,
            child: Text(c, style: TextStyle(fontSize: 13.sp))
        )).toList(),
        onChanged: (v) => setState(() => _dynamicValues[key] = v ?? ''),
        validator: isRequired ? (v) => v == null ? 'Please select $label' : null : null,
        style: TextStyle(fontSize: 13.sp, color: Colors.black87),
        dropdownColor: Colors.white,
      ),
    );
  }

  /* ---------- Submit Functions ---------- */
  // ✅ 本地发布（mock）：需要把 bytes 写到临时文件才能预览
  Future<void> _publishLocalOnly() async {
    // 守卫：未登录/未验证则引导
    if (!await VerificationGuard.ensureVerifiedOrPrompt(context, feature: AppFeature.postListing)) return;

    if (!_formKey.currentState!.validate()) return;
    if (_images.isEmpty) {
      _toast('Please upload at least one photo.');
      return;
    }

    // 将内存图片写入临时目录，便于本地预览
    final tempDir = await getTemporaryDirectory();
    final paths = <String>[];
    for (final img in _images) {
      final ext = (img.ext?.isNotEmpty == true) ? img.ext! : 'jpg';
      final path = '${tempDir.path}/local_${DateTime.now().millisecondsSinceEpoch}_${paths.length}.$ext';
      final f = File(path);
      await f.writeAsBytes(img.bytes);
      paths.add(path);
    }

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final listing = {
      'id': id,
      'category': _category,
      'images': paths, // 本地预览用路径，不涉及上传
      'title': _titleCtrl.text.trim(),
      'price': '\$${_priceCtrl.text.trim()}',
      'location': _city,
      'postedDate': DateTime.now().toIso8601String(),
      'description': _descCtrl.text.trim(),
      'sellerName': _nameCtrl.text.trim(),
      'sellerPhone': _phoneCtrl.text.trim(),
    };
    ListingStore.i.add(listing);
    _toast('Posted locally (mock data).');
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => pd.ProductDetailPage(productId: id, productData: listing),
      ),
    );
  }

  Future<void> _submitListing() async {
    // 守卫：未登录/未验证则引导
    if (!await VerificationGuard.ensureVerifiedOrPrompt(context, feature: AppFeature.postListing)) return;

    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;
    if (_images.isEmpty) {
      _toast('Please upload at least one photo.');
      return;
    }

    if (!kUploadToRemote) {
      await _publishLocalOnly();
      return;
    }

    setState(() {
      _submitting = true;
      _progressMsg = 'Preparing...';
    });

    try {
      final auth = Supabase.instance.client.auth;
      if (auth.currentUser == null) {
        await auth.signInAnonymously();
      }
      final userId = auth.currentUser!.id;

      // ===== 使用 bytes 上传到 Supabase Storage =====
      final urls = <String>[];
      final total = _images.length;
      for (var i = 0; i < _images.length; i++) {
        final img = _images[i];
        if (!mounted) return;
        setState(() => _progressMsg = 'Uploading photos ${i + 1} / $total');

        final ext = (img.ext?.isNotEmpty == true) ? img.ext! : 'jpg';
        final fileName = 'img_${DateTime.now().millisecondsSinceEpoch}_$i.$ext';
        final objectPath = '$userId/${DateTime.now().millisecondsSinceEpoch}_$fileName';

        await Supabase.instance.client.storage
            .from('listings')
            .uploadBinary(
          objectPath,
          img.bytes, // 👈 直接 bytes
          fileOptions: FileOptions(
            contentType: img.mime ?? 'image/*',
            upsert: false,
          ),
        );

        final publicUrl = Supabase.instance.client.storage
            .from('listings')
            .getPublicUrl(objectPath);

        urls.add(publicUrl);
      }

      // 组合额外字段
      final extrasLines = <String>[];
      for (final entry in _dynamicControllers.entries) {
        final v = entry.value.text.trim();
        if (v.isNotEmpty) extrasLines.add('${entry.key}: $v');
      }
      _dynamicValues.forEach((k, v) {
        final vv = v.trim();
        if (vv.isNotEmpty) extrasLines.add('$k: $vv');
      });
      final extrasText = extrasLines.isEmpty ? '' : '\n\n---\nExtras:\n${extrasLines.join('\n')}';
      final desc = '${_descCtrl.text.trim()}$extrasText';

      // Insert listing
      setState(() => _progressMsg = 'Saving item...');
      final priceText = _priceCtrl.text.trim().replaceAll(',', '');
      num? price = priceText.isEmpty ? null : num.tryParse(priceText);

      final row = await ListingApi.insertListing(
        title: _titleCtrl.text.trim(),
        price: price,
        category: _category,
        city: _city,
        description: desc,
        imageUrls: urls, // ⬅️ 写入上传后的 urls
        userId: userId,
        sellerName: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        contactPhone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      );

      if (!mounted) return;

      // Handle coupon usage
      String? listingId = row['id']?.toString();
      if (_selectedCoupon != null && listingId != null) {
        await _useCouponForPinning(listingId);
      }

      // Handle post-publish rewards
      await _handlePostPublishRewards(userId);

      _toast('Posted successfully!');

      // Navigate to detail page（直接带上我们刚上传的 urls 以保证可展示）
      final productId = row['id'].toString();
      final productData = {
        'id': productId,
        'category': row['category'] ?? '',
        'images': urls, // ⬅️ 用我们本地掌握的 urls，避免后端返回字段缺失
        'title': row['title'] ?? '',
        'price': row['price'] == null ? '' : '\$${(row['price'] as num).toStringAsFixed(2)}',
        'location': row['city'] ?? '',
        'postedDate': row['created_at'] ?? DateTime.now().toIso8601String(),
        'description': row['description'] ?? '',
        'sellerName': row['seller_name'] ?? _nameCtrl.text.trim(),
        'sellerPhone': row['contact_phone'] ?? _phoneCtrl.text.trim(),
      };

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => pd.ProductDetailPage(
            productId: productId,
            productData: productData,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _toast('Post failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _progressMsg = '';
        });
      }
    }
  }

  Future<void> _useCouponForPinning(String listingId) async {
    if (_selectedCoupon == null) return;

    try {
      setState(() => _progressMsg = 'Applying coupon...');

      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Not logged in');
      }

      await CouponService.useCouponForPinning(
        couponId: _selectedCoupon!.id,
        listingId: listingId,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.star, color: Colors.white, size: 20.r),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  '🎉 Coupon applied! Item pinned ${_getCouponPinningDescription(_selectedCoupon!.type)} for ${_selectedCoupon!.effectivePinDays} days.',
                  style: TextStyle(fontSize: 14.sp),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.orange[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
          margin: EdgeInsets.all(16.w),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      debugPrint('Failed to use coupon: $e');
      _toast('Failed to use coupon: $e');
    }
  }

  String _getCouponPinningDescription(CouponType type) {
    switch (type) {
      case CouponType.trending:
      case CouponType.trendingPin:
        return 'to the hot section';
      case CouponType.category:
      case CouponType.pinned:
      case CouponType.featured:
      case CouponType.premium:
        return 'to the top of the category page';
      default:
        return 'to the top';
    }
  }

  Future<void> _handlePostPublishRewards(String userId) async {
    try {
      await RewardService.updateTaskProgress(
        userId: userId,
        taskType: 'publish_items',
        increment: 1,
      );

      await RewardService.handleInviteeFirstPost(userId);
      await _showTaskProgressIfNeeded(userId);

    } catch (e) {
      // ignore: avoid_print
      print('Failed to handle post-publish rewards: $e');
    }
  }

  // 安全查找活跃的发布任务（替代 firstOrNull，避免编译问题）
  Map<String, dynamic>? _findActivePublishTask(List<Map<String, dynamic>> tasks) {
    for (final t in tasks) {
      if (t['task_type'] == 'publish_items' && t['status'] == 'active') {
        return t;
      }
    }
    return null;
  }

  Future<void> _showTaskProgressIfNeeded(String userId) async {
    try {
      final tasks = await RewardService.getActiveTasks(userId);
      final publishTask = _findActivePublishTask(tasks);

      if (publishTask != null) {
        final current = (publishTask['current_count'] as num?)?.toInt() ?? 0;
        final target = (publishTask['target_count'] as num?)?.toInt() ?? 0;

        if (current < target) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.task_alt, color: Colors.white, size: 20.r),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Text(
                      'Publishing progress: $current/$target items - Complete to earn hot pin!',
                      style: TextStyle(fontSize: 14.sp),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.orange[600],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.r),
              ),
              margin: EdgeInsets.all(16.w),
            ),
          );
        } else if (current >= target) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.celebration, color: Colors.white, size: 20.r),
                  SizedBox(width: 8.w),
                  const Text('🎉 Congratulations! Publishing task completed - Hot pin earned!'),
                ],
              ),
              backgroundColor: Colors.green[600],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.r),
              ),
              margin: EdgeInsets.all(16.w),
            ),
          );
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('Failed to show task progress: $e');
    }
  }

  /* ---------- Image Picker UI ---------- */
  Future<void> _pickImage() async {
    if (_images.length >= _maxPhotos) {
      _toast('You can upload up to $_maxPhotos photos.');
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: EdgeInsets.all(20.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 40.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
              SizedBox(height: 20.h),
              Text(
                'Add Photo',
                style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 20.h),
              Row(
                children: [
                  Expanded(
                    child: _buildImageOption(
                      Icons.photo_camera_rounded,
                      'Camera',
                          () async {
                        Navigator.pop(context);
                        final file = await _cameraPicker.pickImage(
                          source: ImageSource.camera,
                          imageQuality: 80,
                        );
                        if (file != null && mounted) {
                          if (_images.length >= _maxPhotos) {
                            _toast('You can upload up to $_maxPhotos photos.');
                            return;
                          }
                          final bytes = await file.readAsBytes();
                          setState(() => _images.add((
                          bytes: bytes,
                          name: 'camera_${DateTime.now().millisecondsSinceEpoch}.jpg',
                          ext: 'jpg',
                          mime: 'image/jpeg',
                          )));
                        }
                      },
                    ),
                  ),
                  SizedBox(width: 16.w),
                  Expanded(
                    child: _buildImageOption(
                      Icons.photo_library_rounded,
                      'Gallery',
                          () async {
                        Navigator.pop(context);
                        // ✅ 只在一个地方调用 bytes 版选图
                        final picked = await pickImageBytes();
                        if (picked == null) {
                          debugPrint('[Picker] cancelled or failed');
                          return;
                        }
                        if (!mounted) return;
                        if (_images.length >= _maxPhotos) {
                          _toast('You can upload up to $_maxPhotos photos.');
                          return;
                        }
                        setState(() => _images.add(picked));
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildImageOption(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 16.h),
        decoration: BoxDecoration(
          color: const Color(0xFF2196F3).withOpacity(0.1),
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: const Color(0xFF2196F3).withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.all(12.r),
              decoration: BoxDecoration(
                color: const Color(0xFF2196F3),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(icon, color: Colors.white, size: 24.r),
            ),
            SizedBox(height: 8.h),
            Text(
              label,
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF2196F3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: TextStyle(fontSize: 12.sp)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
        margin: EdgeInsets.all(12.r),
      ),
    );
  }

  /* ------------------ UI ------------------ */
  @override
  Widget build(BuildContext context) {
    final categoryFields = _getCategorySpecificFields();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2196F3),
        title: Text(
          'New Advert',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20.r),
        ),
        elevation: 0,
        centerTitle: true,
      ),
      body: Stack(
        children: [
          AbsorbPointer(
            absorbing: _submitting,
            child: SlideTransition(
              position: _slideAnimation,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(12.w),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Photo Upload Section
                        _buildPhotoSection(),
                        SizedBox(height: 12.h),

                        // Category Dropdown
                        _buildCategorySection(),
                        SizedBox(height: 12.h),

                        // Dynamic Fields
                        if (categoryFields.isNotEmpty) ...[
                          ...categoryFields,
                          SizedBox(height: 12.h),
                        ],

                        // Basic Info Section
                        _buildBasicInfoSection(),
                        SizedBox(height: 12.h),

                        // Coupon Section
                        if (_showCouponSection) ...[
                          _buildCouponSelectionSection(),
                          SizedBox(height: 12.h),
                        ],

                        // Seller Info Section
                        _buildSellerInfoSection(),
                        SizedBox(height: 16.h),

                        // Submit Button
                        _buildSubmitButton(),
                        SizedBox(height: 12.h),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Loading Overlay
          if (_submitting)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: Center(
                child: Container(
                  padding: EdgeInsets.all(24.w),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16.r),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(
                        color: Color(0xFF2196F3),
                        strokeWidth: 3,
                      ),
                      SizedBox(height: 16.h),
                      Text(
                        _progressMsg,
                        style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPhotoSection() {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6.r,
            offset: Offset(0, 2.h),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(6.r),
                decoration: BoxDecoration(
                  color: const Color(0xFF2196F3).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Icon(Icons.camera_alt_rounded, color: const Color(0xFF2196F3), size: 16.r),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Photos',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.sp),
                    ),
                    Text(
                      'Add up to $_maxPhotos photos. First photo will be main.',
                      style: TextStyle(fontSize: 10.sp, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),

          Container(
            constraints: BoxConstraints(minHeight: 60.h),
            child: Wrap(
              spacing: 6.w,
              runSpacing: 6.h,
              children: [
                ..._images.asMap().entries.map((entry) {
                  final index = entry.key;
                  final img = entry.value;
                  return _buildImagePreview(index, img.bytes);
                }),
                if (_images.length < _maxPhotos)
                  _buildAddPhotoButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview(int index, Uint8List bytes) {
    return Stack(
      children: [
        Container(
          width: 60.w,
          height: 60.w,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10.r),
            border: index == 0
                ? Border.all(color: const Color(0xFF2196F3), width: 2)
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10.r),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                ),
                if (index == 0)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [const Color(0xFF2196F3), const Color(0xFF1976D2)],
                        ),
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(10.r),
                          bottomRight: Radius.circular(10.r),
                        ),
                      ),
                      padding: EdgeInsets.symmetric(vertical: 2.h),
                      child: Text(
                        'Main',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 8.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Positioned(
          right: -3,
          top: -3,
          child: GestureDetector(
            onTap: () => setState(() => _images.removeAt(index)),
            child: Container(
              padding: EdgeInsets.all(3.r),
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 2.r,
                  ),
                ],
              ),
              child: Icon(Icons.close, size: 10.r, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAddPhotoButton() {
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        width: 60.w,
        height: 60.w,
        decoration: BoxDecoration(
          color: const Color(0xFF2196F3).withOpacity(0.1),
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: const Color(0xFF2196F3).withOpacity(0.3), width: 2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo_rounded, color: const Color(0xFF2196F3), size: 20.r),
            SizedBox(height: 2.h),
            Text(
              'Add Photo',
              style: TextStyle(fontSize: 8.sp, color: const Color(0xFF2196F3), fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategorySection() {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6.r,
            offset: Offset(0, 2.h),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(6.r),
                decoration: BoxDecoration(
                  color: const Color(0xFF2196F3).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Icon(Icons.category_rounded, color: const Color(0xFF2196F3), size: 16.r),
              ),
              SizedBox(width: 8.w),
              Text(
                'Select Category *',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.sp),
              ),
            ],
          ),
          SizedBox(height: 10.h),

          // 自定义设计的分类选择器
          GestureDetector(
            onTap: _showCategoryPicker,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10.r),
                border: Border.all(
                  color: _category.isEmpty ? Colors.red.shade300 : Colors.grey.shade300,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  if (_category.isNotEmpty) ...[
                    Container(
                      width: 20.w,
                      height: 20.w,
                      decoration: BoxDecoration(
                        color: _getCategoryColor(_category).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(5.r),
                      ),
                      child: Icon(
                        _getCategoryIcon(_category),
                        color: _getCategoryColor(_category),
                        size: 12.r,
                      ),
                    ),
                    SizedBox(width: 10.w),
                  ],
                  Expanded(
                    child: Text(
                      _category.isEmpty ? 'Choose a category for your item' : _category,
                      style: TextStyle(
                        fontSize: 13.sp,
                        color: _category.isEmpty ? Colors.grey.shade500 : Colors.black87,
                        fontWeight: _category.isEmpty ? FontWeight.w400 : FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.keyboard_arrow_down,
                    color: Colors.grey.shade600,
                    size: 20.r,
                  ),
                ],
              ),
            ),
          ),

          // 表单验证
          if (_category.isEmpty && _formKey.currentState?.validate() == false)
            Padding(
              padding: EdgeInsets.only(top: 4.h, left: 12.w),
              child: Text(
                'Please select a category',
                style: TextStyle(
                  color: Colors.red.shade600,
                  fontSize: 11.sp,
                ),
              ),
            ),

          // 选中的分类显示
          if (_category.isNotEmpty) ...[
            SizedBox(height: 8.h),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(8.w),
              decoration: BoxDecoration(
                color: _getCategoryColor(_category).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(
                  color: _getCategoryColor(_category).withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    color: _getCategoryColor(_category),
                    size: 14.r,
                  ),
                  SizedBox(width: 6.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Selected Category',
                          style: TextStyle(
                            fontSize: 9.sp,
                            color: _getCategoryColor(_category).withOpacity(0.8),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: 1.h),
                        Text(
                          _category,
                          style: TextStyle(
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w600,
                            color: _getCategoryColor(_category),
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _category = ''),
                    child: Container(
                      padding: EdgeInsets.all(3.r),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 2.r,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.close,
                        size: 10.r,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showCategoryPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.45,
          padding: EdgeInsets.all(12.w),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
          ),
          child: Column(
            children: [
              Container(
                width: 32.w,
                height: 3.h,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(1.5.r),
                ),
              ),
              SizedBox(height: 12.h),
              Text(
                'Select Category',
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 12.h),
              Expanded(
                child: ListView.builder(
                  itemCount: _categories.length,
                  itemBuilder: (context, index) {
                    final category = _categories[index];
                    return Container(
                      margin: EdgeInsets.only(bottom: 4.h),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8.r),
                          onTap: () {
                            setState(() {
                              _category = category;
                              _dynamicValues.clear();
                              for (final c in _dynamicControllers.values) {
                                c.clear();
                              }
                            });
                            Navigator.pop(context);
                          },
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8.r),
                              border: Border.all(
                                color: Colors.grey.shade200,
                                width: 0.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 28.w,
                                  height: 28.w,
                                  decoration: BoxDecoration(
                                    color: _getCategoryColor(category).withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(6.r),
                                  ),
                                  child: Icon(
                                    _getCategoryIcon(category),
                                    color: _getCategoryColor(category),
                                    size: 14.r,
                                  ),
                                ),
                                SizedBox(width: 10.w),
                                Expanded(
                                  child: Text(
                                    category,
                                    style: TextStyle(
                                      fontSize: 13.sp,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Vehicles':
        return Icons.directions_car_rounded;
      case 'Property':
        return Icons.home_rounded;
      case 'Beauty and Personal Care':
        return Icons.face_rounded;
      case 'Jobs':
        return Icons.work_rounded;
      case 'Babies and Kids':
        return Icons.child_care_rounded;
      case 'Services':
        return Icons.handyman_rounded;
      case 'Leisure Activities':
        return Icons.sports_soccer_rounded;
      case 'Repair and Construction':
        return Icons.build_rounded;
      case 'Home Furniture and Appliances':
        return Icons.chair_rounded;
      case 'Pets':
        return Icons.pets_rounded;
      case 'Electronics':
        return Icons.devices_rounded;
      case 'Phones and Tablets':
        return Icons.smartphone_rounded;
      case 'Seeking Work and CVs':
        return Icons.assignment_ind_rounded;
      case 'Fashion':
        return Icons.checkroom_rounded;
      case 'Food Agriculture and Drinks':
        return Icons.restaurant_rounded;
      default:
        return Icons.category_rounded;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Vehicles':
        return Colors.blue.shade600;
      case 'Property':
        return Colors.green.shade600;
      case 'Beauty and Personal Care':
        return Colors.pink.shade400;
      case 'Jobs':
        return Colors.orange.shade600;
      case 'Babies and Kids':
        return Colors.purple.shade400;
      case 'Services':
        return Colors.teal.shade600;
      case 'Leisure Activities':
        return Colors.red.shade500;
      case 'Repair and Construction':
        return Colors.brown.shade600;
      case 'Home Furniture and Appliances':
        return Colors.indigo.shade600;
      case 'Pets':
        return Colors.amber.shade700;
      case 'Electronics':
        return Colors.cyan.shade600;
      case 'Phones and Tablets':
        return Colors.deepPurple.shade600;
      case 'Seeking Work and CVs':
        return Colors.lightGreen.shade700;
      case 'Fashion':
        return Colors.deepOrange.shade600;
      case 'Food Agriculture and Drinks':
        return Colors.lime.shade700;
      default:
        return const Color(0xFF2196F3);
    }
  }

  Widget _buildBasicInfoSection() {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6.r,
            offset: Offset(0, 2.h),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Basic Information',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.sp),
          ),
          SizedBox(height: 12.h),

          // Title
          TextFormField(
            controller: _titleCtrl,
            style: TextStyle(fontSize: 13.sp),
            decoration: InputDecoration(
              labelText: 'Title *',
              contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10.r),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              labelStyle: TextStyle(fontSize: 12.sp),
            ),
            validator: (v) => v!.isEmpty ? 'Required' : null,
          ),
          SizedBox(height: 12.h),

          // Price
          TextFormField(
            controller: _priceCtrl,
            keyboardType: TextInputType.number,
            style: TextStyle(fontSize: 13.sp),
            decoration: InputDecoration(
              labelText: 'Price (USD) *',
              prefixText: '\$ ',
              contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10.r),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              labelStyle: TextStyle(fontSize: 12.sp),
            ),
            validator: (v) => v!.isEmpty ? 'Required' : null,
          ),
          SizedBox(height: 12.h),

          // Region
          DropdownButtonFormField<String>(
            decoration: InputDecoration(
              labelText: 'Region *',
              contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10.r),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              labelStyle: TextStyle(fontSize: 12.sp),
            ),
            value: _city,
            items: _cities.map((c) => DropdownMenuItem(
                value: c,
                child: Text(c, style: TextStyle(fontSize: 13.sp))
            )).toList(),
            onChanged: (v) => setState(() => _city = v!),
            style: TextStyle(fontSize: 13.sp, color: Colors.black87),
          ),
          SizedBox(height: 12.h),

          // Description
          TextFormField(
            controller: _descCtrl,
            maxLines: 3,
            style: TextStyle(fontSize: 13.sp),
            decoration: InputDecoration(
              labelText: 'Description',
              contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10.r),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              labelStyle: TextStyle(fontSize: 12.sp),
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSellerInfoSection() {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6.r,
            offset: Offset(0, 2.h),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(6.r),
                decoration: BoxDecoration(
                  color: const Color(0xFF2196F3).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Icon(Icons.person_rounded, color: const Color(0xFF2196F3), size: 16.r),
              ),
              SizedBox(width: 8.w),
              Text(
                'Seller Information',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.sp),
              ),
            ],
          ),
          SizedBox(height: 12.h),

          // Name
          TextFormField(
            controller: _nameCtrl,
            style: TextStyle(fontSize: 13.sp),
            decoration: InputDecoration(
              labelText: 'Your Name *',
              contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10.r),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              labelStyle: TextStyle(fontSize: 12.sp),
            ),
            validator: (v) => v!.isEmpty ? 'Required' : null,
          ),
          SizedBox(height: 12.h),

          // Phone
          TextFormField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            style: TextStyle(fontSize: 13.sp),
            decoration: InputDecoration(
              labelText: 'Phone Number *',
              hintText: '+263 77 123 4567',
              contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10.r),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              labelStyle: TextStyle(fontSize: 12.sp),
              hintStyle: TextStyle(fontSize: 11.sp, color: Colors.grey.shade400),
            ),
            validator: (v) => v!.isEmpty ? 'Required' : null,
          ),
        ],
      ),
    );
  }

  Widget _buildCouponSelectionSection() {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.orange.shade50,
            Colors.orange.shade100,
          ],
        ),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8.r),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.orange.shade400, Colors.orange.shade600],
                  ),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Icon(Icons.card_giftcard, color: Colors.white, size: 16.r),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Use Coupon for Pinning',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange.shade800,
                      ),
                    ),
                    Text(
                      'Pin your item to get more visibility',
                      style: TextStyle(
                        fontSize: 10.sp,
                        color: Colors.orange.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),

          if (_loadingCoupons)
            const Center(child: CircularProgressIndicator(color: Colors.orange))
          else if (_availableCoupons.isEmpty)
            Container(
              padding: EdgeInsets.all(10.w),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey.shade600, size: 14.r),
                  SizedBox(width: 6.w),
                  Expanded(
                    child: Text(
                      'No coupons available. Complete tasks to earn pinning coupons!',
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else ...[
              Text(
                'Select a coupon to use:',
                style: TextStyle(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 10.h),
              Wrap(
                spacing: 6.w,
                runSpacing: 6.h,
                children: [
                  _buildCouponOption(null, 'No Coupon', 'Post without pinning'),
                  ..._availableCoupons.map((coupon) => _buildCouponOption(
                    coupon,
                    coupon.title,
                    '${_getCouponTypeDescription(coupon.type)} • ${coupon.expiryStatusText}',
                  )).toList(),
                ],
              ),
            ],
        ],
      ),
    );
  }

  Widget _buildCouponOption(CouponModel? coupon, String title, String subtitle) {
    final isSelected = _selectedCoupon?.id == coupon?.id && coupon != null ||
        (_selectedCoupon == null && coupon == null);

    return GestureDetector(
      onTap: () => setState(() => _selectedCoupon = coupon),
      child: Container(
        padding: EdgeInsets.all(10.w),
        decoration: BoxDecoration(
          color: isSelected ? Colors.orange.shade100 : Colors.white,
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(
            color: isSelected ? Colors.orange.shade400 : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 14.w,
                  height: 14.w,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? Colors.orange : Colors.transparent,
                    border: Border.all(
                      color: isSelected ? Colors.orange : Colors.grey.shade400,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? Icon(Icons.check, size: 8.r, color: Colors.white)
                      : null,
                ),
                SizedBox(width: 6.w),
                Flexible(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.orange.shade800 : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 3.h),
            Padding(
              padding: EdgeInsets.only(left: 20.w),
              child: Text(
                subtitle,
                style: TextStyle(
                  fontSize: 10.sp,
                  color: isSelected ? Colors.orange.shade600 : Colors.grey.shade600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getCouponTypeDescription(CouponType type) {
    switch (type) {
      case CouponType.welcome:
        return 'Welcome – Category Pinning (3 days)';
      case CouponType.trending:
      case CouponType.trendingPin:
        return 'Hot Section Pinning';
      case CouponType.category:
      case CouponType.pinned:
      case CouponType.featured:
      case CouponType.premium:
        return 'Category Pinning';
      case CouponType.boost:
        return 'Boost Promotion';
      case CouponType.registerBonus:
      case CouponType.referralBonus:
      case CouponType.activityBonus:
        return 'Reward';
      default:
        return 'Coupon';
    }
  }

  Widget _buildSubmitButton() {
    return Container(
      width: double.infinity,
      height: 42.h,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
        ),
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2196F3).withOpacity(0.3),
            blurRadius: 8.r,
            offset: Offset(0, 4.h),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _submitting ? null : (kUploadToRemote ? _submitListing : _publishLocalOnly),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
        ),
        child: _submitting
            ? SizedBox(
          height: 18.h,
          width: 18.w,
          child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        )
            : Text(
          'Post Advertisement',
          style: TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
