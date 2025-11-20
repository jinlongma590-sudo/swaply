// lib/router/root_nav.dart
import 'package:flutter/widgets.dart';

final GlobalKey<NavigatorState> rootNavKey = GlobalKey<NavigatorState>();

Future<T?> navPush<T extends Object?>(
    String routeName, {
      Object? arguments,
    }) {
  final nav = rootNavKey.currentState;
  if (nav == null) return Future<T?>.value(null);
  return nav.pushNamed<T>(routeName, arguments: arguments);
}

Future<T?> navReplaceAll<T extends Object?>(
    String routeName, {
      Object? arguments,
    }) {
  final nav = rootNavKey.currentState;
  if (nav == null) return Future<T?>.value(null);
  return nav.pushNamedAndRemoveUntil<T>(
    routeName,
        (r) => false,
    arguments: arguments,
  );
}

Future<bool> navMaybePop<T extends Object?>([T? result]) {
  final nav = rootNavKey.currentState;
  if (nav == null) return Future<bool>.value(false);
  return nav.maybePop(result);
}
