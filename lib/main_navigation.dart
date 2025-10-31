// lib/main_navigation.dart
import 'package:flutter/material.dart';
import 'package:swaply/pages/home_page.dart' as swaply;

/// 旧壳：仅为兼容旧引用；新代码不要再用该类。
@Deprecated('Use MainNavigationPage from main.dart')
class MainNavigation extends StatelessWidget {
  const MainNavigation({super.key});

  @override
  Widget build(BuildContext context) {
    // HomePage 本身没有 isGuest 参数，不要传！
    return const swaply.HomePage();
  }
}
