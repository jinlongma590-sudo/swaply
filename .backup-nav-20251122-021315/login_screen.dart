// lib/auth/login_screen.dart
import 'package:swaply/services/oauth_entry.dart';
// ❌ 移除 SafeNavigator
// import 'package:swaply/router/safe_navigator.dart';
import 'package:swaply/router/root_nav.dart';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'register_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

// ✅ (1) State 增加生命周期监听
class _LoginScreenState extends State<LoginScreen> with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _rememberMe = false;
  bool _busy = false;

  // ✅ (2) initState 增加观察者注册 & 监听登录成功
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // ✅ B) 一次性监听：成功登录后只做收尾，不做导航（交给 AuthGate）
    Supabase.instance.client.auth.onAuthStateChange.firstWhere(
          (e) => e.event == AuthChangeEvent.signedIn,
    ).then((_) {
      // 收尾清理（停止 inFlight，确保按钮可点）
      OAuthEntry.finish();
      if (mounted) setState(() => _busy = false);

      // ⚠️ 不在这里导航！让你的 AuthGate/路由守卫基于 session 自动切到主界面/欢迎弹窗
      // 如果你没有 AuthGate，才在这里做一次性导航（按你项目路由名自行放开）：
      // rootNavKey.currentState?.pushNamedAndRemoveUntil('/main', (_) => false);
    });
  }

  // ✅ (3) dispose 增加观察者注销
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ✅ (4) 增加生命周期状态回调
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 回到前台：无论 OAuth 成功/取消，都先解锁 & 解除 busy
      OAuthEntry.finish(); // ✅ 强制清除 inFlight，防止按钮被全局锁住
      if (mounted) setState(() => _busy = false);

      // 兜底：把可能残留的外层路由/遮罩全部弹掉，确保界面可交互
      final nav = Navigator.of(context, rootNavigator: true);
      while (nav.canPop()) {
        nav.pop();
      }
    }
  }

  /// 统一 OAuth 入口（Google/Facebook/Apple 共用）
  /// ⛔ 已移除 scopes 参数；让 OAuthEntry 内部按 provider 自行决定 scope
  Future<void> _oauthSignIn(
      OAuthProvider provider, {
        Map<String, String>? queryParams,
      }) async {
    if (_busy) return;
    setState(() => _busy = true);

    // 只启动 OAuth，不做任何导航！
    await OAuthEntry.signIn(
      provider,
      queryParams: queryParams ?? const {'display': 'popup'},
    ).whenComplete(() {
      // WebView 被关闭（取消/返回）也要兜底清 busy
      if (mounted) setState(() => _busy = false);
    });
  }

  Future<void> _loginEmailPassword() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid || _busy || OAuthEntry.inFlight) return;

    setState(() => _busy = true);
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Login failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleGoogleLogin() async {
    if (_busy || OAuthEntry.inFlight) return;
    await _oauthSignIn(
      OAuthProvider.google,
      // 建议加 prompt 便于切换账号
      queryParams: const {'prompt': 'select_account'},
    );
  }

  Future<void> _handleFacebookLogin() async {
    if (_busy || OAuthEntry.inFlight) return;
    // ⛔ 不再传 scopes，完全交给 OAuthEntry 自动判断
    await _oauthSignIn(
      OAuthProvider.facebook,
      queryParams: const {'display': 'popup'},
    );
  }

  Future<void> _handleAppleLogin() async {
    if (_busy || OAuthEntry.inFlight) return;
    // ⛔ 不再传 scopes，完全交给 OAuthEntry 自动判断
    await _oauthSignIn(OAuthProvider.apple);
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
    final bool showApple = !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS);

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
                    if (v == null || v.isEmpty) {
                      return 'Please enter your email';
                    }
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
                    onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
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
                              onChanged: (v) => setState(() => _rememberMe = v ?? false),
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
                        onTap: () {
                          // ❗ 改为 rootNav 命名路由
                          navPush('/forgot-password');
                        },
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
                      onTap: _busy || OAuthEntry.inFlight ? null : _loginEmailPassword,
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
                      onTap: () {
                        // ❗ 不再用 Navigator.pushReplacement + MaterialPageRoute
                        navPush('/register');
                      },
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
        onPressed: _busy || OAuthEntry.inFlight ? null : _handleAppleLogin,
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
          onTap: (_busy || OAuthEntry.inFlight) ? null : onPressed,
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
