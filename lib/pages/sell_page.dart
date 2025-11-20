import 'package:flutter/material.dart';
import 'package:swaply/core/l10n/app_localizations.dart';
import 'package:swaply/pages/sell_form_page.dart';

class SellPage extends StatelessWidget {
  final bool isGuest;
  const SellPage({super.key, this.isGuest = false});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (isGuest) return Center(child: Text(l10n.loginToPost));
    return const SellFormPage();
  }
}
