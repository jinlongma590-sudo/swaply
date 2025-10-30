// lib/startup_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _isCheckingAuth = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    // 检查用户登录状态
    _checkAuthStatus();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 检查用户认证状态
  Future<void> _checkAuthStatus() async {
    try {
      // 等待至少2秒显示启动动画
      await Future.delayed(const Duration(seconds: 2));

      if (!mounted) return;

      final currentUser = Supabase.instance.client.auth.currentUser;

      if (currentUser != null) {
        // 用户已登录，跳转到主页
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/home',
              (route) => false,
        );
      } else {
        // 用户未登录，跳转到欢迎页
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/welcome',
              (route) => false,
        );
      }
    } catch (e) {
      // 发生错误时，默认跳转到欢迎页
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/welcome',
              (route) => false,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCheckingAuth = false);
      }
    }
  }

  /// 单个小圆点动画
  Widget _dot(double begin, double end) {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.75, end: 1.0)
          .chain(CurveTween(curve: Interval(begin, end, curve: Curves.easeInOut)))
          .animate(_controller),
      child: Container(
        width: 10,
        height: 10,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).padding;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF2196F3),
      body: Padding(
        padding: EdgeInsets.only(top: insets.top, bottom: insets.bottom),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Logo
              Container(
                width: size.width * 0.28,
                height: size.width * 0.28,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Text(
                  'Swaply',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // 加载动画
              if (_isCheckingAuth) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _dot(0.00, 0.50),
                    _dot(0.15, 0.65),
                    _dot(0.30, 0.80),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Checking login status...',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}