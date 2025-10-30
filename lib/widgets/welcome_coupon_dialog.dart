// lib/widgets/welcome_coupon_dialog.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class WelcomeCouponDialog extends StatefulWidget {
  final Map<String, dynamic> couponData;

  const WelcomeCouponDialog({
    Key? key,
    required this.couponData,
  }) : super(key: key);

  @override
  State<WelcomeCouponDialog> createState() => _WelcomeCouponDialogState();
}

class _WelcomeCouponDialogState extends State<WelcomeCouponDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  // Windows-1252（CP1252） “反向映射”，用于把误解码后的符号还原成原始字节，再整体按 UTF-8 正确解码。
  static const Map<int, int> _cp1252Reverse = {
    0x20AC: 0x80, // €
    0x201A: 0x82, // ‚
    0x0192: 0x83, // ƒ
    0x201E: 0x84, // „
    0x2026: 0x85, // …
    0x2020: 0x86, // †
    0x2021: 0x87, // ‡
    0x02C6: 0x88, // ˆ
    0x2030: 0x89, // ‰
    0x0160: 0x8A, // Š
    0x2039: 0x8B, // ‹
    0x0152: 0x8C, // Œ
    0x017D: 0x8E, // Ž
    0x2018: 0x91, // ‘
    0x2019: 0x92, // ’
    0x201C: 0x93, // “
    0x201D: 0x94, // ”
    0x2022: 0x95, // •
    0x2013: 0x96, // –
    0x2014: 0x97, // —
    0x02DC: 0x98, // ˜
    0x2122: 0x99, // ™
    0x0161: 0x9A, // š
    0x203A: 0x9B, // ›
    0x0153: 0x9C, // œ
    0x017E: 0x9E, // ž
    0x0178: 0x9F, // Ÿ
  };

  // 纠正 “ðŸ… / Ã… / â€¦ / �” 等 UTF-8 被 CP1252/Latin-1 误解码后的乱码
  String _fixUtf8Mojibake(dynamic v) {
    final s = v?.toString() ?? '';
    if (s.isEmpty) return s;

    // 如果原字符串本身已经含有常见 emoji，就认为是正常 UTF-8，直接返回
    final hasEmoji = s.runes.any((r) => (r >= 0x1F300 && r <= 0x1FAFF));
    if (hasEmoji) return s;

    // 粗略判定“看起来像坏掉”的文本再处理，避免误修
    final looksBroken = s.contains('ð') ||
        s.contains('Ã') ||
        s.contains('Â') ||
        s.contains('â') ||
        s.contains('�') ||
        s.contains(RegExp(r'[€‚ƒ„…†‡ˆ‰Š‹ŒŽ‘’“”•–—˜™š›œžŸ]'));
    if (!looksBroken) return s;

    try {
      // 视作 CP1252 -> 取回字节 -> 再按 UTF-8 解码
      final bytes = <int>[];
      for (final rune in s.runes) {
        final code = rune;
        final mapped = _cp1252Reverse[code];
        if (mapped != null) {
          bytes.add(mapped);
        } else if (code <= 0xFF) {
          bytes.add(code & 0xFF);
        } else {
          bytes.add(0x3F); // 超出范围，用 '?' 占位，避免异常
        }
      }
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      // 兜底：Latin1.encode -> UTF8.decode
      try {
        return utf8.decode(latin1.encode(s), allowMalformed: true);
      } catch (_) {
        return s;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final code = (widget.couponData['code']?.toString() ?? '').toUpperCase();

    // 先修复可能的乱码
    final fixedTitle = _fixUtf8Mojibake(
      widget.couponData['title'] ?? 'Welcome gift 🎉',
    );
    final fixedDesc = _fixUtf8Mojibake(
      widget.couponData['description'] ??
          'Welcome to Swaply! Pin your item for free in any category.',
    );

    // 计算过期时间
    String expiryText = '';
    final expiresRaw = widget.couponData['expires_at'];
    if (expiresRaw != null) {
      try {
        final expiresAt = DateTime.parse(expiresRaw.toString());
        final daysLeft = expiresAt.difference(DateTime.now()).inDays;
        if (daysLeft > 0) {
          expiryText = 'Valid for $daysLeft days';
        } else {
          expiryText = 'Expiring soon';
        }
      } catch (_) {}
    }

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20.r),
      ),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: Container(
            constraints: BoxConstraints(maxWidth: 340.w),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.blue.shade50, Colors.purple.shade50],
              ),
              borderRadius: BorderRadius.circular(20.r),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 30.r,
                  offset: Offset(0, 15.h),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 顶部装饰条
                Container(
                  height: 8.h,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Colors.blue, Colors.purple],
                    ),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20.r),
                      topRight: Radius.circular(20.r),
                    ),
                  ),
                ),

                Padding(
                  padding: EdgeInsets.all(20.w),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 动画图标
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 800),
                        builder: (context, value, child) {
                          return Transform.rotate(
                            angle: value * 0.1,
                            child: Container(
                              width: 80.w,
                              height: 80.w,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.blue.shade400,
                                    Colors.purple.shade400,
                                  ],
                                ),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.blue.withOpacity(0.3),
                                    blurRadius: 20.r,
                                    offset: Offset(0, 10.h),
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.card_giftcard,
                                size: 40.sp,
                                color: Colors.white,
                              ),
                            ),
                          );
                        },
                      ),

                      SizedBox(height: 18.h),

                      // 主标题：优先显示券标题（已修复），否则退回默认
                      Text(
                        (fixedTitle.isNotEmpty ? fixedTitle : 'Welcome gift 🎉'),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 22.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                          height: 1.2,
                        ),
                      ),

                      SizedBox(height: 10.h),

                      // 副标题
                      Text(
                        'Coupon Code: $code',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: Colors.grey[700],
                        ),
                      ),

                      SizedBox(height: 18.h),

                      // 优惠券卡片
                      Container(
                        padding: EdgeInsets.all(16.w),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(
                            color: Colors.blue.withOpacity(0.2),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withOpacity(0.08),
                              blurRadius: 15.r,
                              offset: Offset(0, 5.h),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // 券码块（可选择复制）
                            Container(
                              width: double.infinity,
                              padding: EdgeInsets.symmetric(
                                horizontal: 20.w,
                                vertical: 10.h,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.blue.shade50,
                                    Colors.purple.shade50,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(8.r),
                                border: Border.all(
                                  color: Colors.blue.withOpacity(0.1),
                                ),
                              ),
                              child: Column(
                                children: [
                                  SelectableText(
                                    code,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 20.sp,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade700,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                  if (expiryText.isNotEmpty) ...[
                                    SizedBox(height: 4.h),
                                    Text(
                                      expiryText,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 11.sp,
                                        color: Colors.orange.shade600,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            SizedBox(height: 12.h),

                            // 描述
                            Text(
                              fixedDesc,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13.sp,
                                color: Colors.grey[600],
                                height: 1.4,
                              ),
                            ),

                            SizedBox(height: 8.h),

                            // 特性条
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 12.w,
                                vertical: 8.h,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(6.r),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    size: 14.sp,
                                    color: Colors.green,
                                  ),
                                  SizedBox(width: 4.w),
                                  Text(
                                    'Free Category Pinning',
                                    style: TextStyle(
                                      fontSize: 11.sp,
                                      color: Colors.green.shade700,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: 24.h),

                      // 按钮组
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(context),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.symmetric(vertical: 12.h),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8.r),
                                ),
                              ),
                              child: Text(
                                'Later',
                                style: TextStyle(
                                  fontSize: 14.sp,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 12.w),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Colors.blue, Colors.purple],
                                ),
                                borderRadius: BorderRadius.circular(8.r),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.blue.withOpacity(0.3),
                                    blurRadius: 8.r,
                                    offset: Offset(0, 4.h),
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  // 优惠券列表
                                  Navigator.pushNamed(context, '/coupons');
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  padding: EdgeInsets.symmetric(vertical: 12.h),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8.r),
                                  ),
                                ),
                                child: Text(
                                  'View My Coupons',
                                  style: TextStyle(
                                    fontSize: 14.sp,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
