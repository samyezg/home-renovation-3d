import 'dart:convert';

import 'package:flutter/services.dart';

/// 2025 新一线榜 → 轻装家四档本地对照（assets/config/city_tiers_2025.json）。
class CityTierHit {
  const CityTierHit({
    required this.tier,
    required this.label,
    required this.matchedName,
    required this.inTable,
  });

  final String tier;
  final String label;
  final String matchedName;

  /// false：未入披露名单，按三四线及以下建议。
  final bool inTable;
}

abstract final class CityTierCatalog {
  static Map<String, dynamic>? _root;
  static Map<String, Map<String, dynamic>> _cities = {};
  static List<String> _names = [];

  static const _asset = 'assets/config/city_tiers_2025.json';

  static Future<void> ensureLoaded() async {
    if (_root != null) return;
    final raw = await rootBundle.loadString(_asset);
    final j = jsonDecode(raw) as Map<String, dynamic>;
    _root = j;
    final cities = j['cities'] as Map<String, dynamic>? ?? {};
    _cities = {
      for (final e in cities.entries)
        e.key: Map<String, dynamic>.from(e.value as Map),
    };
    _names = _cities.keys.toList()..sort();
  }

  /// 去掉末尾「市」、空白；不做拼音。
  static String normalize(String raw) {
    var s = raw.trim();
    if (s.endsWith('市') && s.length > 1) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  static String tierLabel(String tier) => switch (tier) {
        'tier1' => '一线',
        'new_tier1' => '新一线',
        'tier3_plus' => '三四线及以下',
        _ => '二线',
      };

  /// 未命中时建议 [fallbackTier]（默认 tier3_plus）。
  static CityTierHit resolve(
    String cityName, {
    String fallbackTier = 'tier3_plus',
  }) {
    final key = normalize(cityName);
    if (key.isEmpty) {
      return CityTierHit(
        tier: fallbackTier,
        label: tierLabel(fallbackTier),
        matchedName: '',
        inTable: false,
      );
    }
    final hit = _cities[key];
    if (hit != null) {
      final tier = hit['tier'] as String? ?? fallbackTier;
      return CityTierHit(
        tier: tier,
        label: hit['label'] as String? ?? tierLabel(tier),
        matchedName: key,
        inTable: true,
      );
    }
    return CityTierHit(
      tier: fallbackTier,
      label: tierLabel(fallbackTier),
      matchedName: key,
      inTable: false,
    );
  }

  static List<String> suggest(String query, {int limit = 12}) {
    final q = normalize(query);
    if (q.isEmpty) return _names.take(limit).toList();
    final starts = <String>[];
    final contains = <String>[];
    for (final n in _names) {
      if (n.startsWith(q)) {
        starts.add(n);
      } else if (n.contains(q)) {
        contains.add(n);
      }
      if (starts.length >= limit) break;
    }
    return [...starts, ...contains].take(limit).toList();
  }

  static String hintFor(CityTierHit hit) {
    if (hit.inTable) {
      return '已按 2025 新一线榜建议：${hit.label}（可改）';
    }
    if (hit.matchedName.isEmpty) {
      return '填写城市名后可自动建议级别（可改）';
    }
    return '未在 2025 新一线披露名单，暂按${hit.label}（可改）';
  }
}
