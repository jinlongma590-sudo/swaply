// lib/router/root_nav.dart
import 'package:flutter/material.dart';

NavigatorState _rootNav(BuildContext ctx) =>
    Navigator.of(ctx, rootNavigator: true);

Future<T?> navPushNamed<T>(
    BuildContext ctx,
    String name, {
      Object? arguments,
    }) {
  return _rootNav(ctx).pushNamed<T>(name, arguments: arguments);
}

Future<T?> navReplaceAll<T>(
    BuildContext ctx,
    String name, {
      Object? arguments,
    }) {
  return _rootNav(ctx).pushNamedAndRemoveUntil<T>(
    name,
        (r) => false,
    arguments: arguments,
  );
}

Future<T?> navPush<T>(BuildContext ctx, Route<T> route) {
  return _rootNav(ctx).push<T>(route);
}

Future<bool> navMaybePop(BuildContext ctx) {
  return _rootNav(ctx).maybePop();
}
