import '../models/domain.dart';

abstract final class AcceptanceCatalog {
  static const items = <AcceptanceItem>[
    AcceptanceItem(id: 'AC-01', section: '全屋通用', title: '空鼓初查', standard: '用指节轻敲瓷砖/地板，大面积无明显空鼓声', failHint: '标记位置，请装修方或专业人员复查'),
    AcceptanceItem(id: 'AC-02', section: '全屋通用', title: '墙面观感', standard: '目视无明显大面积裂缝、渗色、鼓包', failHint: '拍照留存，协商修补'),
    AcceptanceItem(id: 'AC-03', section: '全屋通用', title: '开关插座外观', standard: '面板无破裂、无明显歪斜；按压手感正常', failHint: '更换面板或请电工检查', failTypeId: 'electrical'),
    AcceptanceItem(id: 'AC-04', section: '全屋通用', title: '门扇开关', standard: '开关顺畅，无明显刮地、关不严', failHint: '请木工/安装工调试合页与缝隙'),
    AcceptanceItem(id: 'AC-05', section: '全屋通用', title: '收纳基础', standard: '主要空间（玄关/卧室/厨卫）均有就近收纳点', failHint: '记入改造清单，优先软装/柜体方案', failTypeId: 'cabinet_thin'),
    AcceptanceItem(id: 'AC-06', section: '玄关', title: '换鞋条件', standard: '有换鞋凳位或可临时落座处', failHint: '增换鞋凳或壁挂式换鞋方案', failTypeId: 'entry_stool'),
    AcceptanceItem(id: 'AC-07', section: '玄关', title: '鞋柜分区', standard: '有常穿/季储分区或可分区意向', failHint: '用隔板/收纳盒做二八分区', failTypeId: 'storage_box'),
    AcceptanceItem(id: 'AC-08', section: '玄关', title: '进出照明', standard: '进门可方便开灯或有感应灯', failHint: '加感应夜灯/易触及开关', failTypeId: 'soft_plant_light'),
    AcceptanceItem(id: 'AC-09', section: '客厅', title: '电视墙插座', standard: '电视位附近有可用电源', failHint: '整理排插走线或请电工加点位', failTypeId: 'cable_tidy'),
    AcceptanceItem(id: 'AC-10', section: '客厅', title: '座位收纳', standard: '沙发区有抱枕毯等就近收纳或篮筐', failHint: '增加收纳篮/边几柜', failTypeId: 'soft_textile'),
    AcceptanceItem(id: 'AC-11', section: '客厅', title: '视平线装饰', standard: '110～170cm 高度有至少 1 处挂画/壁灯/层架等', failHint: '按配色建议补主视觉挂画', failTypeId: 'soft_art'),
    AcceptanceItem(id: 'AC-12', section: '餐厅', title: '餐桌旁暂存', standard: '餐桌附近有边柜/推车可放餐具纸巾', failHint: '增加窄边柜或餐车', failTypeId: 'cabinet_sideboard'),
    AcceptanceItem(id: 'AC-13', section: '餐厅', title: '桌面杂物', standard: '桌面长期杂物不多，有归处', failHint: '用托盘/盒子收纳，控制展示量', failTypeId: 'storage_box'),
    AcceptanceItem(id: 'AC-14', section: '厨房', title: '台面净空感', standard: '常用区台面可放下砧板与备菜，不过分堆满', failHint: '上墙置物/柜内分层', failTypeId: 'shelf_wall'),
    AcceptanceItem(id: 'AC-15', section: '厨房', title: '插座够用', standard: '台面附近至少能同时使用 2 件小家电', failHint: '请电工评估增位；勿私拉电线', failTypeId: 'electrical'),
    AcceptanceItem(id: 'AC-16', section: '厨房', title: '灶具周边', standard: '灶具旁可安全转身，杂物未紧贴炉火', failHint: '清理可燃杂物，调整动线摆放'),
    AcceptanceItem(id: 'AC-17', section: '厨房', title: '垃圾桶位', standard: '有固定垃圾桶位置且易清理', failHint: '选定柜下/门旁位置并固定容器', failTypeId: 'trash_station'),
    AcceptanceItem(id: 'AC-18', section: '卫生间', title: '干湿意图', standard: '淋浴与洗手区有分隔意图', failHint: '先加浴帘等低成本分隔', failTypeId: 'shower_curtain'),
    AcceptanceItem(id: 'AC-19', section: '卫生间', title: '镜区收纳', standard: '镜柜或台面有洗漱用品固定位置', failHint: '加镜柜收纳盒', failTypeId: 'mirror_cabinet'),
    AcceptanceItem(id: 'AC-20', section: '卫生间', title: '防滑感', standard: '淋浴区脚感不光滑过度，有垫或防滑措施', failHint: '加防滑垫/防滑贴', failTypeId: 'anti_slip'),
    AcceptanceItem(id: 'AC-21', section: '卧室', title: '床头收纳', standard: '床头有台灯位与小物放置处', failHint: '加床头柜或墙搁板', failTypeId: 'shelf_wall'),
    AcceptanceItem(id: 'AC-22', section: '卧室', title: '衣物收纳', standard: '有衣柜或等效衣物收纳，未长期堆床', failHint: '优先通高/组合柜方案', failTypeId: 'cabinet_wardrobe'),
    AcceptanceItem(id: 'AC-23', section: '卧室', title: '插座便利', standard: '床头两侧或一侧有充电条件', failHint: '床头排插整理或请电工', failTypeId: 'cable_tidy'),
    AcceptanceItem(id: 'AC-24', section: '阳台/家政', title: '洗衣动线', standard: '洗衣、晾晒路径基本顺畅，工具有处放', failHint: '加窄柜/挂杆收纳', failTypeId: 'cabinet_thin'),
    AcceptanceItem(id: 'AC-25', section: '阳台/家政', title: '杂物落地', standard: '无明显长期堆地杂物挡通道', failHint: '箱盒归类上架', failTypeId: 'storage_box'),
  ];
}

abstract final class SafetyCatalog {
  static const intro = '以下为居家安全与通行便利自查，完成后会给你简单提示。不能代替专业改造方案。';

  static const items = <SafetyItem>[
    SafetyItem(id: 'SF-01', shortTitle: '地面高差', question: '家里主要通行地面是否基本无门槛、无台阶卡脚？', yesMeaning: '通行较平坦', noHint: '易绊倒处可先加提示条或缓坡垫；改地面请专业', help: '含卫生间门口、阳台门轨等'),
    SafetyItem(id: 'SF-02', shortTitle: '扶手与抓握', question: '卫生间、走廊等湿滑或易滑倒处，是否已有扶手或可抓稳的固定物？', yesMeaning: '关键位置有依靠', noHint: '可考虑加装卫生间扶手（安装请专业）', help: '租赁房可用免钉方案作临时措施'),
    SafetyItem(id: 'SF-03', shortTitle: '门宽通行', question: '常走的房门净宽是否大约 ≥80cm（约两张 A4 横放再加一点）？', yesMeaning: '通行较宽裕', noHint: '轮椅或搬大型家具可能费力；改门请专业（不提供 DIY 改门步骤）', help: '量的是门扇打开后的净宽'),
    SafetyItem(id: 'SF-04', shortTitle: '公区视线', question: '客厅、餐厅、厨房之间，白天是否大致互相看得见、不憋闷？', yesMeaning: '视线较通透', noHint: '可先用半开放软隔断改善感受；拆墙请专业', help: '指观感通透，非强制拆墙'),
    SafetyItem(id: 'SF-05', shortTitle: '感应照明', question: '走廊、卫生间门口等，夜间是否能方便照明（感应灯或易摸到的开关）？', yesMeaning: '起夜较方便', noHint: '建议加感应夜灯（注意电路安全）', help: '优先插电感应灯，改接线请电工'),
    SafetyItem(id: 'SF-06', shortTitle: '家具边角', question: '常碰触的家具边角是否较圆润或已做防撞？', yesMeaning: '磕碰风险较低', noHint: '可贴防撞角/换圆角家具', help: '重点：茶几、床头、橱柜转角'),
    SafetyItem(id: 'SF-07', shortTitle: '紧急呼叫', question: '是否准备了紧急联系方式（家人电话一键可拨、或呼叫设备）？', yesMeaning: '有应急联系手段', noHint: '建议手机设置紧急联系人；条件允许可加呼叫器', help: '不绑定特定品牌设备'),
    SafetyItem(id: 'SF-08', shortTitle: '卫浴防滑', question: '淋浴区/卫生间地面是否有防滑措施（防滑砖、防滑垫等）？', yesMeaning: '防滑有关照', noHint: '先加防滑垫；改造地面请专业', help: '出水口保持通畅，减少积水'),
  ];

  static String scoreMessage(int yesCount) {
    if (yesCount >= 7) {
      return '安全项完成度较高：当前自查表现不错。仍请定期检查防滑与照明。';
    }
    if (yesCount >= 4) {
      return '还有几处值得加强：建议优先处理标记为「否」的项，尤其是地面防滑与夜间照明。';
    }
    return '建议尽快改善通行与防滑：家中跌倒风险可能偏高。请与家人商量，必要时咨询专业改造。';
  }
}

abstract final class RoomTypeLabels {
  static const Map<String, String> labels = {
    'living': '客厅',
    'dining': '餐厅',
    'kitchen': '厨房',
    'bedroom_master': '主卧',
    'bedroom': '次卧',
    'study': '书房',
    'bath': '卫生间',
    'balcony': '阳台',
    'entry': '玄关',
    'other': '其他',
  };
}

abstract final class SceneCatalog {
  static List<Map<String, dynamic>> modules() => [
        for (final d in [15, 30, 35, 45, 60])
          {
            'sku_id': 'cab_$d',
            'name': d <= 20 ? '${d}cm 薄柜' : '${d}cm 深柜',
            'kind': 'cabinet',
            'depth_cm': d,
            'width_cm': 60,
            'height_cm': 220,
          },
        {
          'sku_id': 'furn_bed',
          'name': '双人床',
          'kind': 'furniture',
          'depth_cm': 200,
          'width_cm': 150,
          'height_cm': 50,
        },
        {
          'sku_id': 'furn_desk',
          'name': '书桌',
          'kind': 'furniture',
          'depth_cm': 60,
          'width_cm': 120,
          'height_cm': 75,
        },
        {
          'sku_id': 'furn_sofa',
          'name': '沙发',
          'kind': 'furniture',
          'depth_cm': 90,
          'width_cm': 200,
          'height_cm': 80,
        },
        {
          'sku_id': 'furn_table',
          'name': '餐桌',
          'kind': 'furniture',
          'depth_cm': 90,
          'width_cm': 140,
          'height_cm': 75,
        },
        {
          'sku_id': 'furn_chair',
          'name': '餐椅',
          'kind': 'furniture',
          'depth_cm': 50,
          'width_cm': 45,
          'height_cm': 90,
        },
        {
          'sku_id': 'furn_wardrobe',
          'name': '衣柜',
          'kind': 'cabinet',
          'depth_cm': 60,
          'width_cm': 180,
          'height_cm': 220,
        },
        {
          'sku_id': 'furn_tvstand',
          'name': '电视柜',
          'kind': 'cabinet',
          'depth_cm': 40,
          'width_cm': 160,
          'height_cm': 50,
        },
        {
          'sku_id': 'furn_coffee',
          'name': '茶几',
          'kind': 'furniture',
          'depth_cm': 60,
          'width_cm': 100,
          'height_cm': 45,
        },
        {
          'sku_id': 'furn_shoe',
          'name': '鞋柜',
          'kind': 'cabinet',
          'depth_cm': 35,
          'width_cm': 100,
          'height_cm': 120,
        },
        {
          'sku_id': 'furn_bookshelf',
          'name': '书柜',
          'kind': 'cabinet',
          'depth_cm': 35,
          'width_cm': 90,
          'height_cm': 200,
        },
        {
          'sku_id': 'furn_sideboard',
          'name': '餐边柜',
          'kind': 'cabinet',
          'depth_cm': 40,
          'width_cm': 120,
          'height_cm': 90,
        },
        {
          'sku_id': 'furn_fridge',
          'name': '冰箱',
          'kind': 'appliance',
          'depth_cm': 65,
          'width_cm': 60,
          'height_cm': 180,
        },
        {
          'sku_id': 'furn_washer',
          'name': '洗衣机',
          'kind': 'appliance',
          'depth_cm': 60,
          'width_cm': 60,
          'height_cm': 85,
        },
        {
          'sku_id': 'furn_tv',
          'name': '电视',
          'kind': 'appliance',
          'depth_cm': 8,
          'width_cm': 120,
          'height_cm': 70,
        },
        {
          'sku_id': 'furn_ac',
          'name': '空调',
          'kind': 'appliance',
          'depth_cm': 25,
          'width_cm': 90,
          'height_cm': 30,
        },
        {
          'sku_id': 'furn_toilet',
          'name': '马桶',
          'kind': 'fixture',
          'depth_cm': 70,
          'width_cm': 40,
          'height_cm': 80,
        },
        {
          'sku_id': 'furn_sink',
          'name': '洗手台',
          'kind': 'fixture',
          'depth_cm': 50,
          'width_cm': 80,
          'height_cm': 85,
        },
        {
          'sku_id': 'furn_stove',
          'name': '灶台',
          'kind': 'fixture',
          'depth_cm': 60,
          'width_cm': 80,
          'height_cm': 85,
        },
        {
          'sku_id': 'furn_kitchensink',
          'name': '水槽',
          'kind': 'fixture',
          'depth_cm': 55,
          'width_cm': 80,
          'height_cm': 85,
        },
      ];

  static Map<String, dynamic>? bySku(String skuId) {
    for (final m in modules()) {
      if (m['sku_id'] == skuId) return m;
    }
    return null;
  }

  /// 用户可读名；兼容旧 sku / 裸 title
  static String labelOf(String skuId) {
    final hit = bySku(skuId);
    if (hit != null) return hit['name'] as String? ?? skuId;
    // cab_35 等
    final cab = RegExp(r'^cab_(\d+)$').firstMatch(skuId);
    if (cab != null) {
      final d = int.parse(cab.group(1)!);
      return d <= 20 ? '${d}cm 薄柜' : '${d}cm 深柜';
    }
    return skuId;
  }
}
