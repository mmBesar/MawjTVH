import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/tvh_client.dart';

/// Runs a server action and tells the person how it went. The server decides
/// whether the account may do it, so a refusal is explained, not hidden.
Future<bool> runServerAction(
  BuildContext context, {
  required Future<void> Function() action,
  required String success,
  String? forbidden,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(success)));
    return true;
  } on TvhException catch (error) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(error.isForbidden && forbidden != null ? forbidden : error.message),
        ),
      );
  } catch (error) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$error')));
  }
  return false;
}
