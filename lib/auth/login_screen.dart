// lib/auth/login_screen.dart
import 'package:swaply/services/oauth_entry.dart';
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

class _LoginScreenState extends State<LoginScreen> with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _rememberMe = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 登录成功 → finish()，不做导航（交给 AuthFlowObserver）
    Supabase.instance.client.auth.onAuthStateChange
        .firstWhere((e) => e.event == AuthChangeEvent.signedIn)
        .then((_) {
      if (mounted) setState(() => _busy = false);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // 外部浏览器 → 再回到 app 时
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      OAuthEntry.finish();
      if (mounted) setState(() => _busy = false);
    }
  }

  // Google / Facebook / Apple 通用入口
  Future<void> _oauthSignIn(
      OAuthProvider provider, {
        Map<String, String>? queryParams,
      }) async {
    if (_busy) return;
    setState(() => _busy = true);

    await OAuthEntry.signIn(
      provider,
      queryParams: queryParams,
    ).whenComplete(() {
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
      queryParams: const {'prompt': 'select_account'},
    );
  }

  Future<void> _handleFacebookLogin() async {
    if (_busy || OAuthEntry.inFlight) return;
    await _oauthSignIn(
      OAuthProvider.facebook,
      queryParams: const {'display': 'popup'},
    );
  }

  Future<void> _handleAppleLogin() async {
    if (_busy || OAuthEntry.inFlight) return;
    await _oauthSignIn(OAuthProvider.apple);
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red[400],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool showApple =
        !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS);

    // UI 保持你原来的，不动。
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
                  ),
                ),
                SizedBox(height: 6.h),
                Text(
                  'Sign in to continue to Swaply',
                  style:
                  TextStyle(fontSize: 14.sp, color: Colors.grey[600]),
                ),

                SizedBox(height: 32.h),

                // email field
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

                // password field
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
                    ),
                    onPressed: () => setState(
                            () => _isPasswordVisible = !_isPasswordVisible),
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
                    Row(
                      children: [
                        Checkbox(
                          value: _rememberMe,
                          onChanged: (v) =>
                              setState(() => _rememberMe = v ?? false),
                        ),
                        Text(
                          'Remember me',
                          style: TextStyle(
                              fontSize: 12.sp, color: Colors.grey[700]),
                        ),
                      ],
                    ),

                    GestureDetector(
                      onTap: () => navPush('/forgot-password'),
                      child: Text(
                        'Forgot Password?',
                        style: TextStyle(
                          color: const Color(0xFF2196F3),
                          fontWeight: FontWeight.w600,
                          fontSize: 12.sp,
                        ),
                      ),
                    ),
                  ],
                ),

                SizedBox(height: 24.h),

                // sign in button
                Container(
                  width: double.infinity,
                  height: 48.h,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2196F3), Color(0xFF1E88E5)],
                    ),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: InkWell(
                    onTap:
                    _busy || OAuthEntry.inFlight ? null : _loginEmailPassword,
                    child: Center(
                      child: _busy
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(
                        'Sign In',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),

                SizedBox(height: 20.h),

                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.grey[300])),
                    Text(' OR ', style: TextStyle(color: Colors.grey[500])),
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

                if (showApple) SizedBox(height: 12.h),

                if (showApple)
                  _appleSignInButton(),

                SizedBox(height: 24.h),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Don't have an account? ",
                      style:
                      TextStyle(color: Colors.grey[600], fontSize: 12.sp),
                    ),
                    GestureDetector(
                      onTap: () => navPush('/register'),
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

  // 以下 UI helpers 保留你原来的
  Widget _appleSignInButton() {
    return SizedBox(
      width: double.infinity,
      height: 44.h,
      child: ElevatedButton.icon(
        onPressed: _busy || OAuthEntry.inFlight ? null : _handleAppleLogin,
        icon: const Icon(Icons.apple),
        label: const Text('Sign in with Apple'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
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
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: const Color(0xFF2196F3)),
        suffixIcon: suffixIcon,
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
      child: ElevatedButton.icon(
        onPressed: (_busy || OAuthEntry.inFlight) ? null : onPressed,
        icon: Icon(icon, color: color),
        label: Text(text),
      ),
    );
  }
}
