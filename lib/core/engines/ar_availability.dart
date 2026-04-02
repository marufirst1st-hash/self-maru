import 'package:flutter/services.dart';

/// ARCore 사용 가능 여부 체크
class ArAvailability {
  static const _channel = MethodChannel('com.floormeasure/ar_check');
  static bool? _cached;

  /// ARCore 사용 가능한지 확인
  /// - Google Play Services for AR 설치됨
  /// - 기기가 ARCore 지원
  static Future<bool> isAvailable() async {
    if (_cached != null) return _cached!;
    try {
      final result = await _channel.invokeMethod<bool>('isArCoreAvailable');
      _cached = result ?? false;
      return _cached!;
    } catch (_) {
      _cached = false;
      return false;
    }
  }
}
