import 'package:flutter/material.dart';
import 'package:swaply/core/l10n/app_localizations.dart';

class NotificationPage extends StatefulWidget {
  final VoidCallback onClearBadge;
  final bool isGuest;
  final ValueChanged<int>? onNotificationCountChanged;

  const NotificationPage({
    super.key,
    required this.onClearBadge,
    this.isGuest = false,
    this.onNotificationCountChanged,
  });

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onNotificationCountChanged?.call(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (widget.isGuest) {
      return Center(child: Text(l10n.loginToReceiveNotifications));
    }
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(child: Text('${l10n.notifications} — TODO: migrate real UI')),
    );
  }
}
