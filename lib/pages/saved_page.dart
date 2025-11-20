import 'package:flutter/material.dart';

class SavedPage extends StatelessWidget {
  final bool isGuest;
  final VoidCallback? onNavigateToHome;

  const SavedPage({
    Key? key,
    this.isGuest = false,
    this.onNavigateToHome,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (isGuest) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bookmark_outline, size: 48),
            const SizedBox(height: 8),
            const Text('Please login to view Saved items'),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: onNavigateToHome,
              child: const Text('Go Home'),
            ),
          ],
        ),
      );
    }
    // 临时占位：后续 Step 3 会替换为真正的 Saved 三页签实现
    return const Center(child: Text('SavedPage (placeholder)'));
  }
}
