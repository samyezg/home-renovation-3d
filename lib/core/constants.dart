/// V1 建模与业务常数（docs/03-v1/data/V1-建模常数说明.md）
abstract final class AppConstants {
  static const String appName = '轻装家';
  static const String appVersion = '0.4.17+35';

  static const double floorHeightCm = 280;
  static const double defaultDoorWidthCm = 80;
  /// 默认窗宽（住宅常见；过大时画布符号会显胖）
  static const double defaultWindowWidthCm = 120;
  static const double defaultWindowHeightCm = 140;
  static const double defaultWindowSillCm = 90;

  /// 共墙聚类：绝对下限 cm（Y2 收紧，不再跟跨度放大太多）
  static const double coWallAbsTolCm = 2.0;
  /// 共墙相对跨度系数（原 0.25% → 0.1%）
  static const double coWallRelTol = 0.001;
  /// 导入前邻接贴边归一化容差（原 0.012 → 0.006）
  static const double snapAdjacentNormTol = 0.006;

  /// 画布标注 / 改尺寸对话框对外统一用 mm（内部仍存 cm）。
  static int cmToMm(double cm) => (cm * 10).round();
  static double mmToCm(num mm) => mm.toDouble() / 10.0;
  static String formatMm(double cm) => '${cmToMm(cm)}';
  static const double storageRatioTarget = 0.12;

  /// 最小面宽权威表（cm）
  static const Map<String, double> minWidthCm = {
    'living': 315,
    'bedroom_master': 270,
    'bedroom': 240,
    'study': 210,
  };

  static const List<int> cabinetDepthsCm = [15, 30, 35, 45, 60];

  static const String disclaimer =
      '仅供参考，不替代专业设计与施工。';
  static const String diyDisclaimer =
      '步骤仅供参考。施工前确认墙体无水路电路；如无把握请停止并寻求专业帮助。效果因现场而异。';
  static const String l3Disclaimer =
      '此改造涉及结构或水电安全，请咨询专业人士。「轻装家」不提供 DIY 施工步骤。';
  static const String acceptanceDisclaimer =
      '仅供参考，不替代专业验收与隐蔽工程检测。';
  static const String safetyDisclaimer =
      '仅供参考。涉及改门、电路、燃气、承重，请咨询专业人员。';
}
