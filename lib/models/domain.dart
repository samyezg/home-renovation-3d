class DiagnosisReport {
  DiagnosisReport({
    required this.summaryTitle,
    required this.summaryBody,
    required this.metrics,
    required this.advices,
    required this.divisor,
    required this.sizeLabel,
    required this.cityOffsetApplied,
    this.rankExplain = const [],
    this.allAdviceCount = 0,
    this.highlights = const [],
  });

  final String summaryTitle;
  final String summaryBody;
  final List<DiagMetric> metrics;
  final List<DiagAdvice> advices;
  final double divisor;
  final String sizeLabel;
  final double cityOffsetApplied;
  final List<String> rankExplain;
  final int allAdviceCount;
  final List<String> highlights;
}

class DiagnosisBlocker {
  const DiagnosisBlocker({required this.code, required this.message});
  final String code;
  final String message;
}

class DiagMetric {
  DiagMetric({
    required this.id,
    required this.title,
    required this.value,
    required this.sub,
  });

  final String id;
  final String title;
  final String value;
  final String sub;
}

class DiagAdvice {
  DiagAdvice({
    required this.ruleId,
    required this.typeId,
    required this.diyLevel,
    required this.title,
    required this.reason,
    this.cabinetDepthCm,
    this.templateId,
    this.priority = 50,
    this.stackLabel = '其他',
    this.rankReason = '',
  });

  final String ruleId;
  final String typeId;
  final String diyLevel; // L1 L2 L3
  final String title;
  final String reason;
  final int? cabinetDepthCm;
  final String? templateId;
  final int priority;
  final String stackLabel; // 安全/收纳/显大/颜值
  final String rankReason;
}

class ChecklistLine {
  ChecklistLine({
    required this.id,
    required this.category,
    required this.title,
    this.specHint,
    this.source,
    this.price,
    this.depthCm,
    this.skuId,
    this.qty = 1,
    this.roomHint,
  });

  final String id;
  String category;
  String title;
  String? specHint;
  String? source;
  double? price; // always null in V1
  int? depthCm;
  String? skuId;
  int qty;
  String? roomHint;

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'title': title,
        'spec_hint': specHint,
        'source': source,
        'price': price,
        'depth_cm': depthCm,
        'sku_id': skuId,
        'qty': qty,
        'room_hint': roomHint,
      };

  factory ChecklistLine.fromJson(Map<String, dynamic> j) => ChecklistLine(
        id: j['id'] as String,
        category: j['category'] as String? ?? '其他',
        title: j['title'] as String? ?? '',
        specHint: j['spec_hint'] as String?,
        source: j['source'] as String?,
        price: (j['price'] as num?)?.toDouble(),
        depthCm: j['depth_cm'] as int?,
        skuId: j['sku_id'] as String?,
        qty: (j['qty'] as num?)?.toInt() ?? 1,
        roomHint: j['room_hint'] as String?,
      );
}

class DiyTemplate {
  const DiyTemplate({
    required this.templateId,
    required this.typeId,
    required this.diyLevel,
    required this.title,
    required this.stars,
    required this.durationMin,
    required this.durationMax,
    required this.tools,
    required this.materials,
    required this.steps,
    required this.warnings,
    required this.listCategory,
    required this.listSpecHint,
  });

  final String templateId;
  final String typeId;
  final String diyLevel;
  final String title;
  final int stars;
  final int durationMin;
  final int durationMax;
  final List<String> tools;
  final List<String> materials;
  final List<String> steps;
  final List<String> warnings;
  final String listCategory;
  final String listSpecHint;
}

class AcceptanceItem {
  const AcceptanceItem({
    required this.id,
    required this.section,
    required this.title,
    required this.standard,
    required this.failHint,
    this.failTypeId,
  });

  final String id;
  final String section;
  final String title;
  final String standard;
  final String failHint;
  final String? failTypeId;
}

class SafetyItem {
  const SafetyItem({
    required this.id,
    required this.shortTitle,
    required this.question,
    required this.yesMeaning,
    required this.noHint,
    required this.help,
  });

  final String id;
  final String shortTitle;
  final String question;
  final String yesMeaning;
  final String noHint;
  final String help;
}

enum CheckTriState { yes, no, na, unanswered }
