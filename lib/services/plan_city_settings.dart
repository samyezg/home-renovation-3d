import '../models/plan.dart';
import 'city_tier_catalog.dart';
import 'repositories.dart';

/// 按「我的」默认城市创建空方案
Future<PlanDocument> createPlanWithSettings({String name = '我家方案'}) async {
  await CityTierCatalog.ensureLoaded();
  final s = await SettingsRepository().load();
  final cityRaw = (s['default_city_name'] as String?)?.trim();
  final city = (cityRaw == null || cityRaw.isEmpty) ? '成都' : cityRaw;
  final fallback = s['city_tier_default'] as String? ?? 'tier2';
  final hit = CityTierCatalog.resolve(city, fallbackTier: fallback);
  return PlanDocument.create(
    name: name,
    building: BuildingInfo(
      cityName: hit.matchedName.isEmpty ? city : hit.matchedName,
      cityTier: hit.tier,
      cityTierSource: 'auto',
    ),
  );
}

/// I19：模板/示例方案城市从「我的」设置注入（不写死成都）
Future<void> applyCityFromSettings(PlanDocument plan) async {
  await CityTierCatalog.ensureLoaded();
  final s = await SettingsRepository().load();
  final cityRaw = (s['default_city_name'] as String?)?.trim();
  final city = (cityRaw == null || cityRaw.isEmpty) ? '成都' : cityRaw;
  final fallback = s['city_tier_default'] as String? ?? 'tier2';
  final hit = CityTierCatalog.resolve(city, fallbackTier: fallback);
  plan.building.cityName = hit.matchedName.isEmpty ? city : hit.matchedName;
  plan.building.cityTier = hit.tier;
  plan.building.cityTierSource = 'auto';
}
