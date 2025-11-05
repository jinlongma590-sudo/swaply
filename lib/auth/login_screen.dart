// lib/auth/login_screen.dart - iOS 定向回调修复版（直连 Supabase）

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode; // ✅ 用于 authScreenLaunchMode

// 如需注册/找回密码页，请在别处跳转；这里不做任何路由
import 'register_screen.dart';
import 'forgot_password_screen.dart';

import 'package:supabase_flutter/supabase_flutter.dart' as sf;

// 与 supabase_flutter 官方默认回调保持一致（iOS 必须携带这个或你的自定义 Scheme）
const String _kIOSRedirect = 'io.supabase.flutter://callback';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _rememberMe = false;
  bool _busy = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // 统一的 OAuth 入口：仅 iOS 显式传 redirectTo，其它平台走默认
  Future<void> _oauthSignIn(
      sf.OAuthProvider provider, {
        String? scopes,
        Map<String, String>? queryParams,
      }) async {
    await sf.Supabase.instance.client.auth.signInWithOAuth(
      provider,
      redirectTo: Platform.isIOS ? _kIOSRedirect : null,
      authScreenLaunchMode: LaunchMode.externalApplication, // ✅ 强制外部浏览器
      scopes: scopes,
      queryParams: queryParams,
    );
  }

  Future<void> _loginEmailPassword() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid || _busy) return;

    setState(() => _busy = true);
    try {
      await sf.Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      // 交给全局 onAuthStateChange 处理路由
    } on sf.AuthException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Login failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleGoogleLogin() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _oauthSignIn(
        sf.OAuthProvider.google,
        // 避免自动选中历史账号
        queryParams: const {'prompt': 'select_account'},
        // 可选：scopes: 'email profile',
      );
    } on sf.AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('cancel') ||
          msg.contains('canceled') ||
          msg.contains('popup_closed')) {
        // 用户手动关闭，不提示
      } else {
        _showError('Google sign-in error: ${e.message}');
      }
    } catch (_) {
      Future.delayed(const Duration(seconds: 1), () {
        final user = sf.Supabase.instance.client.auth.currentUser;
        if (mounted && user == null) {
          _showError('Failed to start Google sign-in. Please try again.');
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleFacebookLogin() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _oauthSignIn(
        sf.OAuthProvider.facebook,
        // 可选：scopes: 'email public_profile',
      );
    } on sf.AuthException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Facebook 登录启动失败，请稍后再试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleAppleLogin() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _oauthSignIn(
        sf.OAuthProvider.apple,
        // Apple 推荐 scopes: name email（首次授权才会返回姓名）
        scopes: 'name email',
      );
    } on sf.AuthException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Apple 登录启动失败，请稍后再试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red[400],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool showApple = !kIsWeb && Platform.isIOS;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const SizedBox.shrink(),
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
                Text(
                  'Welcome Back!',
                  style: TextStyle(
                    fontSize: 24.sp,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                    letterSpacing: -0.5,
                  ),
                ),
                SizedBox(height: 6.h),
                Text(
                  'Sign in to continue to Swaply',
                  style: TextStyle(fontSize: 14.sp, color: Colors.grey[600]),
                ),
                SizedBox(height: 32.h),

                _buildTextField(
                  controller: _emailController,
                  label: 'Email Address',
                  hint: 'Enter your email',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Please enter your email';
                    if (!RegExp(r'^[\w\.-]+@[\w\.-]+\.\w{2,}$').hasMatch(v)) {
                      return 'Please enter a valid email';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16.h),

                _buildTextField(
                  controller: _passwordController,
                  label: 'Password',
                  hint: 'Enter your password',
                  icon: Icons.lock_outline,
                  obscureText: !_isPasswordVisible,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isPasswordVisible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: Colors.grey[500],
                      size: 18.r,
                    ),
                    onPressed: () =>
                        setState(() => _isPasswordVisible = !_isPasswordVisible),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Please enter your password';
                    if (v.length < 6) return 'Password must be at least 6 characters';
                    return null;
                  },
                ),
                SizedBox(height: 12.h),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Row(
                        children: [
                          SizedBox(
                            height: 18.r,
                            width: 18.r,
                            child: Checkbox(
                              value: _rememberMe,
                              onChanged: (v) =>
                                  setState(() => _rememberMe = v ?? false),
                              activeColor: const Color(0xFF2196F3),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(3.r),
                              ),
                            ),
                          ),
                          SizedBox(width: 6.w),
                          Flexible(
                            child: Text(
                              'Remember me',
                              style: TextStyle(fontSize: 12.sp, color: Colors.grey[700]),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: GestureDetector(
                        onTap: () => _showError('Forgot Password 统一入口处理'),
                        child: Text(
                          'Forgot Password?',
                          style: TextStyle(
                            color: const Color(0xFF2196F3),
                            fontWeight: FontWeight.w600,
                            fontSize: 12.sp,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 24.h),

                Container(
                  width: double.infinity,
                  height: 48.h,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2196F3), Color(0xFF1E88E5)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(12.r),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2196F3).withOpacity(0.3),
                        blurRadius: 10.r,
                        offset: Offset(0, 6.h),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _busy ? null : _loginEmailPassword,
                      borderRadius: BorderRadius.circular(12.r),
                      child: Center(
                        child: _busy
                            ? SizedBox(
                          width: 20.r,
                          height: 20.r,
                          child: const CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                            : Text(
                          'Sign In',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 20.h),

                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.grey[300])),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12.w),
                      child: Text(
                        'OR',
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: Colors.grey[300])),
                  ],
                ),
                SizedBox(height: 20.h),

                Row(
                  children: [
                    Expanded(
                      child: _socialLoginButton(
                        'Google',
                        Colors.red[600]!,
                        Icons.g_mobiledata,
                        _handleGoogleLogin,
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: _socialLoginButton(
                        'Facebook',
                        Colors.blue[800]!,
                        Icons.facebook,
                        _handleFacebookLogin,
                      ),
                    ),
                  ],
                ),

                SizedBox(height: 12.h),
                if (showApple) _appleSignInButton(),

                SizedBox(height: 24.h),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Don't have an account? ",
                      style: TextStyle(color: Colors.grey[600], fontSize: 12.sp),
                    ),
                    GestureDetector(
                      onTap: () => _showError('注册跳转不在登录页处理'),
                      child: Text(
                        'Sign Up',
                        style: TextStyle(
                          color: const Color(0xFF2196F3),
                          fontWeight: FontWeight.w700,
                          fontSize: 12.sp,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16.h),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- UI helpers ---

  Widget _appleSignInButton() {
    return SizedBox(
      width: double.infinity,
      height: 44.h,
      child: ElevatedButton.icon(
        onPressed: _busy ? null : _handleAppleLogin,
        icon: const Icon(Icons.apple, color: Colors.white),
        label: const Text('Sign in with Apple', overflow: TextOverflow.ellipsis),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
          textStyle: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildTextField({
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
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10.r,
            offset: Offset(0, 3.h),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        style: TextStyle(fontSize: 14.sp),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: TextStyle(color: Colors.grey[600], fontSize: 12.sp),
          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 12.sp),
          prefixIcon: Container(
            padding: EdgeInsets.all(10.r),
            child: Icon(icon, color: const Color(0xFF2196F3), size: 18.r),
          ),
          suffixIcon: suffixIcon,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: BorderSide(color: Colors.grey[200]!, width: 1.0),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Color(0xFF2196F3), width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: BorderSide(color: Colors.red[300]!, width: 1.0),
          ),
          focusedErrorBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Colors.red, width: 1.5),
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        ),
        validator: validator,
      ),
    );
  }

  Widget _socialLoginButton(
      String text,
      Color color,
      IconData icon,
      VoidCallback onPressed,
      ) {
    return Container(
      height: 42.h,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey[200]!),
        borderRadius: BorderRadius.circular(10.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8.r,
            offset: Offset(0, 2.h),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _busy ? null : onPressed,
          borderRadius: BorderRadius.circular(10.r),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 18.r),
              SizedBox(width: 6.w),
              Flexible(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
