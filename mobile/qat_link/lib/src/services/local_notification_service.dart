import 'dart:io';

import 'package:flutter/services.dart';

class LocalNotificationService {
  const LocalNotificationService._();

  static const _channel = MethodChannel('qatlink/notifications');
  static bool _permissionRequested = false;

  static Future<void> requestPermission() async {
    if (!Platform.isAndroid || _permissionRequested) return;
    _permissionRequested = true;
    try {
      await _channel.invokeMethod<void>('requestPermission');
    } on Object {
      return;
    }
  }

  static Future<void> show({
    required String id,
    required String title,
    required String body,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('show', {
        'id': _stableId(id),
        'title': title,
        'body': body,
      });
    } on Object {
      return;
    }
  }

  static int _stableId(String value) {
    var hash = 0;
    for (final code in value.codeUnits) {
      hash = ((hash * 31) + code) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }
}
