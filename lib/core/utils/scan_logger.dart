import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// 테스트용 스캔 로그 기록
/// 센서 이벤트를 파일에 남김 → USB 연결 후 adb pull로 확인
class ScanLogger {
  static StringBuffer _buffer = StringBuffer();
  static DateTime? _startTime;

  static void start() {
    _buffer = StringBuffer();
    _startTime = DateTime.now();
    log('=== 스캔 시작 ===');
  }

  static void log(String msg) {
    final elapsed = _startTime != null
        ? DateTime.now().difference(_startTime!).inMilliseconds
        : 0;
    final line = '[${elapsed}ms] $msg';
    _buffer.writeln(line);
    // 콘솔에도 출력
    print('ScanLog: $line');
  }

  static void logAr(String event, {Map<String, dynamic>? data}) {
    log('AR: $event${data != null ? ' $data' : ''}');
  }

  static void logPdr(int steps, double x, double y) {
    log('PDR: steps=$steps pos=($x, $y)');
  }

  static void logFlash(String event, {double? diff}) {
    log('FLASH: $event${diff != null ? ' diff=$diff' : ''}');
  }

  static void logSonar(String event, {double? dist}) {
    log('SONAR: $event${dist != null ? ' dist=$dist' : ''}');
  }

  static void logWall(int count) {
    log('WALL: $count개 감지');
  }

  static void logCorner(int count, double area) {
    log('CORNER: $count개, area=${area.toStringAsFixed(2)}m²');
  }

  static void logCorrection(String source, int total) {
    log('CORRECTION: source=$source total=$total');
  }

  /// 로그를 파일로 저장
  static Future<String?> save() async {
    try {
      log('=== 스캔 종료 ===');
      final dir = await getExternalStorageDirectory();
      if (dir == null) return null;
      final file = File('${dir.path}/scan_log_${DateTime.now().millisecondsSinceEpoch}.txt');
      await file.writeAsString(_buffer.toString());
      return file.path;
    } catch (_) {
      return null;
    }
  }

  static String get content => _buffer.toString();
}
