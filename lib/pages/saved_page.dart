import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:swaply/core/l10n/app_localizations.dart';

class SavedPage extends StatelessWidget {
  final bool isGuest;
  final VoidCallback? onNavigateToHome;
  const SavedPage({super.key, this.isGuest = false, this.onNavigateToHome});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (isGuest) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.loginToSaveFavorites, textAlign: TextAlign.center),
            SizedBox(height: 12.h),
            ElevatedButton(onPressed: onNavigateToHome, child: Text(l10n.loginNow)),
          ],
        ),
      );
    }
    return const _SavedScaffoldPlaceholder();
  }
}

class _SavedScaffoldPlaceholder extends StatelessWidget {
  const _SavedScaffoldPlaceholder();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(child: Text('${l10n.saved} — TODO: migrate real UI')),
    );
  }
}
