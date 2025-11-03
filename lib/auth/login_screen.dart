// lib/pages/login_screen.dart - Updated Version (no internal navigation; single onAuthStateChange in main.dart)
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
// 保留：如需继续使用注册/找回密码页，请在别处触发导航，这里不再导航
import 'register_screen.dart';
import 'forgot_password_screen.dart';

// 仅保留 Supabase 直接调用，避免任何服务内隐藏导航（使用命名空间避免与 provider 混淆）
import 'package:supabase_flutter/supabase_flutter.dart' as sf;

// 统一的 OAuth 回调常量（与 Dashboard / iOS URL Types / AndroidManifest 对齐）
const String kAuthRedirectUri = 'cc.swaply.app://login-callback';

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

  // ✅ 防双击 / 防二次提交
  bool _busy = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ======== Email / Password 登录：只提交请求，不导航 ========
  Future<void> _loginEmailPassword() async {
    final isFormValid = _formKey.currentState?.validate() ?? false;
    if (!isFormValid || _busy) return;

    setState(() => _busy = true);
    try {
      await sf.Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      // ✅ 成功后不做任何导航/弹窗，交给 main.dart 的 onAuthStateChange(signedIn)
    } on sf.AuthException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Login failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ======== Google 登录：只提交请求，不导航 ========
  Future<void> _handleGoogleLogin() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      // 关键：只发起 OAuth，不在这里做“失败”吐司，等待回调处理
      await sf.Supabase.instance.client.auth.signInWithOAuth(
        sf.OAuthProvider.google,
        redirectTo: kAuthRedirectUri,                    // 你项目里的常量
        queryParams: const {'prompt': 'select_account'}, // 可保留
      );
      // 不要在这里导航、不提示“失败/成功”，交给 onAuthStateChange
    } on sf.AuthException catch (e) {
      final msg = e.message.toLowerCase();
      // 用户取消/关闭页面这类错误直接吞掉，避免“已登录却提示失败”
      if (msg.contains('cancel') ||
          msg.contains('canceled') ||
          msg.contains('popup_closed')) {
        // no-op
      } else {
        // 真异常再提示
        _showError('Google sign-in error: ${e.message}');
      }
    } catch (_) {
      // 极少数机型启动页面抛异常，但回调可能仍会到达；延迟 1s 检查是否真的没登录
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

  // ======== Facebook 登录（如需保留）：只提交请求，不导航 ========
  Future<void> _handleFacebookLogin() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await sf.Supabase.instance.client.auth.signInWithOAuth(
        sf.OAuthProvider.facebook,
        redirectTo: kAuthRedirectUri,
      );
    } on sf.AuthException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Facebook 登录启动失败，请稍后再试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ======== Apple 登录：只提交请求，不导航（iOS 生效） ========
  Future<void> _handleAppleLogin() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await sf.Supabase.instance.client.auth.signInWithOAuth(
        sf.OAuthProvider.apple,
        redirectTo: kAuthRedirectUri,
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10.r),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ✅ 不做任何自动关闭/返回；不展示会触发导航的按钮
      backgroundColor: Colors.grey[50],
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        // ❌ 去掉返回按钮里的 Navigator.pop
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
                  style: TextStyle(
                    fontSize: 14.sp,
                    color: Colors.grey[600],
                    letterSpacing: 0.2,
                  ),
                ),
                SizedBox(height: 32.h),

                // Email
                _buildTextField(
                  controller: _emailController,
                  label: 'Email Address',
                  hint: 'Enter your email',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your email';
                    }
                    if (!RegExp(r'^[\w\.-]+@[\w\.-]+\.\w{2,}$')
                        .hasMatch(value)) {
                      return 'Please enter a valid email';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16.h),

                // Password
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
                    onPressed: () {
                      setState(() => _isPasswordVisible = !_isPasswordVisible);
                    },
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your password';
                    }
                    if (value.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 12.h),

                // Remember row（不做导航）
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
                              onChanged: (value) {
                                setState(() => _rememberMe = value ?? false);
                              },
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
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: Colors.grey[700],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // ❌ 不再跳“找回密码页”，仅提示。若需跳转，请在别处统一处理。
                    Flexible(
                      child: GestureDetector(
                        onTap: () {
                          _showError('Forgot Password 暂不在此页导航，请在统一入口处理');
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

                // Sign In Button
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
                        color: const Color(0xFF2196F3).withValues(alpha: 0.3),
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
                            strokeWidth: 2.0,
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

                // OR
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

                // Social buttons
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

                // Apple（iOS 的情况下也可显示普通按钮，这里用文字按钮以避免额外依赖）
                SizedBox(height: 12.h),
                SizedBox(
                  width: double.infinity,
                  height: 42.h,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _handleAppleLogin,
                    icon: const Icon(Icons.apple),
                    label: const Text('Sign in with Apple'),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                  ),
                ),

                SizedBox(height: 24.h),

                // Sign up link（不导航，仅提示）
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Don't have an account? ",
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12.sp,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        _showError('注册跳转不在登录页处理，请在统一入口处理');
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
            color: Colors.black.withValues(alpha: 0.05),
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
          labelStyle: TextStyle(
            color: Colors.grey[600],
            fontSize: 12.sp,
          ),
          hintText: hint,
          hintStyle: TextStyle(
            color: Colors.grey[400],
            fontSize: 12.sp,
          ),
          prefixIcon: Container(
            padding: EdgeInsets.all(10.r),
            child: Icon(
              icon,
              color: const Color(0xFF2196F3),
              size: 18.r,
            ),
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
            borderSide: BorderSide(
              color: Colors.grey[200]!,
              width: 1.0.r,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: BorderSide(
              color: const Color(0xFF2196F3),
              width: 1.5.r,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: BorderSide(
              color: Colors.red[300]!,
              width: 1.0.r,
            ),
          ),
          focusedErrorBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(
              color: Colors.red,
              width: 1.5,
            ),
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: 16.w,
            vertical: 14.h,
          ),
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
            color: Colors.black.withValues(alpha: 0.05),
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
