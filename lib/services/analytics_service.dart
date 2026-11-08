import 'package:flutter/services.dart';

/// 埋点开关：默认关闭（P2 / T17）。开启前须更新隐私政策并征得同意。
class AnalyticsService {
  AnalyticsService._();
  static final instance = AnalyticsService._();

  bool _enabled = false;
  bool get enabled => _enabled;

  Future<void> initFromFlags() async {
    try {
      final raw = await rootBundle.loadString('assets/config/feature_flags.json');
      _enabled = raw.contains('"analytics_enabled": true');
    } catch (_) {
      _enabled = false;
    }
  }

  void logEvent(String name, [Map<String, Object?>? params]) {
    if (!_enabled) return;
    // 预留：接入正式 SDK 时在此上报。当前 no-op。
    assert(() {
      // ignore: avoid_print
      print('[analytics-off-or-stub] $name $params');
      return true;
    }());
  }
}
