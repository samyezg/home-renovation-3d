import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/domain.dart';
import '../models/plan.dart';

class PlanRepository {
  Future<Directory> _dir() async {
    final root = await getApplicationDocumentsDirectory();
    final d = Directory('${root.path}/plans');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<List<PlanDocument>> listPlans() async {
    final d = await _dir();
    final files = d
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    final out = <PlanDocument>[];
    for (final f in files) {
      try {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        out.add(PlanDocument.fromJson(j));
      } catch (_) {}
    }
    out.sort((a, b) => b.meta.updatedAt.compareTo(a.meta.updatedAt));
    return out;
  }

  Future<void> save(PlanDocument plan) async {
    plan.touch();
    plan.rebuildWallsFromRooms();
    final d = await _dir();
    final f = File('${d.path}/${plan.meta.id}.json');
    await f.writeAsString(plan.encodePretty());
  }

  Future<PlanDocument?> load(String id) async {
    final d = await _dir();
    final f = File('${d.path}/$id.json');
    if (!await f.exists()) return null;
    final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    return PlanDocument.fromJson(j);
  }

  Future<void> delete(String id) async {
    final d = await _dir();
    final f = File('${d.path}/$id.json');
    if (await f.exists()) await f.delete();
  }

  Future<int> count() async => (await listPlans()).length;

  Future<int> approxBytes() async {
    final d = await _dir();
    var total = 0;
    for (final f in d.listSync().whereType<File>()) {
      if (f.path.endsWith('.json')) total += await f.length();
    }
    return total;
  }

  Future<void> deleteAll() async {
    final d = await _dir();
    for (final f in d.listSync().whereType<File>()) {
      if (f.path.endsWith('.json')) await f.delete();
    }
  }

  /// 全部方案摘要文本（便于分享/备份）
  Future<String> exportAllText() async {
    final list = await listPlans();
    final buf = StringBuffer('轻装家 · 本地方案导出\n')
      ..writeln('共 ${list.length} 个方案\n');
    if (list.isEmpty) {
      buf.writeln('（空）');
    } else {
      for (final p in list) {
        buf.writeln('· ${p.meta.name}');
        buf.writeln(
          '  ${p.building.areaBuildM2}㎡ · ${p.rooms.length} 空间 · ${p.building.cityName}',
        );
        buf.writeln('  id=${p.meta.id}');
        final warns = p.annotations.recognizeWarnings;
        if (warns.isNotEmpty) {
          buf.writeln(
            '  识图warning(${p.annotations.recognizeSource ?? "?"}): '
            '${warns.length} 条',
          );
          for (final w in warns.take(6)) {
            buf.writeln('    - $w');
          }
        }
      }
      buf.writeln('\n—— JSON 备份 ——\n');
      for (final p in list) {
        buf.writeln(p.encodePretty());
        buf.writeln('\n---\n');
      }
    }
    buf.writeln('仅供参考，数据保存在本机。');
    return buf.toString();
  }
}

class ChecklistRepository {
  Future<File> _file() async {
    final root = await getApplicationDocumentsDirectory();
    return File('${root.path}/checklist.json');
  }

  Future<List<ChecklistLine>> load() async {
    final f = await _file();
    if (!await f.exists()) return [];
    final list = jsonDecode(await f.readAsString()) as List;
    return list
        .map((e) => ChecklistLine.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveAll(List<ChecklistLine> items) async {
    final f = await _file();
    await f.writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        items.map((e) => e.toJson()).toList(),
      ),
    );
  }

  Future<void> add(ChecklistLine line) async {
    final items = await load();
    items.removeWhere((e) => e.id == line.id);
    items.add(line);
    await saveAll(items);
  }

  Future<void> remove(String id) async {
    final items = await load();
    items.removeWhere((e) => e.id == id);
    await saveAll(items);
  }

  Future<String> exportText() async {
    final items = await load();
    final buf = StringBuffer('轻装家 · 改造清单\n')
      ..writeln('（价格字段为空 · 仅供参考）\n');
    if (items.isEmpty) {
      buf.writeln('（空）');
    } else {
      for (final e in items) {
        final qty = e.qty <= 1 ? '' : ' ×${e.qty}';
        buf.writeln('· [${e.category}] ${e.title}$qty');
        if (e.specHint != null && e.specHint!.isNotEmpty) {
          buf.writeln('  规格提示：${e.specHint}');
        }
      }
    }
    buf.writeln('\n仅供参考，不替代专业设计与施工。');
    return buf.toString();
  }

  Future<int> count() async => (await load()).length;

  Future<int> approxBytes() async {
    final f = await _file();
    if (!await f.exists()) return 0;
    return f.length();
  }

  Future<void> clearAll() async {
    final f = await _file();
    if (await f.exists()) await f.delete();
  }
}

class SettingsRepository {
  Future<File> _file() async {
    final root = await getApplicationDocumentsDirectory();
    return File('${root.path}/settings.json');
  }

  Future<Map<String, dynamic>> load() async {
    final f = await _file();
    if (!await f.exists()) {
      return {
        'city_tier_default': 'tier2',
        'city_offset_enabled': true,
        'default_city_name': '成都',
        'wall_opacity': 0.35,
        'canvas_style_mode': 'simple',
        'view3d_style_mode': 'cartoon',
        'style_tone': 'warmWood',
      };
    }
    return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
  }

  Future<void> save(Map<String, dynamic> m) async {
    final f = await _file();
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(m));
  }
}

class ProgressRepository {
  Future<File> _file(String name) async {
    final root = await getApplicationDocumentsDirectory();
    return File('${root.path}/$name.json');
  }

  Future<Map<String, String>> loadStates(String name) async {
    final f = await _file(name);
    if (!await f.exists()) return {};
    final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    return j.map((k, v) => MapEntry(k, '$v'));
  }

  Future<void> saveStates(String name, Map<String, String> states) async {
    final f = await _file(name);
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(states));
  }
}
