import 'package:flutter/material.dart';
import 'app.dart';
import 'services/analytics_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AnalyticsService.instance.initFromFlags();
  AnalyticsService.instance.logEvent('app_open');
  runApp(const QingZhuangJiaApp());
}
