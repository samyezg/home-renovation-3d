import '../core/constants.dart';
import '../data/diy_catalog.dart';
import '../models/domain.dart';
import '../models/plan.dart';

/// P0 + P1 诊断；排序遵循 R012：安全 > 收纳 > 显大 > 颜值。
class DiagnosisEngine {
  DiagnosisEngine({this.cityOffsetEnabled = true});

  final bool cityOffsetEnabled;

  static List<DiagnosisBlocker> blockers(PlanDocument plan) {
    final out = <DiagnosisBlocker>[];
    if (plan.building.areaBuildM2 <= 0) {
      out.add(const DiagnosisBlocker(
        code: 'AREA_REQUIRED',
        message: '建筑面积（需大于 0）',
      ));
    }
    var doorTypeMissing = false;
    for (final d in plan.doors) {
      if (d.positionType != 'O' && d.positionType != 'I' && d.positionType != 'II') {
        doorTypeMissing = true;
        break;
      }
    }
    if (doorTypeMissing) {
      out.add(const DiagnosisBlocker(
        code: 'DOOR_POSITION_TYPE',
        message: '门洞位置类型（O / I / II）',
      ));
    }
    if (plan.rooms.isEmpty) {
      out.add(const DiagnosisBlocker(
        code: 'ROOMS_EMPTY',
        message: '房间（请在户型画布绘制，或载入示例）',
      ));
    }
    return out;
  }

  DiagnosisReport run(PlanDocument plan) {
    final b = plan.building;
    final den = b.roomCount + b.bathroomCount;
    final divisor = den <= 0 ? 0.0 : b.areaBuildM2 / den;
    final offset = cityOffsetEnabled ? _tierOffset(b.cityTier) : 0.0;
    final size = _sizeLabel(divisor, offset);

    final advices = <DiagAdvice>[];
    _r001b(plan, advices);
    _r002(plan, advices);
    _r003(plan, advices);
    _r004(plan, advices);
    _r005(plan, advices);
    _r006(plan, advices);
    _r007(plan, advices);
    _r008(plan, advices);
    _r009(plan, advices);
    _r010(plan, advices);
    _r011(plan, advices);

    // R012：按栈排序后取前 3，并写可解释文案
    advices.sort(_byStackThenPriority);
    final top = advices.take(3).toList();
    final rankExplain = <String>[
      '排序规则（R012）：安全 > 收纳 > 显大 > 颜值；同档再按规则优先级。',
      for (var i = 0; i < top.length; i++)
        '${i + 1}. [${top[i].stackLabel}] ${top[i].ruleId} · ${top[i].rankReason.isEmpty ? top[i].title : top[i].rankReason}',
    ];

    final iiCount = plan.doors.where((d) => d.positionType == 'II').length;
    final doorTotal = plan.doors.isEmpty ? 0 : plan.doors.length;
    final storageMissing =
        plan.rooms.where((r) => !r.hasStorageZone && r.type != 'bath').length;

    final metrics = <DiagMetric>[
      DiagMetric(
        id: 'r001',
        title: '空间显大指数',
        value: size,
        sub: '越大越显宽敞 · ${divisor.toStringAsFixed(1)}',
      ),
      DiagMetric(
        id: 'r002',
        title: '走道',
        value: doorTotal == 0 ? '待标' : '$iiCount/$doorTotal II',
        sub: '门洞 O/I/II',
      ),
      DiagMetric(
        id: 'r003',
        title: '收纳',
        value: storageMissing == 0 ? '均布' : '缺$storageMissing',
        sub: '目标 ≥12%',
      ),
      DiagMetric(
        id: 'r009',
        title: '视距',
        value: plan.annotations.redRulerCm == null
            ? '—'
            : plan.annotations.redRulerCm!.toStringAsFixed(0),
        sub: '面宽视距 cm',
      ),
    ];

    final tierName = _tierName(b.cityTier);
    final tight = size == 'XS' || size == 'S';
    final summaryTitle = tight ? '整体偏紧凑，建议先看收纳与门位。' : '整体大致适中，可按优先建议微调。';
    final summaryBody =
        '空间显大指数 ≈ ${divisor.toStringAsFixed(1)}（$size 码）。已按$tierName标准估算，仅供参考。'
        '${offset != 0 ? '（城市偏移 ${offset > 0 ? '+' : ''}${offset.toStringAsFixed(0)}）' : ''}';

    final highlights = _buildHighlights(
      size: size,
      tight: tight,
      storageMissing: storageMissing,
      iiCount: iiCount,
      doorTotal: doorTotal,
      top: top,
      storageRatio: b.storageRatioSurvey,
    );

    return DiagnosisReport(
      summaryTitle: summaryTitle,
      summaryBody: summaryBody,
      metrics: metrics,
      advices: top,
      divisor: divisor,
      sizeLabel: size,
      cityOffsetApplied: offset,
      rankExplain: rankExplain,
      allAdviceCount: advices.length,
      highlights: highlights,
    );
  }

  List<String> _buildHighlights({
    required String size,
    required bool tight,
    required int storageMissing,
    required int iiCount,
    required int doorTotal,
    required List<DiagAdvice> top,
    required double? storageRatio,
  }) {
    final out = <String>[];
    if (tight) {
      out.add('户型偏紧凑（$size 码），可用浅色软装与镜面让空间更显宽敞。');
    } else {
      out.add('空间尺度大致适中（$size 码），可按优先建议微调细节。');
    }
    if (storageMissing > 0) {
      out.add('有 $storageMissing 个空间尚未标记收纳，建议优先补就近柜体或门后收纳。');
    } else if (storageRatio != null && storageRatio < AppConstants.storageRatioTarget) {
      out.add(
        '收纳占比自估约 ${(storageRatio * 100).toStringAsFixed(0)}%，建议提到约 12%。',
      );
    } else {
      out.add('收纳分布看起来较均衡，可继续保持通高/集成思路。');
    }
    if (doorTotal == 0) {
      out.add('尚未标注门洞，补齐后可更准确判断走道是否交叉。');
    } else if (iiCount > 0) {
      out.add('有 $iiCount 处门洞偏居中，易形成交叉走道，改门位请找专业评估。');
    } else {
      out.add('门洞位置整体较稳妥，走道干扰风险不高。');
    }
    for (final a in top) {
      if (out.length >= 5) break;
      final line = a.title.trim();
      if (line.isEmpty) continue;
      if (out.any((h) => h.contains(line) || line.contains(h))) continue;
      out.add(line);
    }
    return out.take(5).toList();
  }

  int _stackRank(String label) => switch (label) {
        '安全' => 0,
        '收纳' => 1,
        '显大' => 2,
        '颜值' => 3,
        _ => 4,
      };

  int _byStackThenPriority(DiagAdvice a, DiagAdvice b) {
    final s = _stackRank(a.stackLabel).compareTo(_stackRank(b.stackLabel));
    if (s != 0) return s;
    return a.priority.compareTo(b.priority);
  }

  String _stackFor(String typeId, String diyLevel) {
    if (diyLevel == 'L3' ||
        typeId == 'door_move' ||
        typeId == 'wall_remove' ||
        typeId == 'electrical' ||
        typeId == 'plumbing_gas' ||
        typeId == 'load_bearing') {
      return '安全';
    }
    if (typeId.contains('cabinet') ||
        typeId.contains('storage') ||
        typeId == 'shelf_wall' ||
        typeId == 'entry_stool' ||
        typeId == 'mirror_cabinet') {
      return '收纳';
    }
    if (typeId == 'soft_textile' || typeId.contains('plant')) {
      return '显大';
    }
    return '颜值';
  }

  DiagAdvice _advice({
    required String ruleId,
    required String typeId,
    required String diyLevel,
    required String title,
    required String reason,
    int priority = 50,
    int? cabinetDepthCm,
    String? templateId,
    String rankReason = '',
  }) {
    final stack = _stackFor(typeId, diyLevel);
    return DiagAdvice(
      ruleId: ruleId,
      typeId: typeId,
      diyLevel: diyLevel,
      title: title,
      reason: reason,
      priority: priority,
      cabinetDepthCm: cabinetDepthCm,
      templateId: templateId,
      stackLabel: stack,
      rankReason: rankReason.isEmpty ? '属「$stack」栈' : rankReason,
    );
  }

  double _tierOffset(String tier) => switch (tier) {
        'tier1' || 'new_tier1' => -2.0,
        'tier3_plus' => 2.0,
        _ => 0.0,
      };

  String _tierName(String tier) => switch (tier) {
        'tier1' => '一线',
        'new_tier1' => '新一线',
        'tier3_plus' => '三四线',
        _ => '二线',
      };

  String _sizeLabel(double d, double offset) {
    if (d <= 18 + offset) return 'XS';
    if (d <= 20 + offset) return 'S';
    if (d <= 22 + offset) return 'M';
    if (d <= 25 + offset) return 'L';
    return 'XL';
  }

  void _r001b(PlanDocument plan, List<DiagAdvice> out) {
    final stage = plan.building.familyStage;
    if (stage == 'parenting' || stage == 'elderly' || stage == 'empty_nest') {
      out.add(_advice(
        ruleId: 'R001b',
        typeId: 'storage_box',
        diyLevel: 'L1',
        title: '按家庭阶段做有限改善',
        reason: '当前阶段更依赖收纳与通行便利，建议先完成就近收纳与安全自查（可选）。',
        templateId: 'T-L1-BOX-01',
        priority: 40,
        rankReason: '生命周期提示 · 收纳栈',
      ));
    }
  }

  void _r002(PlanDocument plan, List<DiagAdvice> out) {
    final ii = plan.doors.where((d) => d.positionType == 'II').toList();
    if (ii.isEmpty) return;
    out.add(_advice(
      ruleId: 'R002',
      typeId: 'door_move',
      diyLevel: 'L3',
      title: '门洞偏居中（II 型）',
      reason: 'II 型门洞易形成交叉走道。若考虑改门位，涉及结构，仅提示找专业。',
      templateId: 'T-L3-DOOR-01',
      priority: 10,
      rankReason: '安全栈优先 · 改门 L3',
    ));
  }

  void _r003(PlanDocument plan, List<DiagAdvice> out) {
    final missing = plan.rooms
        .where((r) => !r.hasStorageZone && !_skipStorage(r.type))
        .toList();
    if (missing.isEmpty) return;
    final name = missing.first.name;
    out.add(_advice(
      ruleId: 'R003',
      typeId: 'cabinet_thin',
      diyLevel: 'L2',
      title: '补$name就近收纳',
      reason: '收纳均布：该空间尚无收纳区标记，可优先薄柜/门后收纳。',
      templateId: 'T-L2-CAB-30',
      cabinetDepthCm: 30,
      priority: 20,
      rankReason: '收纳均布缺失',
    ));
  }

  bool _skipStorage(String type) => type == 'bath' || type == 'balcony';

  void _r004(PlanDocument plan, List<DiagAdvice> out) {
    final ratio = plan.building.storageRatioSurvey;
    final missing = plan.rooms.where((r) => !r.hasStorageZone).length;
    final ok = ratio != null
        ? ratio >= AppConstants.storageRatioTarget
        : missing == 0;
    if (ok) return;
    out.add(_advice(
      ruleId: 'R004',
      typeId: 'cabinet_wardrobe',
      diyLevel: 'L2',
      title: '收纳占比建议提到约 12%',
      reason: ratio == null
          ? '尚未填写收纳占比，且存在无收纳空间；可用柜体提升投影面积。'
          : '当前自估约 ${(ratio * 100).toStringAsFixed(0)}%，低于 12% 目标。',
      templateId: 'T-L2-CAB-60',
      cabinetDepthCm: 60,
      priority: 25,
      rankReason: '收纳占比未达标',
    ));
  }

  void _r005(PlanDocument plan, List<DiagAdvice> out) {
    if (plan.building.storageIntegrated) return;
    out.add(_advice(
      ruleId: 'R005',
      typeId: 'cabinet_wardrobe',
      diyLevel: 'L2',
      title: '零散柜改为通高/集成',
      reason: '立体集成：优先通高柜减少零散占地。',
      templateId: 'T-L2-CAB-60',
      cabinetDepthCm: 60,
      priority: 35,
      rankReason: '收纳集成',
    ));
  }

  void _r006(PlanDocument plan, List<DiagAdvice> out) {
    if (plan.building.displayRatioOk) return;
    out.add(_advice(
      ruleId: 'R006',
      typeId: 'storage_box',
      diyLevel: 'L1',
      title: '开放展示区少留多收',
      reason: '开放格大约留两成作展示，其余收进盒或带门柜，空间更清爽。',
      templateId: 'T-L1-BOX-01',
      priority: 30,
      rankReason: '收纳 · 少留展示多收纳',
    ));
  }

  void _r007(PlanDocument plan, List<DiagAdvice> out) {
    for (final r in plan.rooms) {
      final minW = AppConstants.minWidthCm[r.type];
      if (minW == null) continue;
      if (r.widthCm + 0.5 >= minW) continue;
      out.add(_advice(
        ruleId: 'R007',
        typeId: 'soft_textile',
        diyLevel: 'L1',
        title: '${r.name}面宽偏紧',
        reason:
            '当前面宽约 ${r.widthCm.toStringAsFixed(0)}cm，建议参考 ≥${minW.toStringAsFixed(0)}cm。可用浅色软装弱化压抑感；改结构请专业。',
        templateId: 'T-L1-TEXTILE-01',
        priority: 28,
        rankReason: '显大 · 面宽不足',
      ));
      break;
    }
  }

  void _r008(PlanDocument plan, List<DiagAdvice> out) {
    for (final r in plan.rooms) {
      final minW = AppConstants.minWidthCm[r.type];
      if (minW == null) continue;
      final surplus = r.widthCm - minW;
      if (surplus < 15) continue;
      final depth = _pickDepth(surplus);
      out.add(_advice(
        ruleId: 'R008',
        typeId: depth >= 60 ? 'cabinet_wardrobe' : 'cabinet_thin',
        diyLevel: 'L2',
        title: '${r.name}可插入 ${depth}cm 内存条',
        reason:
            '富余面宽约 ${surplus.toStringAsFixed(0)}cm，建议贴墙柜深 ${depth}cm（可进 3D 验证）。',
        templateId: DiyCatalog.cabinetTemplateId(depth),
        cabinetDepthCm: depth,
        priority: 22,
        rankReason: '收纳 · 富余面宽内存条',
      ));
      break;
    }
  }

  /// R009：手填面宽视距 —— 偏短时提示（拆墙模拟仍 L3）
  void _r009(PlanDocument plan, List<DiagAdvice> out) {
    final red = plan.annotations.redRulerCm;
    if (red == null) return;
    final living = plan.rooms.where((r) => r.type == 'living');
    final ref = living.isEmpty ? 400.0 : living.first.widthCm;
    if (red + 1 >= ref * 0.85) return;
    out.add(_advice(
      ruleId: 'R009',
      typeId: 'soft_textile',
      diyLevel: 'L1',
      title: '最大视距偏短',
      reason:
          '手填面宽视距 ${red.toStringAsFixed(0)}cm，相对客厅面宽偏紧。可先用浅色软装改善感受；若考虑拆墙拉通视距属专业改造。',
      templateId: 'T-L1-TEXTILE-01',
      priority: 32,
      rankReason: '显大 · 面宽视距',
    ));
    if (red < 280) {
      out.add(_advice(
        ruleId: 'R009',
        typeId: 'wall_remove',
        diyLevel: 'L3',
        title: '拉通视距若需拆墙',
        reason: '面宽视距明显偏短时，打通隔墙可改善，但须确认承重与物业规定。',
        templateId: 'T-L3-WALL-01',
        priority: 15,
        rankReason: '安全栈 · 拆墙仅提示',
      ));
    }
  }

  /// R010：三通比例 survey —— open_connections / (建筑面积×0.8) 启发式
  void _r010(PlanDocument plan, List<DiagAdvice> out) {
    final opens = plan.annotations.openConnections;
    if (opens.isEmpty) return;
    // 每条打通关系按约 12㎡ 估算连通感贡献（survey 启发式）
    final openArea = opens.length * 12.0;
    final base = plan.building.areaBuildM2 * 0.8;
    if (base <= 0) return;
    final ratio = openArea / base;
    if (ratio >= 0.30) return;
    out.add(_advice(
      ruleId: 'R010',
      typeId: 'wall_remove',
      diyLevel: 'L3',
      title: '三通比例可能不足',
      reason:
          '已标记打通 ${opens.length} 处，估算连通感约 ${(ratio * 100).toStringAsFixed(0)}%（目标参考 ≥30%）。继续扩大打通请专业评估。',
      templateId: 'T-L3-WALL-01',
      priority: 18,
      rankReason: '安全/显大 · 三通 survey',
    ));
  }

  void _r011(PlanDocument plan, List<DiagAdvice> out) {
    if (plan.building.colorSchemeOk) return;
    out.add(_advice(
      ruleId: 'R011',
      typeId: 'soft_color',
      diyLevel: 'L1',
      title: '压缩跳色，守住主色+辅色',
      reason: '建议一种底色加一种跳色，跳色观感控制在约两成内，空间更干净。',
      templateId: 'T-L1-COLOR-01',
      priority: 45,
      rankReason: '颜值栈 · 主色+辅色',
    ));
  }

  int _pickDepth(double surplus) {
    final depths = AppConstants.cabinetDepthsCm.reversed;
    for (final d in depths) {
      if (surplus >= d + 10) return d;
    }
    return 15;
  }
}
