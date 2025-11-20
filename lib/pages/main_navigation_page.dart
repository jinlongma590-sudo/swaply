// lib/pages/main_navigation_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

// 你已有的 4 个页面 —— 路径保持和你工程一致
import 'package:swaply/pages/home_page.dart';
import 'package:swaply/pages/wishlist_page.dart';     // 你工程中叫 SavedPage 的话，改这里的 import + 类名
import 'package:swaply/pages/sell_form_page.dart';
import 'package:swaply/pages/profile_page.dart';

// 如果你有真正的通知页，请：
// 1) 把下面这个占位类删掉
// 2) import 你的通知页： import 'package:swaply/pages/notification_page.dart';
// 3) 把 _tabs 里的 NotificationsStubPage() 换成你的 NotificationPage()
class NotificationsStubPage extends StatelessWidget {
  const NotificationsStubPage({super.key});
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Text(
          'Notifications',
          style: TextStyle(fontSize: 16.sp),
        ),
      ),
    );
  }
}

class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _index = 0;

  late final List<Widget> _tabs = const [
    HomePage(),
    WishlistPage(),          // 如果你类名是 SavedPage，请改成 SavedPage()
    SellFormPage(),
    NotificationsStubPage(), // 如上所述，替换为你的 NotificationPage()
    ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),

      // ✅ 占位底栏：先用系统 BottomNavigationBar 保持可运行
      // ⚠️ 如果你已有“蓝色自定义底栏”，直接把这一块替换为你的组件，
      //     唯一要求：onTap: (i) => setState(()=> _index = i)
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        type: BottomNavigationBarType.fixed,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.favorite_border),
            label: 'Saved',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_box_outlined),
            label: 'Sell',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications_none),
            label: 'Alerts',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
