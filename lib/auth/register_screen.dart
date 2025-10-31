// lib/auth/register_screen.dart  鈥?Updated: add Sign in with Apple (iOS only) + Google helper (PKCE)
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'login_screen.dart';
import 'package:swaply/services/auth_service.dart';
import 'package:swaply/services/oauth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:swaply/services/reward_service.dart';

// 鉁?Google 鐧诲綍鏀逛负浣跨敤鎴戜滑灏佽鐨?helper锛圥KCE + 娣遍摼鍥炶皟锛?
import 'package:swaply/auth/google_signin.dart' as gauth;

// 鉁?Apple 鐧诲綍鐩稿叧
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:swaply/services/apple_auth_service.dart';

class RegisterScreen extends StatefulWidget {
  final String? invitationCode;
  const RegisterScreen({Key? key, this.invitationCode}) : super(key: key);

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();

  /// 鐧诲綍鍚庣敱鍏ㄥ眬鐩戝惉鍣ㄨ鍙栧苟澶勭悊锛堢ぞ浜ょ櫥褰曚篃閫傜敤锛?
  static String? pendingInvitationCode;
  static void clearPendingCode() => pendingInvitationCode = null;
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _invitationCodeController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isLoading = false;
  bool _agreeToTerms = false;
  bool _showInvitationCode = false;

  final _auth = AuthService();

  // 鉁?浠呭湪 iOS 鏄剧ず Apple 鎸夐挳
  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    final code = widget.invitationCode;
    if (code != null && code.isNotEmpty) {
      _invitationCodeController.text = code;
      _showInvitationCode = true;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _invitationCodeController.dispose();
    super.dispose();
  }

  /// 缁熶竴澶勭悊锛氫繚瀛橀個璇风爜缁欏叏灞€鐩戝惉鍣紝骞跺湪宸茬櫥褰曟椂绔嬪嵆缁戝畾
  Future<void> _maybeBindInviteCode(String? code) async {
    if (code == null || code.trim().isEmpty) return;
    final normalized = code.trim().toUpperCase();

    // 鍏滃簳淇濆瓨锛氭棤璁烘槸鍚﹀凡鐧诲綍
    RegisterScreen.pendingInvitationCode = normalized;

    // 濡傛灉姝ゆ椂宸茬粡鏈変細璇濓紝灏辩洿鎺ヨ皟鐢?RPC 缁戝畾锛坰ubmitInviteCode 杩斿洖 void锛屼笉鑳藉綋琛ㄨ揪寮忎娇鐢級
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        await RewardService.submitInviteCode(normalized);
        // 缁戝畾璋冪敤瀹屾垚鍚庢竻绌哄厹搴曪紙RPC 鍐呴儴搴斾繚璇佸箓绛夛級
        RegisterScreen.clearPendingCode();
      } catch (_) {
        // 淇濈暀 pending锛屼氦缁欏叏灞€鐩戝惉鍣ㄥ湪鍚庣画 signedIn 鏃跺啀璇曚竴娆?
      }
    }
  }

  String? _pickCodeFromUI() {
    final fromRoute = widget.invitationCode?.trim().toUpperCase();
    if (fromRoute != null && fromRoute.isNotEmpty) return fromRoute;

    final fromField = _invitationCodeController.text.trim().toUpperCase();
    if (fromField.isNotEmpty) return fromField;

    return null;
  }

  Future<void> _register() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid || !_agreeToTerms) {
      if (!_agreeToTerms) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Please agree to Terms of Service and Privacy Policy'),
            backgroundColor: Colors.red[400],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.r)),
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      final code = _pickCodeFromUI();

      // 鍏堟妸閭€璇风爜鍐欏埌 pending锛岄伩鍏嶆敞鍐?浼氳瘽寤虹珛鐨勬椂闂村樊涓㈠け
      await _maybeBindInviteCode(code);

      await _auth.signUpWithEmailPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        fullName: _nameController.text.trim(),
      );

      // 鍐嶅皾璇曚竴娆＄珛鍗崇粦瀹氾紙杩欐椂閫氬父宸?signed in锛?
      await _maybeBindInviteCode(code);

      if (!mounted) return;
      _showSuccessDialog();
      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) Navigator.pop(context); // 鍏冲脊绐?
      // 鍏跺畠锛氬垱寤?profile / 娆㈣繋鍒?/ 瀵艰埅锛岀敱浣犵殑鍏ㄥ眬 Auth 鐩戝惉鍣ㄥ仛
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: Colors.red[400],
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 鉁?Google 娉ㄥ唽锛氭敼涓轰娇鐢?helper锛堜笌鐧诲綍椤典竴鑷达級
  Future<void> _googleRegister() async {
    setState(() => _isLoading = true);
    try {
      final code = _pickCodeFromUI();
      await _maybeBindInviteCode(code);

      await gauth.signInWithGoogle(context);

      await _maybeBindInviteCode(code);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Google 娉ㄥ唽澶辫触锛?e'),
          backgroundColor: Colors.red[400],
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _facebookRegister() async {
    setState(() => _isLoading = true);
    try {
      final code = _pickCodeFromUI();
      await _maybeBindInviteCode(code);

      await OAuthService.signInWithFacebook();

      await _maybeBindInviteCode(code);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Facebook 娉ㄥ唽澶辫触锛?e'),
          backgroundColor: Colors.red[400],
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 鉁?Apple 娉ㄥ唽锛氫笌鍏跺畠绀句氦閫昏緫涓€鑷达紝鏀寔閭€璇风爜鍏滃簳
  Future<void> _appleRegister() async {
    setState(() => _isLoading = true);
    try {
      final code = _pickCodeFromUI();
      await _maybeBindInviteCode(code);

      final ok = await AppleAuthService().signIn();
      if (!mounted) return;

      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Apple 鐧诲綍琚彇娑堟垨澶辫触')),
        );
      }

      await _maybeBindInviteCode(code);
      // 鎴愬姛鍚庣殑瀵艰埅/濂栧姳浠嶇敱浣犵殑鍏ㄥ眬 Auth 鐩戝惉鍣ㄥ鐞?
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Apple 娉ㄥ唽澶辫触锛?e'),
          backgroundColor: Colors.red[400],
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: EdgeInsets.all(24.r),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16.r),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: const Duration(milliseconds: 600),
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Container(
                      width: 60.r,
                      height: 60.r,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
                        ),
                      ),
                      child: Icon(Icons.check, color: Colors.white, size: 30.r),
                    ),
                  );
                },
              ),
              SizedBox(height: 16.h),
              Text('Registration Success!',
                  style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF2196F3))),
              SizedBox(height: 8.h),
              Text('Welcome to Swaply!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.sp, color: Colors.grey[600])),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Container(
          margin: EdgeInsets.all(8.r),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(10.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 6.r,
                offset: Offset(0, 2.h),
              )
            ],
          ),
          child: IconButton(
            icon: Icon(Icons.arrow_back_ios_rounded,
                color: Colors.black87, size: 18.r),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 16.h),
                Text('Create Account',
                    style: TextStyle(
                        fontSize: 24.sp,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                        letterSpacing: -0.5)),
                SizedBox(height: 6.h),
                Text('Join Swaply and start trading',
                    style: TextStyle(fontSize: 14.sp, color: Colors.grey[600])),
                SizedBox(height: 28.h),

                _input(
                  controller: _nameController,
                  label: 'Full Name *',
                  hint: 'Enter your full name',
                  icon: Icons.person_outline,
                  validator: (v) => (v == null || v.isEmpty)
                      ? 'Please enter your full name'
                      : null,
                ),
                SizedBox(height: 14.h),

                _input(
                  controller: _emailController,
                  label: 'Email Address *',
                  hint: 'Enter your email',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return 'Please enter your email';
                    }
                    if (!RegExp(r'^[\w\.-]+@[\w\.-]+\.\w{2,}$').hasMatch(v)) {
                      return 'Please enter a valid email';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 14.h),

                _input(
                  controller: _phoneController,
                  label: 'Phone Number',
                  hint: '+263 77 123 4567',
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  validator: (v) {
                    if (v != null && v.isNotEmpty && v.length < 10) {
                      return 'Please enter a valid phone number';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 14.h),

                _invitationCodeBox(),
                SizedBox(height: 14.h),

                _input(
                  controller: _passwordController,
                  label: 'Password *',
                  hint: 'Enter your password',
                  icon: Icons.lock_outline,
                  obscureText: !_isPasswordVisible,
                  suffixIcon: IconButton(
                    onPressed: () => setState(
                        () => _isPasswordVisible = !_isPasswordVisible),
                    icon: Icon(
                      _isPasswordVisible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18.r,
                      color: Colors.grey[500],
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return 'Please enter your password';
                    }
                    if (v.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 14.h),

                _input(
                  controller: _confirmPasswordController,
                  label: 'Confirm Password *',
                  hint: 'Confirm your password',
                  icon: Icons.lock_outline,
                  obscureText: !_isConfirmPasswordVisible,
                  suffixIcon: IconButton(
                    onPressed: () => setState(() =>
                        _isConfirmPasswordVisible = !_isConfirmPasswordVisible),
                    icon: Icon(
                      _isConfirmPasswordVisible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18.r,
                      color: Colors.grey[500],
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return 'Please confirm your password';
                    }
                    if (v != _passwordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16.h),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 18.r,
                      width: 18.r,
                      child: Checkbox(
                        value: _agreeToTerms,
                        onChanged: (v) =>
                            setState(() => _agreeToTerms = v ?? false),
                        activeColor: const Color(0xFF2196F3),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(3.r)),
                      ),
                    ),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(
                              fontSize: 12.sp, color: Colors.grey[700]),
                          children: const [
                            TextSpan(text: 'I agree to the '),
                            TextSpan(
                              text: 'Terms of Service',
                              style: TextStyle(
                                color: Color(0xFF2196F3),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(text: ' and '),
                            TextSpan(
                              text: 'Privacy Policy',
                              style: TextStyle(
                                color: Color(0xFF2196F3),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 20.h),

                // Sign Up
                SizedBox(
                  height: 48.h,
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _register,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2196F3),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r)),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 20.r,
                                height: 20.r,
                                child: const CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 10.w),
                              const Text('Creating Account...'),
                            ],
                          )
                        : const Text('Create Account'),
                  ),
                ),
                SizedBox(height: 18.h),

                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.grey[300])),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12.w),
                      child: Text('OR',
                          style: TextStyle(
                              color: Colors.grey[500], fontSize: 12.sp)),
                    ),
                    Expanded(child: Divider(color: Colors.grey[300])),
                  ],
                ),
                SizedBox(height: 18.h),

                Row(
                  children: [
                    Expanded(
                      child: _socialBtn(
                        'Google',
                        Colors.red[600]!,
                        Icons.g_mobiledata,
                        _googleRegister,
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: _socialBtn(
                        'Facebook',
                        Colors.blue[800]!,
                        Icons.facebook,
                        _facebookRegister,
                      ),
                    ),
                  ],
                ),

                // 鉁?Apple 瀹樻柟鎸夐挳锛堜粎 iOS 灞曠ず锛屾暣琛屽搴︼級
                if (_isIOS) ...[
                  SizedBox(height: 12.h),
                  SizedBox(
                    width: double.infinity,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AbsorbPointer(
                          absorbing: _isLoading,
                          child: SignInWithAppleButton(
                            onPressed: _appleRegister,
                            style: SignInWithAppleButtonStyle.black,
                            borderRadius:
                                const BorderRadius.all(Radius.circular(12)),
                          ),
                        ),
                        if (_isLoading)
                          const Positioned.fill(
                            child: IgnorePointer(
                              ignoring: true,
                              child: Center(
                                child: SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],

                SizedBox(height: 22.h),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("Already have an account? ",
                        style: TextStyle(
                            color: Colors.grey[600], fontSize: 12.sp)),
                    GestureDetector(
                      onTap: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LoginScreen(),
                        ),
                      ),
                      child: Text(
                        'Sign In',
                        style: TextStyle(
                          color: const Color(0xFF2196F3),
                          fontWeight: FontWeight.w700,
                          fontSize: 12.sp,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12.h),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===== UI =====
  Widget _invitationCodeBox() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8.r,
            offset: Offset(0, 2.h),
          )
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () =>
                setState(() => _showInvitationCode = !_showInvitationCode),
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(12.r),
              bottom: _showInvitationCode ? Radius.zero : Radius.circular(12.r),
            ),
            child: Padding(
              padding: EdgeInsets.all(12.r),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(6.r),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2196F3).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6.r),
                    ),
                    child: Icon(Icons.card_giftcard,
                        color: const Color(0xFF2196F3), size: 18.r),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Have an invitation code?',
                            style: TextStyle(
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87)),
                        Text("Get extra rewards with friend's invitation",
                            style: TextStyle(
                                fontSize: 11.sp, color: Colors.grey[600])),
                      ],
                    ),
                  ),
                  Icon(
                    _showInvitationCode ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey[600],
                    size: 20.r,
                  ),
                ],
              ),
            ),
          ),
          if (_showInvitationCode)
            Column(
              children: [
                Divider(height: 1, color: Colors.grey[200]),
                Padding(
                  padding: EdgeInsets.all(12.r),
                  child: TextFormField(
                    controller: _invitationCodeController,
                    style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2),
                    textAlign: TextAlign.center,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'Enter invitation code',
                      hintStyle:
                          TextStyle(fontSize: 12.sp, color: Colors.grey[400]),
                      prefixIcon: Icon(Icons.vpn_key,
                          size: 18.r, color: const Color(0xFF2196F3)),
                      filled: true,
                      fillColor: const Color(0xFF2196F3).withOpacity(0.05),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10.r),
                          borderSide: BorderSide.none),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12.w, vertical: 10.h),
                    ),
                    validator: (v) {
                      if (v != null && v.isNotEmpty && v.length < 6) {
                        return 'Invalid invitation code format';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _input({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return Container(
      decoration: BoxDecoration(boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 10.r,
          offset: Offset(0, 3.h),
        )
      ]),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        validator: validator,
        style: TextStyle(fontSize: 14.sp),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: TextStyle(color: Colors.grey[600], fontSize: 12.sp),
          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 12.sp),
          prefixIcon: Padding(
            padding: EdgeInsets.all(10.r),
            child: Icon(icon, color: const Color(0xFF2196F3), size: 18.r),
          ),
          suffixIcon: suffixIcon,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.r),
              borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.r),
              borderSide: BorderSide(color: Colors.grey[200]!, width: 1)),
          focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              borderSide: BorderSide(color: Color(0xFF2196F3), width: 1.5)),
          errorBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              borderSide: BorderSide(color: Colors.red, width: 1)),
          focusedErrorBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              borderSide: BorderSide(color: Colors.red, width: 1.5)),
          contentPadding:
              EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
        ),
      ),
    );
  }

  Widget _socialBtn(
      String text, Color color, IconData icon, Future<void> Function() onTap) {
    return SizedBox(
      height: 42.h,
      child: OutlinedButton(
        onPressed: _isLoading ? null : onTap,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.grey[200]!),
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18.r),
            SizedBox(width: 6.w),
            Flexible(
              child: Text(
                text,
                style: TextStyle(fontSize: 12.sp, color: Colors.grey[700]),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
