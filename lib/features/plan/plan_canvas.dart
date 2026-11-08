import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../data/catalogs.dart';
import '../../models/plan.dart';
import '../../services/plan_city_settings.dart';
import '../../services/repositories.dart';
import '../../theme/app_colors.dart';
import '../../theme/style_mode.dart';
import '../../widgets/plan_template_sheet.dart';
import '../../widgets/style_mode_sheet.dart';

/// 户型画布：选中制拖拽、门窗落墙、承重、尺寸标注、手绘 V3 多边形、家具布置 I11、I16 手柄
///
/// 交互（已批准）：
/// - 单击：仅选中；已选可拖；拖中不吸附，松手对齐 10cm
/// - 选中后 8 手柄改尺寸；拖移显示幽灵原点；空白点击取消选中
/// - 双击或「改尺寸」：编辑属性
/// - 「手绘」V3：笔画 → 简化多边形 → 确认卡 → 落定 RoomRect(shape:polygon)
/// - 期次 R：切角、顶点拖移/删除、门窗按异形边归属并保留沿墙位置
/// - I10：选中墙旁「+门洞」；门洞建筑符号；沿墙拖位置
/// - I12：选中墙旁「+窗户」；四线窗符号；尺寸自动标注
/// - I11：右下角家具 FAB → 目录落定；拖移/旋转/删除；3D 单向同步
/// - I16：户型模板入口
/// - 期次 U：操作提示可淡出；结构变更可撤销一档
class PlanCanvasPanel extends StatefulWidget {
  const PlanCanvasPanel({
    super.key,
    required this.plan,
    required this.onChanged,
  });

  final PlanDocument plan;
  final VoidCallback onChanged;

  static const double pxPerCm = 0.35;
  static const double gridCm = 10;
  static const double minHitDp = 44;

  @override
  State<PlanCanvasPanel> createState() => _PlanCanvasPanelState();
}

class _PlanCanvasPanelState extends State<PlanCanvasPanel> {
  String? _selectedRoomId;
  String? _selectedWallId;
  var _draggingRoom = false;
  var _resizingRoom = false;
  var _draggingDoor = false;
  var _draggingWindow = false;
  var _draggingFurniture = false;
  /// I16：拖移幽灵原点（cm）
  double? _dragOriginX;
  double? _dragOriginY;
  var _drawMode = false;
  /// 期次 W：手型平移（禁用选中，专心拖动画布）
  var _handPanMode = false;
  final _transform = TransformationController();
  final _viewerKey = GlobalKey();
  final List<Offset> _strokePx = [];
  List<Offset>? _sketchUnderlayPx;
  var _styleMode = CanvasStyleMode.simple;
  var _tone = StyleTone.warmWood;
  /// I10/I12：门窗列表面板展开（有门或窗时可展开；空态仅状态条）
  var _openingsExpanded = false;
  String? _selectedDoorId;
  String? _selectedWindowId;
  /// I11：画布家具选中
  String? _selectedFurnitureId;
  /// 期次 R：顶点编辑模式（多边形房间）
  var _vertexEditMode = false;
  var _draggingVertex = false;
  int? _dragVertexIndex;
  /// 期次 U：单档撤销快照
  Map<String, dynamic>? _undoSnapshot;
  /// I9 P1：操作提示（进入后淡出，点「？」可再看）
  var _hintVisible = true;

  static const double _minRoomCm = 80;
  static const double _handleVisualDp = 8;
  static const double _handleHitDp = 44;
  static const double _vertexVisualDp = 10;
  static const double _defaultChamferCm = 80;

  PlanDocument get plan => widget.plan;

  CanvasPalette get _palette =>
      StyleModeCatalog.canvasPalette(_styleMode, _tone);

  @override
  void initState() {
    super.initState();
    _loadStylePrefs();
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _hintVisible = false);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || plan.rooms.isEmpty) return;
      _fitMainCluster();
    });
  }

  void _captureUndo() {
    _undoSnapshot =
        jsonDecode(jsonEncode(plan.toJson())) as Map<String, dynamic>;
  }

  void _clearSelection() {
    _selectedRoomId = null;
    _selectedWallId = null;
    _selectedDoorId = null;
    _selectedWindowId = null;
    _selectedFurnitureId = null;
    _draggingRoom = false;
    _resizingRoom = false;
    _draggingDoor = false;
    _draggingWindow = false;
    _draggingFurniture = false;
    _vertexEditMode = false;
    _draggingVertex = false;
    _dragVertexIndex = null;
    _dragOriginX = null;
    _dragOriginY = null;
  }

  void _performUndo() {
    final snap = _undoSnapshot;
    if (snap == null) return;
    setState(() {
      plan.restoreFromJson(snap);
      _undoSnapshot = null;
      _clearSelection();
    });
    widget.onChanged();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已撤销上一步')),
    );
  }

  void _flashHint() {
    setState(() => _hintVisible = true);
    Future<void>.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _hintVisible = false);
    });
  }

  String get _hintText {
    if (_handPanMode) return '手型：拖移/捏合浏览 · 再点手型退出 · 「适应」可框住主户型';
    if (_drawMode) return '手绘：松手生成多边形房间';
    if (_vertexEditMode) {
      return '顶点编辑：拖顶点 · 双击顶点删除（≥4 点）· 切角见工具栏';
    }
    if (_selectedWallId != null) {
      return '选中墙：+门/窗 · 合并附近共墙 · 拆为通口 · 承重';
    }
    return '选中后拖移·拖角改尺寸·切角/顶点 · 可撤销一步';
  }

  /// 期次 W：把主连通房间簇适配进视口。
  void _fitMainCluster() {
    final rooms = plan.rooms;
    if (rooms.isEmpty) return;
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    void expand(double x, double y) {
      minX = math.min(minX, x);
      minY = math.min(minY, y);
      maxX = math.max(maxX, x);
      maxY = math.max(maxY, y);
    }

    for (final r in rooms) {
      final poly = r.polygon;
      if (poly != null && poly.length >= 3) {
        for (final p in poly) {
          if (p.length >= 2) expand(p[0], p[1]);
        }
      } else {
        expand(r.x, r.y);
        expand(r.x + r.widthCm, r.y + r.depthCm);
      }
    }
    if (!minX.isFinite) return;
    const pad = 40.0;
    minX -= pad;
    minY -= pad;
    maxX += pad;
    maxY += pad;
    final contentW = (maxX - minX) * PlanCanvasPanel.pxPerCm;
    final contentH = (maxY - minY) * PlanCanvasPanel.pxPerCm;
    if (contentW < 1 || contentH < 1) return;

    final box = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    final vw = box?.size.width ?? 360.0;
    final vh = box?.size.height ?? 480.0;
    final scale = (math.min(vw / contentW, vh / contentH) * 0.92)
        .clamp(0.2, 5.0);
    final contentLeft = minX * PlanCanvasPanel.pxPerCm;
    final contentTop = minY * PlanCanvasPanel.pxPerCm;
    final dx = (vw - contentW * scale) / 2 - contentLeft * scale;
    final dy = (vh - contentH * scale) / 2 - contentTop * scale;
    _transform.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
    setState(() {});
  }

  void _deleteSelectedRoom() {
    final r = _selectedRoom;
    if (r == null) return;
    _captureUndo();
    setState(() {
      plan.rooms.removeWhere((e) => e.id == r.id);
      plan.doors.removeWhere((d) => d.roomId == r.id);
      plan.windows.removeWhere((w) => w.roomId == r.id);
      plan.furniture.removeWhere((f) => f.roomId == r.id);
      plan.rebuildWallsFromRooms();
      _clearSelection();
    });
    widget.onChanged();
  }

  void _deleteDoor(DoorOpening d) {
    _captureUndo();
    setState(() {
      plan.doors.removeWhere((e) => e.id == d.id);
      if (_selectedDoorId == d.id) _selectedDoorId = null;
    });
    widget.onChanged();
  }

  void _deleteWindow(WindowOpening w) {
    _captureUndo();
    setState(() {
      plan.windows.removeWhere((e) => e.id == w.id);
      if (_selectedWindowId == w.id) _selectedWindowId = null;
    });
    widget.onChanged();
  }

  Future<void> _loadStylePrefs() async {
    final s = await SettingsRepository().load();
    if (!mounted) return;
    setState(() {
      _styleMode = StyleModeCatalog.parseCanvas(s['canvas_style_mode'] as String?);
      _tone = StyleModeCatalog.parseTone(s['style_tone'] as String?);
    });
  }

  Future<void> _persistStyle() async {
    final s = await SettingsRepository().load();
    s['canvas_style_mode'] = _styleMode.name;
    s['style_tone'] = _tone.name;
    await SettingsRepository().save(s);
  }

  Future<void> _openStyleSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StyleModeSheet.canvas(
        mode: _styleMode,
        tone: _tone,
        onMode: (m) {
          setState(() => _styleMode = m);
          _persistStyle();
        },
        onTone: (t) {
          setState(() => _tone = t);
          _persistStyle();
        },
      ),
    );
  }

  double _snap(double cm) =>
      (cm / PlanCanvasPanel.gridCm).round() * PlanCanvasPanel.gridCm;

  RoomRect? get _selectedRoom {
    final id = _selectedRoomId;
    if (id == null) return null;
    for (final r in plan.rooms) {
      if (r.id == id) return r;
    }
    return null;
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bearingCount =
        plan.constraints.where((c) => c.type == 'load_bearing').length;
    return Column(
      children: [
        // I9.1：一行图标工具栏（44dp），条件显隐
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            children: [
              IconButton(
                tooltip: '加房间',
                onPressed: _addRoom,
                icon: const Icon(Icons.add),
              ),
              IconButton(
                tooltip: _drawMode ? '退出手绘' : '手绘',
                isSelected: _drawMode,
                onPressed: () {
                  setState(() {
                    _drawMode = !_drawMode;
                    _strokePx.clear();
                    if (_drawMode) {
                      _handPanMode = false;
                      _selectedRoomId = null;
                      _selectedDoorId = null;
                      _selectedWindowId = null;
                      _selectedFurnitureId = null;
                      _draggingRoom = false;
                      _resizingRoom = false;
                      _vertexEditMode = false;
                      _draggingVertex = false;
                      _dragVertexIndex = null;
                      _dragOriginX = null;
                      _dragOriginY = null;
                      _draggingDoor = false;
                      _draggingWindow = false;
                      _draggingFurniture = false;
                    }
                  });
                },
                icon: Icon(_drawMode ? Icons.edit_off : Icons.gesture),
              ),
              IconButton(
                tooltip: _handPanMode ? '退出平移' : '手型平移',
                isSelected: _handPanMode,
                onPressed: () {
                  setState(() {
                    _handPanMode = !_handPanMode;
                    if (_handPanMode) {
                      _drawMode = false;
                      _strokePx.clear();
                      _selectedRoomId = null;
                      _selectedWallId = null;
                      _selectedDoorId = null;
                      _selectedWindowId = null;
                      _selectedFurnitureId = null;
                      _vertexEditMode = false;
                    }
                  });
                },
                icon: const Icon(Icons.pan_tool_alt_outlined),
              ),
              IconButton(
                tooltip: '适应主户型',
                onPressed: plan.rooms.isEmpty ? null : _fitMainCluster,
                icon: const Icon(Icons.fit_screen_outlined),
              ),
              IconButton(
                tooltip: '门洞落墙',
                onPressed: plan.rooms.isEmpty ? null : _addDoorOnWall,
                icon: const Icon(Icons.door_front_door_outlined),
              ),
              IconButton(
                tooltip: '加窗户',
                onPressed: plan.rooms.isEmpty ? null : _addWindowOnWall,
                icon: const Icon(Icons.window_outlined),
              ),
              if (_selectedWallId != null)
                IconButton(
                  tooltip: _isSelectedWallBearing() ? '取消承重' : '标承重墙',
                  onPressed: _toggleLoadBearing,
                  icon: const Icon(Icons.foundation),
                ),
              if (_selectedWallId != null)
                IconButton(
                  tooltip: '合并附近共墙',
                  onPressed: _mergeSelectedWallWithNearby,
                  icon: const Icon(Icons.join_full),
                ),
              if (_selectedWallId != null)
                IconButton(
                  tooltip: '拆为通口',
                  onPressed: _openSelectedWallAsPassage,
                  icon: const Icon(Icons.horizontal_rule),
                ),
              if (_selectedRoom != null)
                IconButton(
                  tooltip: '改尺寸',
                  onPressed: () => _editRoom(_selectedRoom!),
                  icon: const Icon(Icons.straighten),
                ),
              if (_selectedRoom != null)
                IconButton(
                  tooltip: '切角',
                  onPressed: () => _chamferSelectedRoom(),
                  icon: const Icon(Icons.rounded_corner),
                ),
              if (_selectedRoom != null)
                IconButton(
                  tooltip: _vertexEditMode ? '退出顶点编辑' : '编辑顶点',
                  isSelected: _vertexEditMode,
                  onPressed: () {
                    final r = _selectedRoom!;
                    setState(() {
                      if (!_vertexEditMode) {
                        r.ensurePolygonFromRect();
                        plan.rebuildWallsFromRooms();
                        _preserveOpeningsAfterRebuild();
                        _vertexEditMode = true;
                      } else {
                        _vertexEditMode = false;
                        _draggingVertex = false;
                        _dragVertexIndex = null;
                      }
                    });
                    widget.onChanged();
                  },
                  icon: Icon(
                    _vertexEditMode ? Icons.hexagon : Icons.polyline_outlined,
                  ),
                ),
              if (_selectedRoom != null)
                IconButton(
                  tooltip: '删除房间',
                  onPressed: _deleteSelectedRoom,
                  icon: const Icon(Icons.delete_outline),
                ),
              IconButton(
                tooltip: _undoSnapshot == null ? '无可撤销' : '撤销一步',
                onPressed: _undoSnapshot == null ? null : _performUndo,
                icon: const Icon(Icons.undo),
              ),
              IconButton(
                tooltip: '操作提示',
                onPressed: _flashHint,
                icon: const Icon(Icons.help_outline),
              ),
              IconButton(
                tooltip: '样式·${StyleModeCatalog.canvasLabel(_styleMode)}',
                onPressed: _openStyleSheet,
                icon: const Icon(Icons.palette_outlined),
              ),
              IconButton(
                tooltip: '户型模板',
                onPressed: _applyTemplate,
                icon: const Icon(Icons.dashboard_customize_outlined),
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: _hintVisible
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: Text(
                    _hintText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        Expanded(
          child: Stack(
            children: [
              ColoredBox(
                color: _palette.background,
                child: InteractiveViewer(
                  key: _viewerKey,
                  transformationController: _transform,
                  minScale: 0.2,
                  maxScale: 5.0,
                  boundaryMargin: const EdgeInsets.all(400),
                  panEnabled: _handPanMode ||
                      (!_draggingRoom &&
                          !_resizingRoom &&
                          !_draggingDoor &&
                          !_draggingWindow &&
                          !_draggingFurniture &&
                          !_draggingVertex &&
                          !_drawMode),
                  scaleEnabled: !_draggingRoom &&
                      !_resizingRoom &&
                      !_draggingDoor &&
                      !_draggingWindow &&
                      !_draggingFurniture &&
                      !_draggingVertex &&
                      !_drawMode,
                  child: SizedBox(
                    width: 900,
                    height: 700,
                    child: Stack(
                      children: [
                        CustomPaint(
                          size: const Size(900, 700),
                          painter: _CanvasPainter(
                            plan: plan,
                            selectedWallId: _selectedWallId,
                            pxPerCm: PlanCanvasPanel.pxPerCm,
                            sketch: _sketchUnderlayPx,
                            liveStroke: _drawMode ? _strokePx : null,
                            palette: _palette,
                          ),
                        ),
                        // I16：空白点击取消选中（在房间/墙层之下）
                        if (!_drawMode && !_handPanMode)
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => setState(_clearSelection),
                            ),
                          ),
                        if (!_drawMode && !_handPanMode) ..._wallHitTargets(),
                        if (!_drawMode && !_handPanMode)
                          for (final r in plan.rooms)
                            if (r.id != _selectedRoomId) _roomWidget(r),
                        if (!_drawMode && !_handPanMode)
                          for (final r in plan.rooms)
                            if (r.id == _selectedRoomId) _roomWidget(r),
                        // 门窗符号须在房间层之上，否则会被房间填充挡住
                        if (!_drawMode)
                          IgnorePointer(
                            child: CustomPaint(
                              size: const Size(900, 700),
                              painter: _DoorOverlayPainter(
                                plan: plan,
                                selectedDoorId: _selectedDoorId,
                                pxPerCm: PlanCanvasPanel.pxPerCm,
                                palette: _palette,
                              ),
                            ),
                          ),
                        if (!_drawMode)
                          IgnorePointer(
                            child: CustomPaint(
                              size: const Size(900, 700),
                              painter: _WindowOverlayPainter(
                                plan: plan,
                                selectedWindowId: _selectedWindowId,
                                pxPerCm: PlanCanvasPanel.pxPerCm,
                                palette: _palette,
                              ),
                            ),
                          ),
                        if (!_drawMode)
                          IgnorePointer(
                            child: CustomPaint(
                              size: const Size(900, 700),
                              painter: _DimensionOverlayPainter(
                                plan: plan,
                                pxPerCm: PlanCanvasPanel.pxPerCm,
                              ),
                            ),
                          ),
                        if (!_drawMode && !_handPanMode)
                          for (final d in plan.doors) _doorHitTarget(d),
                        if (!_drawMode && !_handPanMode)
                          for (final w in plan.windows) _windowHitTarget(w),
                        // I16：手柄/幽灵在门窗命中之上，保证拖角可用
                        if (!_drawMode && !_handPanMode) ..._selectedRoomChrome(),
                        // I11：家具在房间之上，便于点选/拖移
                        if (!_drawMode && !_handPanMode)
                          for (final f in plan.furniture)
                            if (f.id != _selectedFurnitureId)
                              _furnitureWidget(f),
                        if (!_drawMode && !_handPanMode)
                          for (final f in plan.furniture)
                            if (f.id == _selectedFurnitureId)
                              _furnitureWidget(f),
                        if (!_drawMode && !_handPanMode) ..._selectedWallOpeningFabs(),
                        if (!_drawMode && !_handPanMode) ..._selectedFurnitureActionBar(),
                        if (_drawMode)
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanStart: (d) {
                                setState(() {
                                  _strokePx
                                    ..clear()
                                    ..add(d.localPosition);
                                });
                              },
                              onPanUpdate: (d) {
                                setState(() => _strokePx.add(d.localPosition));
                              },
                              onPanEnd: (_) => _finishStroke(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              // I11：右下角家具入口
              if (!_drawMode)
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: FloatingActionButton.small(
                    heroTag: 'plan_furniture_fab',
                    tooltip: '家具',
                    backgroundColor: AppColors.surface,
                    foregroundColor: AppColors.brand,
                    onPressed: _openFurnitureCatalog,
                    child: const Icon(Icons.weekend),
                  ),
                ),
            ],
          ),
        ),
        // I9.2 + I10.4 + I12：门窗面板可折叠；空态仅状态条
        _buildOpeningsPanel(bearingCount),
      ],
    );
  }

  Widget _buildOpeningsPanel(int bearingCount) {
    final status =
        '门洞 ${plan.doors.length} · 窗 ${plan.windows.length} · 家具 ${plan.furniture.length} · 承重 $bearingCount'
        '${_selectedRoom == null ? '' : ' · ${_selectedRoom!.name}'}'
        '${_drawMode ? ' · 手绘' : ''}';
    final canExpand = plan.doors.isNotEmpty || plan.windows.isNotEmpty;
    final expanded = canExpand && _openingsExpanded;

    return Material(
      color: AppColors.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: canExpand
                ? () => setState(() => _openingsExpanded = !_openingsExpanded)
                : null,
            child: SizedBox(
              height: 36,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    if (canExpand)
                      Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                        size: 20,
                        color: AppColors.textSecondary,
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (expanded)
            SizedBox(
              height: 220,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                children: [
                  for (final d in plan.doors)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '门 ${d.id} · 墙 ${d.wallId ?? "未落墙"}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                GestureDetector(
                                  onTap: () => _editDoorWidth(d),
                                  child: Text(
                                    '房间 ${d.roomId} · 中心 ${AppConstants.formatMm(d.centerCm)}mm · '
                                    '宽 ${AppConstants.formatMm(d.widthCm)}mm（点此改宽）',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              DropdownButton<String>(
                                isDense: true,
                                underline: const SizedBox.shrink(),
                                value: const {
                                  'swing',
                                  'sliding',
                                  'folding',
                                  'double',
                                }.contains(d.doorType)
                                    ? d.doorType
                                    : 'swing',
                                items: const [
                                  DropdownMenuItem(
                                    value: 'swing',
                                    child: Text('平开'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'sliding',
                                    child: Text('推拉'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'folding',
                                    child: Text('折叠'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'double',
                                    child: Text('双开'),
                                  ),
                                ],
                                onChanged: (v) => _onDoorTypeChanged(d, v),
                              ),
                              DropdownButton<String>(
                                isDense: true,
                                underline: const SizedBox.shrink(),
                                value: d.positionType,
                                items: const [
                                  DropdownMenuItem(
                                    value: 'O',
                                    child: Text('O 外开'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'I',
                                    child: Text('I 内开'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'II',
                                    child: Text('II 推拉'),
                                  ),
                                ],
                                onChanged: (v) {
                                  setState(() => d.positionType = v ?? 'I');
                                  widget.onChanged();
                                },
                              ),
                              IconButton(
                                tooltip: '删除门洞',
                                iconSize: 20,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(
                                  width: 36,
                                  height: 36,
                                ),
                                onPressed: () => _deleteDoor(d),
                                icon: const Icon(Icons.delete_outline),
                                color: AppColors.danger,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  for (final w in plan.windows)
                    ListTile(
                      dense: true,
                      title: Text('窗 ${w.id} · 墙 ${w.wallId ?? "未落墙"}'),
                      subtitle: Text(
                        '房间 ${w.roomId} · 中心 ${AppConstants.formatMm(w.centerCm)}mm · '
                        '${AppConstants.formatMm(w.widthCm)}×${AppConstants.formatMm(w.heightCm)}mm',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DropdownButton<String>(
                            value: w.type,
                            items: const [
                              DropdownMenuItem(
                                value: 'normal',
                                child: Text('普通窗'),
                              ),
                              DropdownMenuItem(
                                value: 'floor',
                                child: Text('落地窗'),
                              ),
                              DropdownMenuItem(
                                value: 'bay',
                                child: Text('飘窗'),
                              ),
                            ],
                            onChanged: (v) {
                              setState(() => w.type = v ?? 'normal');
                              widget.onChanged();
                            },
                          ),
                          IconButton(
                            tooltip: '删除窗户',
                            iconSize: 20,
                            onPressed: () => _deleteWindow(w),
                            icon: const Icon(Icons.delete_outline),
                            color: AppColors.danger,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _onDoorTypeChanged(DoorOpening d, String? v) {
    final type = v ?? 'swing';
    setState(() {
      d.doorType = type;
      if (type == 'sliding') {
        d.positionType = 'II';
      } else if (d.positionType == 'II') {
        d.positionType = 'I';
      }
    });
    widget.onChanged();
  }

  Future<void> _editDoorWidth(DoorOpening d) async {
    final ctrl = TextEditingController(
      text: AppConstants.formatMm(d.widthCm),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('门洞宽度'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '宽度 (mm)',
            helperText: '范围 700–1000，默认 800',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    var w = AppConstants.mmToCm(double.tryParse(ctrl.text) ?? d.widthCm * 10);
    if (w < 70) w = 70;
    if (w > 100) w = 100;
    setState(() => d.widthCm = _snap(w));
    widget.onChanged();
  }

  Future<void> _finishStroke() async {
    if (_strokePx.length < 8) {
      setState(() => _strokePx.clear());
      return;
    }
    final strokeCm = <Offset>[
      for (final p in _strokePx)
        Offset(
          p.dx / PlanCanvasPanel.pxPerCm,
          p.dy / PlanCanvasPanel.pxPerCm,
        ),
    ];
    final polyCm = _simplifyStrokeToPolygon(strokeCm);
    if (polyCm.length < 3) {
      setState(() => _strokePx.clear());
      return;
    }

    var minX = polyCm.first.dx, maxX = polyCm.first.dx;
    var minY = polyCm.first.dy, maxY = polyCm.first.dy;
    for (final p in polyCm) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    var xCm = minX;
    var yCm = minY;
    var wCm = maxX - minX;
    var dCm = maxY - minY;
    if (wCm < 80) wCm = 80;
    if (dCm < 80) dCm = 80;
    if (xCm < 0) xCm = 0;
    if (yCm < 0) yCm = 0;

    final polygon = <List<double>>[
      for (final p in polyCm) [p.dx, p.dy],
    ];

    setState(() {
      _sketchUnderlayPx = [
        for (final p in polyCm)
          Offset(p.dx * PlanCanvasPanel.pxPerCm, p.dy * PlanCanvasPanel.pxPerCm),
        Offset(
          polyCm.first.dx * PlanCanvasPanel.pxPerCm,
          polyCm.first.dy * PlanCanvasPanel.pxPerCm,
        ),
      ];
      _strokePx.clear();
    });

    final confirmed = await _confirmHandRoom(
      xCm: xCm,
      yCm: yCm,
      widthCm: wCm,
      depthCm: dCm,
      polygon: polygon,
    );
    FocusManager.instance.primaryFocus?.unfocus();
    if (confirmed == null) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _drawMode = false);
      });
      return;
    }
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _captureUndo();
      setState(() {
        plan.rooms.add(confirmed);
        plan.rebuildWallsFromRooms();
        _selectedRoomId = confirmed.id;
        _drawMode = false;
        if (confirmed.type != 'bath') {
          plan.doors.add(
            DoorOpening(
              id: 'door_${const Uuid().v4().substring(0, 6)}',
              roomId: confirmed.id,
              widthCm: AppConstants.defaultDoorWidthCm,
              positionType: 'I',
              doorType: 'swing',
              centerCm: confirmed.widthCm / 2,
            ),
          );
          _snapDoorToNearestWall(plan.doors.last);
        }
      });
      widget.onChanged();
    });
  }

  /// 手绘笔画 → 采样 + Douglas-Peucker + 去共线 → 10cm 吸附，最少 3 点。
  List<Offset> _simplifyStrokeToPolygon(List<Offset> strokeCm) {
    if (strokeCm.isEmpty) return const [];
    // 每隔约 25cm 采样，保留首尾
    const sampleStep = 25.0;
    final sampled = <Offset>[strokeCm.first];
    var acc = 0.0;
    for (var i = 1; i < strokeCm.length; i++) {
      acc += (strokeCm[i] - strokeCm[i - 1]).distance;
      if (acc >= sampleStep) {
        sampled.add(strokeCm[i]);
        acc = 0;
      }
    }
    if ((sampled.last - strokeCm.last).distance > 5) {
      sampled.add(strokeCm.last);
    }

    // 未闭合则闭合
    if ((sampled.first - sampled.last).distance > 40) {
      sampled.add(sampled.first);
    }

    var simplified = _douglasPeucker(sampled, 18);
    // 去掉闭合重复点再处理
    if (simplified.length >= 2 &&
        (simplified.first - simplified.last).distance < 1) {
      simplified = simplified.sublist(0, simplified.length - 1);
    }
    simplified = _removeColinear(simplified, 8);
    // 吸附 10cm
    simplified = [
      for (final p in simplified) Offset(_snap(p.dx), _snap(p.dy)),
    ];
    // 去重相邻同点
    final dedup = <Offset>[];
    for (final p in simplified) {
      if (dedup.isEmpty || (dedup.last - p).distance >= 5) {
        dedup.add(p);
      }
    }
    if (dedup.length >= 2 && (dedup.first - dedup.last).distance < 5) {
      dedup.removeLast();
    }
    if (dedup.length < 3) {
      // 退化：用外接矩形四角
      double minX = strokeCm.first.dx, maxX = strokeCm.first.dx;
      double minY = strokeCm.first.dy, maxY = strokeCm.first.dy;
      for (final p in strokeCm) {
        minX = math.min(minX, p.dx);
        maxX = math.max(maxX, p.dx);
        minY = math.min(minY, p.dy);
        maxY = math.max(maxY, p.dy);
      }
      minX = _snap(minX);
      minY = _snap(minY);
      maxX = _snap(math.max(maxX, minX + 80));
      maxY = _snap(math.max(maxY, minY + 80));
      return [
        Offset(minX, minY),
        Offset(maxX, minY),
        Offset(maxX, maxY),
        Offset(minX, maxY),
      ];
    }
    return dedup;
  }

  List<Offset> _douglasPeucker(List<Offset> pts, double epsilon) {
    if (pts.length < 3) return List<Offset>.from(pts);
    var maxDist = 0.0;
    var idx = 0;
    final a = pts.first;
    final b = pts.last;
    for (var i = 1; i < pts.length - 1; i++) {
      final d = _perpDist(pts[i], a, b);
      if (d > maxDist) {
        maxDist = d;
        idx = i;
      }
    }
    if (maxDist > epsilon) {
      final left = _douglasPeucker(pts.sublist(0, idx + 1), epsilon);
      final right = _douglasPeucker(pts.sublist(idx), epsilon);
      return [...left.sublist(0, left.length - 1), ...right];
    }
    return [a, b];
  }

  double _perpDist(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final len2 = dx * dx + dy * dy;
    if (len2 < 1e-6) return (p - a).distance;
    final t = ((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / len2;
    final proj = Offset(a.dx + t * dx, a.dy + t * dy);
    return (p - proj).distance;
  }

  List<Offset> _removeColinear(List<Offset> pts, double tol) {
    if (pts.length < 3) return pts;
    final out = <Offset>[pts.first];
    for (var i = 1; i < pts.length - 1; i++) {
      final a = out.last;
      final b = pts[i];
      final c = pts[i + 1];
      if (_perpDist(b, a, c) > tol) {
        out.add(b);
      }
    }
    out.add(pts.last);
    return out;
  }

  Future<RoomRect?> _confirmHandRoom({
    required double xCm,
    required double yCm,
    required double widthCm,
    required double depthCm,
    List<List<double>>? polygon,
  }) async {
    var type = 'living';
    final wCtrl = TextEditingController(text: AppConstants.formatMm(widthCm));
    final dCtrl = TextEditingController(text: AppConstants.formatMm(depthCm));
    final isPoly = polygon != null && polygon.length >= 3;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(isPoly ? '手绘识别为多边形房间' : '手绘识别为矩形房间'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPoly
                      ? '已简化为 ${polygon.length} 边形（AABB 可改；异形轮廓保留）。'
                      : '已按外接矩形拟合（异形暂收成矩形，可改尺寸与类型）。',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(
                    labelText: '房间类型',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final e in RoomTypeLabels.labels.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setLocal(() => type = v ?? 'living'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: wCtrl,
                  decoration: const InputDecoration(
                    labelText: '面宽 mm（包围盒）',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: dCtrl,
                  decoration: const InputDecoration(
                    labelText: '进深 mm（包围盒）',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认落定'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) {
      wCtrl.dispose();
      dCtrl.dispose();
      return null;
    }
    final w = _snap(
      AppConstants.mmToCm(double.tryParse(wCtrl.text) ?? widthCm * 10),
    );
    final d = _snap(
      AppConstants.mmToCm(double.tryParse(dCtrl.text) ?? depthCm * 10),
    );
    wCtrl.dispose();
    dCtrl.dispose();
    final room = RoomRect(
      id: 'room_${const Uuid().v4().substring(0, 6)}',
      name: RoomTypeLabels.labels[type] ?? '房间',
      type: type,
      x: xCm,
      y: yCm,
      widthCm: widthCm < 80 ? 80 : widthCm,
      depthCm: depthCm < 80 ? 80 : depthCm,
      hasStorageZone: type == 'bedroom_master' || type == 'entry',
      shape: isPoly ? 'polygon' : 'rect',
      polygon: isPoly
          ? [
              for (final p in polygon) [p[0], p[1]],
            ]
          : null,
    );
    if (isPoly) {
      room.syncAabbFromPolygon();
      final tw = w < 80 ? 80.0 : w;
      final td = d < 80 ? 80.0 : d;
      if ((tw - room.widthCm).abs() > 0.5 || (td - room.depthCm).abs() > 0.5) {
        room.setAabbTransformingPolygon(room.x, room.y, tw, td);
      }
    } else {
      room.widthCm = w < 80 ? 80 : w;
      room.depthCm = d < 80 ? 80 : d;
    }
    return room;
  }

  Widget _roomWidget(RoomRect r) {
    final selected = _selectedRoomId == r.id;
    final pal = _palette;
    final visualW = r.widthCm * PlanCanvasPanel.pxPerCm;
    final visualH = r.depthCm * PlanCanvasPanel.pxPerCm;
    final hitW = math.max(visualW, PlanCanvasPanel.minHitDp);
    final hitH = math.max(visualH, PlanCanvasPanel.minHitDp);
    final padX = (hitW - visualW) / 2;
    final padY = (hitH - visualH) / 2;
    final fill = pal.showRoomFill
        ? (r.hasStorageZone
            ? pal.roomFill.withValues(alpha: 0.85)
            : pal.roomFill)
        : Colors.transparent;
    final label = '${r.name}'
        '${selected ? (_vertexEditMode ? '\n顶点编辑中' : '\n拖移 · 拖角双向改尺寸') : ''}';

    void onTap() => setState(() {
          _selectedRoomId = r.id;
          _selectedWallId = null;
          _selectedDoorId = null;
          _selectedWindowId = null;
          _selectedFurnitureId = null;
        });
    void onDoubleTap() {
      setState(() {
        _selectedRoomId = r.id;
        _selectedDoorId = null;
        _selectedWindowId = null;
        _selectedFurnitureId = null;
      });
      _editRoom(r);
    }

    final canDragRoom = selected && !_vertexEditMode;
    final gestures = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onPanStart: canDragRoom
          ? (_) => setState(() {
                _draggingRoom = true;
                _dragOriginX = r.x;
                _dragOriginY = r.y;
                _selectedWallId = null;
                _selectedDoorId = null;
                _selectedWindowId = null;
                _selectedFurnitureId = null;
              })
          : null,
      onPanUpdate: canDragRoom
          ? (d) {
              final scale =
                  _transform.value.getMaxScaleOnAxis().clamp(0.01, 10.0);
              setState(() {
                var dx = d.delta.dx / scale / PlanCanvasPanel.pxPerCm;
                var dy = d.delta.dy / scale / PlanCanvasPanel.pxPerCm;
                if (r.x + dx < 0) dx = -r.x;
                if (r.y + dy < 0) dy = -r.y;
                r.translateBy(dx, dy);
              });
              widget.onChanged();
            }
          : null,
      onPanEnd: canDragRoom
          ? (_) {
              setState(() {
                _draggingRoom = false;
                _dragOriginX = null;
                _dragOriginY = null;
                final sx = _snap(r.x);
                final sy = _snap(r.y);
                r.translateBy(sx - r.x, sy - r.y);
                plan.rebuildWallsFromRooms();
                _preserveOpeningsAfterRebuild();
              });
              widget.onChanged();
            }
          : null,
      child: SizedBox(
        width: visualW,
        height: visualH,
        child: r.hasPolygon
            ? CustomPaint(
                painter: _RoomPolygonPainter(
                  points: [
                    for (final p in r.polygon!)
                      Offset(
                        (p[0] - r.x) * PlanCanvasPanel.pxPerCm,
                        (p[1] - r.y) * PlanCanvasPanel.pxPerCm,
                      ),
                  ],
                  fill: fill,
                  border: selected ? pal.selectedBorder : pal.roomBorder,
                  strokeWidth:
                      selected ? pal.strokeWidth + 1.2 : pal.strokeWidth,
                ),
                child: Center(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: pal.text,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              )
            : Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: fill,
                  border: Border.all(
                    color: selected ? pal.selectedBorder : pal.roomBorder,
                    width: selected ? pal.strokeWidth + 1.2 : pal.strokeWidth,
                  ),
                  boxShadow: selected && pal.showRoomFill
                      ? [
                          BoxShadow(
                            color:
                                pal.selectedBorder.withValues(alpha: 0.25),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: pal.text,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
      ),
    );

    Widget content = gestures;
    if (r.hasPolygon) {
      final localPts = <Offset>[
        for (final p in r.polygon!)
          Offset(
            (p[0] - r.x) * PlanCanvasPanel.pxPerCm,
            (p[1] - r.y) * PlanCanvasPanel.pxPerCm,
          ),
      ];
      // ClipPath 将命中限制在多边形内（非 AABB 空角）
      content = ClipPath(
        clipper: _RoomPolygonClipper(localPts),
        child: gestures,
      );
    }

    return Positioned(
      left: r.x * PlanCanvasPanel.pxPerCm - padX,
      top: r.y * PlanCanvasPanel.pxPerCm - padY,
      width: hitW,
      height: hitH,
      child: Padding(
        padding: EdgeInsets.only(left: padX, top: padY),
        child: content,
      ),
    );
  }

  Future<void> _applyTemplate() async {
    final pick = await showPlanTemplateSheet(context);
    if (pick == null || pick is BlankPlanChoice) return;
    if (pick is! PlanDocument) return;
    if (!mounted) return;
    await applyCityFromSettings(pick);
    if (!mounted) return;
    _captureUndo();
    setState(() {
      plan.rooms
        ..clear()
        ..addAll(pick.rooms);
      plan.doors
        ..clear()
        ..addAll(pick.doors);
      plan.windows
        ..clear()
        ..addAll(pick.windows);
      plan.furniture.clear();
      plan.walls
        ..clear()
        ..addAll(pick.walls);
      plan.building.areaBuildM2 = pick.building.areaBuildM2;
      plan.building.roomCount = pick.building.roomCount;
      plan.building.bathroomCount = pick.building.bathroomCount;
      plan.building.cityName = pick.building.cityName;
      plan.building.cityTier = pick.building.cityTier;
      plan.building.cityTierSource = pick.building.cityTierSource;
      plan.meta.name = pick.meta.name;
      _selectedRoomId = null;
      _selectedWallId = null;
      _selectedDoorId = null;
      _selectedWindowId = null;
      _selectedFurnitureId = null;
      _draggingRoom = false;
      _resizingRoom = false;
      _dragOriginX = null;
      _dragOriginY = null;
      _sketchUnderlayPx = null;
      _strokePx.clear();
      _drawMode = false;
    });
    widget.onChanged();
  }

  /// I16 / R：选中房间的幽灵框、标注、8 缩放手柄或顶点手柄
  List<Widget> _selectedRoomChrome() {
    final r = _selectedRoom;
    if (r == null) return const [];
    const px = PlanCanvasPanel.pxPerCm;
    final out = <Widget>[];

    if (_draggingRoom && _dragOriginX != null && _dragOriginY != null) {
      out.add(
        Positioned(
          left: _dragOriginX! * px,
          top: _dragOriginY! * px,
          width: r.widthCm * px,
          height: r.depthCm * px,
          child: IgnorePointer(
            child: CustomPaint(
              painter: _DashedRectPainter(
                color: AppColors.textSecondary.withValues(alpha: 0.55),
              ),
            ),
          ),
        ),
      );
    }

    if (_draggingRoom || _resizingRoom || _draggingVertex) {
      final label = _draggingVertex && _dragVertexIndex != null
          ? '顶点 ${_dragVertexIndex! + 1}'
          : _resizingRoom
              ? '${AppConstants.formatMm(r.widthCm)}×${AppConstants.formatMm(r.depthCm)}mm'
              : (() {
                  final ox = _dragOriginX ?? r.x;
                  final oy = _dragOriginY ?? r.y;
                  final dx = (r.x - ox).round();
                  final dy = (r.y - oy).round();
                  return 'Δ ${AppConstants.formatMm(dx.toDouble())},${AppConstants.formatMm(dy.toDouble())} mm';
                })();
      out.add(
        Positioned(
          left: r.x * px,
          top: math.max(0.0, r.y * px - 22),
          child: IgnorePointer(
            child: Material(
              color: AppColors.surface.withValues(alpha: 0.92),
              elevation: 1,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // 期次 R：顶点编辑模式 → 顶点手柄；否则 AABB 8 手柄
    if (_vertexEditMode && r.hasPolygon) {
      final poly = r.polygon!;
      for (var i = 0; i < poly.length; i++) {
        final cx = poly[i][0] * px;
        final cy = poly[i][1] * px;
        out.add(_vertexHandle(r, i, cx, cy));
      }
      return out;
    }

    const handles = <(String, double, double)>[
      ('nw', 0, 0),
      ('n', 0.5, 0),
      ('ne', 1, 0),
      ('e', 1, 0.5),
      ('se', 1, 1),
      ('s', 0.5, 1),
      ('sw', 0, 1),
      ('w', 0, 0.5),
    ];
    for (final h in handles) {
      final cx = (r.x + r.widthCm * h.$2) * px;
      final cy = (r.y + r.depthCm * h.$3) * px;
      out.add(_resizeHandle(r, h.$1, cx, cy));
    }
    return out;
  }

  Widget _vertexHandle(RoomRect r, int index, double cx, double cy) {
    final half = _handleHitDp / 2;
    final visual = _vertexVisualDp;
    return Positioned(
      left: cx - half,
      top: cy - half,
      width: _handleHitDp,
      height: _handleHitDp,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {}, // 吞掉，避免点到空白取消选中
        onDoubleTap: () {
          if ((r.polygon?.length ?? 0) <= 3) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('至少保留 3 个顶点')),
            );
            return;
          }
          setState(() {
            r.removeVertex(index);
            plan.rebuildWallsFromRooms();
            _preserveOpeningsAfterRebuild();
            _dragVertexIndex = null;
            _draggingVertex = false;
          });
          widget.onChanged();
        },
        onPanStart: (_) => setState(() {
          _draggingVertex = true;
          _dragVertexIndex = index;
          _selectedWallId = null;
          _selectedDoorId = null;
          _selectedWindowId = null;
          _selectedFurnitureId = null;
        }),
        onPanUpdate: (d) {
          final scale =
              _transform.value.getMaxScaleOnAxis().clamp(0.01, 10.0);
          final dxCm = d.delta.dx / scale / PlanCanvasPanel.pxPerCm;
          final dyCm = d.delta.dy / scale / PlanCanvasPanel.pxPerCm;
          final poly = r.polygon;
          if (poly == null || index >= poly.length) return;
          setState(() {
            var nx = poly[index][0] + dxCm;
            var ny = poly[index][1] + dyCm;
            if (nx < 0) nx = 0;
            if (ny < 0) ny = 0;
            r.moveVertex(index, nx, ny);
          });
          widget.onChanged();
        },
        onPanEnd: (_) {
          setState(() {
            _draggingVertex = false;
            final poly = r.polygon;
            if (poly != null && index < poly.length) {
              r.moveVertex(
                index,
                _snap(poly[index][0]),
                _snap(poly[index][1]),
              );
            }
            _dragVertexIndex = null;
            plan.rebuildWallsFromRooms();
            _preserveOpeningsAfterRebuild();
          });
          widget.onChanged();
        },
        child: Center(
          child: Container(
            width: visual,
            height: visual,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.brand, width: 2),
            ),
          ),
        ),
      ),
    );
  }

  Widget _resizeHandle(RoomRect r, String corner, double cx, double cy) {
    final half = _handleHitDp / 2;
    final visual = _handleVisualDp;
    return Positioned(
      left: cx - half,
      top: cy - half,
      width: _handleHitDp,
      height: _handleHitDp,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => setState(() {
          _resizingRoom = true;
          _selectedWallId = null;
          _selectedDoorId = null;
          _selectedWindowId = null;
          _selectedFurnitureId = null;
        }),
        onPanUpdate: (d) {
          final scale =
              _transform.value.getMaxScaleOnAxis().clamp(0.01, 10.0);
          final dxCm = d.delta.dx / scale / PlanCanvasPanel.pxPerCm;
          final dyCm = d.delta.dy / scale / PlanCanvasPanel.pxPerCm;
          setState(() => _applyRoomResize(r, corner, dxCm, dyCm));
          widget.onChanged();
        },
        onPanEnd: (_) {
          setState(() {
            _resizingRoom = false;
            final sx = _snap(r.x);
            final sy = _snap(r.y);
            final sw = _snap(r.widthCm).clamp(_minRoomCm, 5000).toDouble();
            final sd = _snap(r.depthCm).clamp(_minRoomCm, 5000).toDouble();
            final nx = sx < 0 ? 0.0 : sx;
            final ny = sy < 0 ? 0.0 : sy;
            r.setAabbTransformingPolygon(nx, ny, sw, sd);
            plan.rebuildWallsFromRooms();
            _preserveOpeningsAfterRebuild();
          });
          widget.onChanged();
        },
        child: Center(
          child: Container(
            width: visual,
            height: visual,
            decoration: BoxDecoration(
              color: AppColors.brand,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
          ),
        ),
      ),
    );
  }

  /// 边中点：单轴；四角（nw/ne/sw/se）：面宽+进深随手指同时自由调整（非强制等比）。
  void _applyRoomResize(RoomRect r, String corner, double dxCm, double dyCm) {
    var x = r.x;
    var y = r.y;
    var w = r.widthCm;
    var d = r.depthCm;

    if (corner == 'nw') {
      x += dxCm;
      y += dyCm;
      w -= dxCm;
      d -= dyCm;
    } else if (corner == 'ne') {
      y += dyCm;
      w += dxCm;
      d -= dyCm;
    } else if (corner == 'se') {
      w += dxCm;
      d += dyCm;
    } else if (corner == 'sw') {
      x += dxCm;
      w -= dxCm;
      d += dyCm;
    } else if (corner == 'n') {
      y += dyCm;
      d -= dyCm;
    } else if (corner == 's') {
      d += dyCm;
    } else if (corner == 'e') {
      w += dxCm;
    } else if (corner == 'w') {
      x += dxCm;
      w -= dxCm;
    }

    if (w < _minRoomCm) {
      if (corner == 'nw' || corner == 'w' || corner == 'sw') {
        x = r.x + r.widthCm - _minRoomCm;
      }
      w = _minRoomCm;
    }
    if (d < _minRoomCm) {
      if (corner == 'nw' || corner == 'n' || corner == 'ne') {
        y = r.y + r.depthCm - _minRoomCm;
      }
      d = _minRoomCm;
    }
    if (x < 0) {
      w += x;
      x = 0;
      if (w < _minRoomCm) w = _minRoomCm;
    }
    if (y < 0) {
      d += y;
      y = 0;
      if (d < _minRoomCm) d = _minRoomCm;
    }

    r.setAabbTransformingPolygon(x, y, w, d);
  }

  List<Widget> _wallHitTargets() {
    if (plan.walls.isEmpty) {
      plan.rebuildWallsFromRooms();
    }
    return [
      for (final w in plan.walls)
        Positioned(
          left: (w.x1 < w.x2 ? w.x1 : w.x2) * PlanCanvasPanel.pxPerCm - 6,
          top: (w.y1 < w.y2 ? w.y1 : w.y2) * PlanCanvasPanel.pxPerCm - 6,
          width: ((w.x1 - w.x2).abs() * PlanCanvasPanel.pxPerCm).clamp(12, 2000) +
              12,
          height: ((w.y1 - w.y2).abs() * PlanCanvasPanel.pxPerCm).clamp(12, 2000) +
              12,
          child: GestureDetector(
            onTap: () => setState(() {
              _selectedWallId = w.id;
              _selectedRoomId = null;
              _selectedDoorId = null;
              _selectedWindowId = null;
              _selectedFurnitureId = null;
            }),
            child: Container(color: Colors.transparent),
          ),
        ),
    ];
  }

  /// I10.1 / I12：选中墙旁「+门洞」「+窗户」
  List<Widget> _selectedWallOpeningFabs() {
    final id = _selectedWallId;
    if (id == null || plan.rooms.isEmpty) return const [];
    final walls = plan.walls.where((w) => w.id == id);
    if (walls.isEmpty) return const [];
    final w = walls.first;
    final mid = Offset(
      (w.x1 + w.x2) / 2 * PlanCanvasPanel.pxPerCm,
      (w.y1 + w.y2) / 2 * PlanCanvasPanel.pxPerCm,
    );
    final len = _wallLen(w);
    final ux = (w.x2 - w.x1) / len;
    final uy = (w.y2 - w.y1) / len;
    var nx = -uy;
    var ny = ux;
    final room = _roomForWall(w);
    if (room != null) {
      final rcx = (room.x + room.widthCm / 2) * PlanCanvasPanel.pxPerCm;
      final rcy = (room.y + room.depthCm / 2) * PlanCanvasPanel.pxPerCm;
      if (nx * (rcx - mid.dx) + ny * (rcy - mid.dy) < 0) {
        nx = -nx;
        ny = -ny;
      }
    }
    const offset = 36.0;
    const along = 48.0;
    final doorLeft = mid.dx + nx * offset - ux * along / 2 - 22;
    final doorTop = mid.dy + ny * offset - uy * along / 2 - 22;
    final winLeft = mid.dx + nx * offset + ux * along / 2 - 22;
    final winTop = mid.dy + ny * offset + uy * along / 2 - 22;
    return [
      Positioned(
        left: doorLeft,
        top: doorTop,
        child: Material(
          color: AppColors.surface,
          elevation: 3,
          shape: const CircleBorder(),
          child: IconButton(
            tooltip: '+门洞',
            iconSize: 22,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            onPressed: _addDoorOnSelectedWall,
            icon: const Icon(Icons.door_front_door),
            color: AppColors.brand,
          ),
        ),
      ),
      Positioned(
        left: winLeft,
        top: winTop,
        child: Material(
          color: AppColors.surface,
          elevation: 3,
          shape: const CircleBorder(),
          child: IconButton(
            tooltip: '+窗户',
            iconSize: 22,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            onPressed: _addWindowOnSelectedWall,
            icon: const Icon(Icons.window),
            color: AppColors.accent,
          ),
        ),
      ),
    ];
  }

  /// I10.2：门洞命中区（拖沿墙调位置）；符号由 Painter 绘制
  Widget _doorHitTarget(DoorOpening d) {
    final wall = plan.walls.where((w) => w.id == d.wallId);
    if (wall.isEmpty) return const SizedBox.shrink();
    final w = wall.first;
    final len = _wallLen(w);
    final t = (d.centerCm / len).clamp(0.05, 0.95);
    final cx = (w.x1 + (w.x2 - w.x1) * t) * PlanCanvasPanel.pxPerCm;
    final cy = (w.y1 + (w.y2 - w.y1) * t) * PlanCanvasPanel.pxPerCm;
    final hit = math.max(
      d.widthCm * PlanCanvasPanel.pxPerCm + 16,
      PlanCanvasPanel.minHitDp,
    );
    final selected = _selectedDoorId == d.id;
    return Positioned(
      left: cx - hit / 2,
      top: cy - hit / 2,
      width: hit,
      height: hit,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          _selectedDoorId = d.id;
          _selectedWallId = d.wallId;
          _selectedRoomId = null;
          _selectedWindowId = null;
          _selectedFurnitureId = null;
        }),
        onPanStart: (_) => setState(() {
          _draggingDoor = true;
          _selectedDoorId = d.id;
          _selectedWallId = d.wallId;
          _selectedRoomId = null;
          _selectedWindowId = null;
          _selectedFurnitureId = null;
        }),
        onPanUpdate: (details) {
          final scale = _transform.value.getMaxScaleOnAxis().clamp(0.01, 10.0);
          final lenNow = _wallLen(w);
          final tNow = (d.centerCm / lenNow).clamp(0.05, 0.95);
          final cur = Offset(
            (w.x1 + (w.x2 - w.x1) * tNow) * PlanCanvasPanel.pxPerCm,
            (w.y1 + (w.y2 - w.y1) * tNow) * PlanCanvasPanel.pxPerCm,
          );
          _moveDoorAlongWall(d, w, cur + details.delta / scale);
          widget.onChanged();
        },
        onPanEnd: (_) {
          setState(() {
            _draggingDoor = false;
            d.centerCm = _snap(d.centerCm).clamp(
              d.widthCm / 2 + 10,
              len - d.widthCm / 2 - 10,
            );
          });
          widget.onChanged();
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: selected
                ? Border.all(color: AppColors.brand.withValues(alpha: 0.45), width: 1.5)
                : null,
          ),
        ),
      ),
    );
  }

  /// I12：窗户命中区（拖沿墙调位置）；符号由 Painter 绘制
  Widget _windowHitTarget(WindowOpening win) {
    final wall = plan.walls.where((w) => w.id == win.wallId);
    if (wall.isEmpty) return const SizedBox.shrink();
    final w = wall.first;
    final len = _wallLen(w);
    final t = (win.centerCm / len).clamp(0.05, 0.95);
    final cx = (w.x1 + (w.x2 - w.x1) * t) * PlanCanvasPanel.pxPerCm;
    final cy = (w.y1 + (w.y2 - w.y1) * t) * PlanCanvasPanel.pxPerCm;
    final hit = math.max(
      win.widthCm * PlanCanvasPanel.pxPerCm + 16,
      PlanCanvasPanel.minHitDp,
    );
    final selected = _selectedWindowId == win.id;
    return Positioned(
      left: cx - hit / 2,
      top: cy - hit / 2,
      width: hit,
      height: hit,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          _selectedWindowId = win.id;
          _selectedWallId = win.wallId;
          _selectedRoomId = null;
          _selectedDoorId = null;
          _selectedFurnitureId = null;
        }),
        onPanStart: (_) => setState(() {
          _draggingWindow = true;
          _selectedWindowId = win.id;
          _selectedWallId = win.wallId;
          _selectedRoomId = null;
          _selectedDoorId = null;
          _selectedFurnitureId = null;
        }),
        onPanUpdate: (details) {
          final scale = _transform.value.getMaxScaleOnAxis().clamp(0.01, 10.0);
          final lenNow = _wallLen(w);
          final tNow = (win.centerCm / lenNow).clamp(0.05, 0.95);
          final cur = Offset(
            (w.x1 + (w.x2 - w.x1) * tNow) * PlanCanvasPanel.pxPerCm,
            (w.y1 + (w.y2 - w.y1) * tNow) * PlanCanvasPanel.pxPerCm,
          );
          _moveWindowAlongWall(win, w, cur + details.delta / scale);
          widget.onChanged();
        },
        onPanEnd: (_) {
          setState(() {
            _draggingWindow = false;
            win.centerCm = _snap(win.centerCm).clamp(
              win.widthCm / 2 + 10,
              len - win.widthCm / 2 - 10,
            );
          });
          widget.onChanged();
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: selected
                ? Border.all(
                    color: AppColors.accent.withValues(alpha: 0.45),
                    width: 1.5,
                  )
                : null,
          ),
        ),
      ),
    );
  }

  void _moveDoorAlongWall(DoorOpening d, WallSeg w, Offset localPx) {
    final len = _wallLen(w);
    final ax = w.x1 * PlanCanvasPanel.pxPerCm;
    final ay = w.y1 * PlanCanvasPanel.pxPerCm;
    final bx = w.x2 * PlanCanvasPanel.pxPerCm;
    final by = w.y2 * PlanCanvasPanel.pxPerCm;
    final abx = bx - ax;
    final aby = by - ay;
    final abLen2 = abx * abx + aby * aby;
    if (abLen2 <= 0) return;
    final t = ((localPx.dx - ax) * abx + (localPx.dy - ay) * aby) / abLen2;
    final centerCm = (t.clamp(0.0, 1.0) * len);
    final half = d.widthCm / 2;
    setState(() {
      d.centerCm = centerCm.clamp(half + 10, len - half - 10);
    });
  }

  void _moveWindowAlongWall(WindowOpening win, WallSeg w, Offset localPx) {
    final len = _wallLen(w);
    final ax = w.x1 * PlanCanvasPanel.pxPerCm;
    final ay = w.y1 * PlanCanvasPanel.pxPerCm;
    final bx = w.x2 * PlanCanvasPanel.pxPerCm;
    final by = w.y2 * PlanCanvasPanel.pxPerCm;
    final abx = bx - ax;
    final aby = by - ay;
    final abLen2 = abx * abx + aby * aby;
    if (abLen2 <= 0) return;
    final t = ((localPx.dx - ax) * abx + (localPx.dy - ay) * aby) / abLen2;
    final centerCm = (t.clamp(0.0, 1.0) * len);
    final half = win.widthCm / 2;
    setState(() {
      win.centerCm = centerCm.clamp(half + 10, len - half - 10);
    });
  }

  RoomRect? _roomForWall(WallSeg w) {
    RoomRect? best;
    var bestDist = double.infinity;
    final mx = (w.x1 + w.x2) / 2;
    final my = (w.y1 + w.y2) / 2;
    for (final r in plan.rooms) {
      if (!_wallTouchesRoom(w, r)) continue;
      final cx = r.x + r.widthCm / 2;
      final cy = r.y + r.depthCm / 2;
      final dist = (mx - cx) * (mx - cx) + (my - cy) * (my - cy);
      if (dist < bestDist) {
        bestDist = dist;
        best = r;
      }
    }
    if (best != null) return best;
    for (final r in plan.rooms) {
      final cx = r.x + r.widthCm / 2;
      final cy = r.y + r.depthCm / 2;
      final dist = (mx - cx) * (mx - cx) + (my - cy) * (my - cy);
      if (dist < bestDist) {
        bestDist = dist;
        best = r;
      }
    }
    return best;
  }

  void _addDoorOnSelectedWall() {
    final id = _selectedWallId;
    if (id == null || plan.rooms.isEmpty) return;
    if (plan.walls.isEmpty) plan.rebuildWallsFromRooms();
    final walls = plan.walls.where((w) => w.id == id);
    if (walls.isEmpty) return;
    final w = walls.first;
    final room = _roomForWall(w) ?? plan.rooms.first;
    final len = _wallLen(w);
    final half = AppConstants.defaultDoorWidthCm / 2;
    final door = DoorOpening(
      id: 'door_${const Uuid().v4().substring(0, 6)}',
      roomId: room.id,
      wallId: w.id,
      centerCm: _snap(len / 2).clamp(half + 10, len - half - 10),
      widthCm: AppConstants.defaultDoorWidthCm,
      positionType: 'I',
      doorType: 'swing',
    );
    _captureUndo();
    setState(() {
      plan.doors.add(door);
      _selectedDoorId = door.id;
      _selectedWindowId = null;
      _selectedFurnitureId = null;
      _openingsExpanded = true;
    });
    widget.onChanged();
  }

  void _addWindowOnSelectedWall() {
    final id = _selectedWallId;
    if (id == null || plan.rooms.isEmpty) return;
    if (plan.walls.isEmpty) plan.rebuildWallsFromRooms();
    final walls = plan.walls.where((w) => w.id == id);
    if (walls.isEmpty) return;
    final w = walls.first;
    final room = _roomForWall(w) ?? plan.rooms.first;
    final len = _wallLen(w);
    final half = AppConstants.defaultWindowWidthCm / 2;
    final win = WindowOpening(
      id: 'win_${const Uuid().v4().substring(0, 6)}',
      roomId: room.id,
      wallId: w.id,
      centerCm: _snap(len / 2).clamp(half + 10, len - half - 10),
      widthCm: AppConstants.defaultWindowWidthCm,
      heightCm: AppConstants.defaultWindowHeightCm,
      sillCm: AppConstants.defaultWindowSillCm,
      type: 'normal',
    );
    _captureUndo();
    setState(() {
      plan.windows.add(win);
      _selectedWindowId = win.id;
      _selectedDoorId = null;
      _selectedFurnitureId = null;
      _openingsExpanded = true;
    });
    widget.onChanged();
  }

  double _wallLen(WallSeg w) {
    final dx = w.x2 - w.x1;
    final dy = w.y2 - w.y1;
    final len = (dx * dx + dy * dy);
    return len <= 0 ? 1 : math.sqrt(len);
  }

  bool _isSelectedWallBearing() {
    final id = _selectedWallId;
    if (id == null) return false;
    return plan.constraints
        .any((c) => c.type == 'load_bearing' && c.wallId == id);
  }

  void _toggleLoadBearing() {
    final id = _selectedWallId;
    if (id == null) return;
    setState(() {
      final existing = plan.constraints
          .where((c) => c.type == 'load_bearing' && c.wallId == id)
          .toList();
      if (existing.isNotEmpty) {
        plan.constraints.removeWhere((c) => existing.contains(c));
      } else {
        plan.constraints.add(
          ConstraintMark(
            id: 'c_${const Uuid().v4().substring(0, 6)}',
            type: 'load_bearing',
            wallId: id,
            note: '用户标记承重',
          ),
        );
      }
    });
    widget.onChanged();
  }

  /// Y2：把附近平行双墙贴到选中墙上并重建（持久化靠贴齐房间边）。
  void _mergeSelectedWallWithNearby() {
    final id = _selectedWallId;
    if (id == null) return;
    final walls = plan.walls.where((w) => w.id == id);
    if (walls.isEmpty) return;
    final target = walls.first;
    const searchTol = 15.0; // cm，查找双墙
    final nearby = plan.walls
        .where((o) => o.id != target.id && _areParallelNearWalls(target, o, searchTol))
        .toList();
    if (nearby.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('附近未发现可合并的平行墙')),
      );
      return;
    }
    _captureUndo();
    setState(() {
      final lines = [target, ...nearby];
      _snapRoomEdgesToLine(target, lines, searchTol + 2);
      plan.rebuildWallsFromRooms();
      _preserveOpeningsAfterRebuild();
      _selectedWallId = null;
    });
    widget.onChanged();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已合并 ${nearby.length + 1} 段近墙为共墙')),
    );
  }

  /// Y2：选中墙拆为通口（大开口，保留墙网可编辑）。
  void _openSelectedWallAsPassage() {
    final id = _selectedWallId;
    if (id == null || plan.rooms.isEmpty) return;
    final walls = plan.walls.where((w) => w.id == id);
    if (walls.isEmpty) return;
    final w = walls.first;
    final len = _wallLen(w);
    if (len < 80) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('墙段过短，无法拆为通口')),
      );
      return;
    }
    final width = math.min(len - 20, len * 0.92).clamp(60.0, len - 10);
    final center = len / 2;
    // 已有近似通口则提示
    final exists = plan.doors.any(
      (d) =>
          d.wallId == id &&
          d.widthCm >= width * 0.7 &&
          (d.centerCm - center).abs() < width * 0.3,
    );
    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该墙已有较大开口')),
      );
      return;
    }
    _captureUndo();
    final roomId = _roomForWall(w)?.id ?? plan.rooms.first.id;
    setState(() {
      plan.doors.add(
        DoorOpening(
          id: 'pass_${const Uuid().v4().substring(0, 6)}',
          roomId: roomId,
          wallId: w.id,
          centerCm: center,
          widthCm: width,
          positionType: 'II',
          doorType: 'sliding',
        ),
      );
      _openingsExpanded = true;
      _selectedDoorId = plan.doors.last.id;
    });
    widget.onChanged();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已拆为通口，可在列表改宽或删除')),
    );
  }

  bool _areParallelNearWalls(WallSeg a, WallSeg b, double tolCm) {
    final adx = a.x2 - a.x1;
    final ady = a.y2 - a.y1;
    final bdx = b.x2 - b.x1;
    final bdy = b.y2 - b.y1;
    final aLen = math.sqrt(adx * adx + ady * ady);
    final bLen = math.sqrt(bdx * bdx + bdy * bdy);
    if (aLen < 1 || bLen < 1) return false;
    final aHoriz = adx.abs() >= ady.abs();
    final bHoriz = bdx.abs() >= bdy.abs();
    if (aHoriz != bHoriz) return false;
    if (aHoriz) {
      final dy = ((a.y1 + a.y2) / 2 - (b.y1 + b.y2) / 2).abs();
      if (dy > tolCm) return false;
      final aMin = math.min(a.x1, a.x2);
      final aMax = math.max(a.x1, a.x2);
      final bMin = math.min(b.x1, b.x2);
      final bMax = math.max(b.x1, b.x2);
      return !(aMax < bMin - tolCm || bMax < aMin - tolCm);
    }
    final dx = ((a.x1 + a.x2) / 2 - (b.x1 + b.x2) / 2).abs();
    if (dx > tolCm) return false;
    final aMin = math.min(a.y1, a.y2);
    final aMax = math.max(a.y1, a.y2);
    final bMin = math.min(b.y1, b.y2);
    final bMax = math.max(b.y1, b.y2);
    return !(aMax < bMin - tolCm || bMax < aMin - tolCm);
  }

  /// 将靠近参考线的房间顶点/边贴到 target 墙所在直线。
  void _snapRoomEdgesToLine(
    WallSeg target,
    List<WallSeg> refs,
    double tolCm,
  ) {
    final tdx = target.x2 - target.x1;
    final tdy = target.y2 - target.y1;
    final horiz = tdx.abs() >= tdy.abs();
    final lineCoord = horiz
        ? (target.y1 + target.y2) / 2
        : (target.x1 + target.x2) / 2;

    for (final r in plan.rooms) {
      r.ensurePolygonFromRect();
      final poly = r.polygon;
      if (poly == null) continue;
      var changed = false;
      for (final p in poly) {
        if (p.length < 2) continue;
        final d = horiz ? (p[1] - lineCoord).abs() : (p[0] - lineCoord).abs();
        if (d > tolCm) continue;
        // 仅贴靠近任一参考墙投影范围的点
        var nearSeg = false;
        for (final ref in refs) {
          if (horiz) {
            final lo = math.min(ref.x1, ref.x2) - tolCm;
            final hi = math.max(ref.x1, ref.x2) + tolCm;
            if (p[0] >= lo && p[0] <= hi) nearSeg = true;
          } else {
            final lo = math.min(ref.y1, ref.y2) - tolCm;
            final hi = math.max(ref.y1, ref.y2) + tolCm;
            if (p[1] >= lo && p[1] <= hi) nearSeg = true;
          }
        }
        if (!nearSeg) continue;
        if (horiz) {
          p[1] = lineCoord;
        } else {
          p[0] = lineCoord;
        }
        changed = true;
      }
      if (changed) r.syncAabbFromPolygon();
    }
  }

  Future<void> _addRoom() async {
    final type = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final e in RoomTypeLabels.labels.entries)
              ListTile(
                title: Text(e.value),
                onTap: () => Navigator.pop(ctx, e.key),
              ),
          ],
        ),
      ),
    );
    if (type == null) return;
    final idx = plan.rooms.length;
    final id = 'room_${const Uuid().v4().substring(0, 6)}';
    _captureUndo();
    setState(() {
      _drawMode = false;
      plan.rooms.add(
        RoomRect(
          id: id,
          name: RoomTypeLabels.labels[type] ?? '房间',
          type: type,
          x: _snap(80.0 + (idx % 3) * 320),
          y: _snap(80.0 + (idx ~/ 3) * 280),
          widthCm: type == 'living' ? 420 : 300,
          depthCm: type == 'living' ? 400 : 320,
          hasStorageZone: type == 'bedroom_master' || type == 'entry',
        ),
      );
      plan.rebuildWallsFromRooms();
      _selectedRoomId = id;
      _selectedFurnitureId = null;
      _selectedDoorId = null;
      _selectedWindowId = null;
      if (type != 'bath') {
        final wallId = plan.walls.isNotEmpty ? plan.walls.first.id : null;
        plan.doors.add(
          DoorOpening(
            id: 'door_${const Uuid().v4().substring(0, 6)}',
            roomId: id,
            wallId: wallId,
            centerCm: 100,
            widthCm: AppConstants.defaultDoorWidthCm,
            positionType: 'I',
            doorType: 'swing',
          ),
        );
        _snapDoorToNearestWall(plan.doors.last);
      }
    });
    widget.onChanged();
  }

  Future<void> _addDoorOnWall() async {
    final room = await showModalBottomSheet<RoomRect>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('选择房间')),
            for (final r in plan.rooms)
              ListTile(
                title: Text(r.name),
                onTap: () => Navigator.pop(ctx, r),
              ),
          ],
        ),
      ),
    );
    if (room == null) return;
    plan.rebuildWallsFromRooms();
    final door = DoorOpening(
      id: 'door_${const Uuid().v4().substring(0, 6)}',
      roomId: room.id,
      widthCm: AppConstants.defaultDoorWidthCm,
      positionType: 'I',
      doorType: 'swing',
      centerCm: room.widthCm / 2,
    );
    _captureUndo();
    setState(() {
      plan.doors.add(door);
      _snapDoorToNearestWall(door);
      _selectedDoorId = door.id;
      _selectedWindowId = null;
      _selectedFurnitureId = null;
      _openingsExpanded = true;
    });
    widget.onChanged();
  }

  Future<void> _addWindowOnWall() async {
    final room = await showModalBottomSheet<RoomRect>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('选择房间')),
            for (final r in plan.rooms)
              ListTile(
                title: Text(r.name),
                onTap: () => Navigator.pop(ctx, r),
              ),
          ],
        ),
      ),
    );
    if (room == null) return;
    plan.rebuildWallsFromRooms();
    final win = WindowOpening(
      id: 'win_${const Uuid().v4().substring(0, 6)}',
      roomId: room.id,
      widthCm: AppConstants.defaultWindowWidthCm,
      heightCm: AppConstants.defaultWindowHeightCm,
      sillCm: AppConstants.defaultWindowSillCm,
      type: 'normal',
      centerCm: room.widthCm / 2,
    );
    _captureUndo();
    setState(() {
      plan.windows.add(win);
      _snapWindowToNearestWall(win);
      _selectedWindowId = win.id;
      _selectedDoorId = null;
      _selectedFurnitureId = null;
      _openingsExpanded = true;
    });
    widget.onChanged();
  }

  Future<void> _openFurnitureCatalog() async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('选择家具')),
            for (final m in SceneCatalog.modules())
              ListTile(
                title: Text(m['name'] as String? ?? m['sku_id'] as String),
                subtitle: Text(
                  '${AppConstants.formatMm((m['width_cm'] as num).toDouble())}×'
                  '${AppConstants.formatMm((m['depth_cm'] as num).toDouble())}×'
                  '${AppConstants.formatMm((m['height_cm'] as num).toDouble())} mm',
                ),
                onTap: () => Navigator.pop(ctx, m),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final room = _selectedRoom ?? (plan.rooms.isNotEmpty ? plan.rooms.first : null);
    if (room == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先添加房间')),
      );
      return;
    }
    final sku = picked['sku_id'] as String? ?? 'furn_sofa';
    final item = FurnitureItem(
      id: 'furn_${const Uuid().v4().substring(0, 6)}',
      type: sku,
      roomId: room.id,
      x: room.x + room.widthCm / 2,
      y: room.y + room.depthCm / 2,
      rotation: 0,
      widthCm: (picked['width_cm'] as num?)?.toDouble() ?? 100,
      depthCm: (picked['depth_cm'] as num?)?.toDouble() ?? 60,
      heightCm: (picked['height_cm'] as num?)?.toDouble() ?? 80,
    );
    _constrainFurnitureInRoom(item);
    _captureUndo();
    setState(() {
      plan.furniture.add(item);
      _selectedFurnitureId = item.id;
      _selectedRoomId = null;
      _selectedWallId = null;
      _selectedDoorId = null;
      _selectedWindowId = null;
    });
    widget.onChanged();
  }

  FurnitureItem? get _selectedFurniture {
    final id = _selectedFurnitureId;
    if (id == null) return null;
    for (final f in plan.furniture) {
      if (f.id == id) return f;
    }
    return null;
  }

  RoomRect? _roomById(String id) {
    for (final r in plan.rooms) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// 按旋转后的包围盒，把家具中心粗略限制在所属房间内
  void _constrainFurnitureInRoom(FurnitureItem f) {
    final room = _roomById(f.roomId);
    if (room == null) return;
    final rot = ((f.rotation % 180) + 180) % 180;
    final swapped = rot > 45 && rot < 135;
    final halfW = (swapped ? f.depthCm : f.widthCm) / 2;
    final halfD = (swapped ? f.widthCm : f.depthCm) / 2;
    final minX = room.x + halfW;
    final maxX = room.x + room.widthCm - halfW;
    final minY = room.y + halfD;
    final maxY = room.y + room.depthCm - halfD;
    if (maxX >= minX) {
      f.x = f.x.clamp(minX, maxX);
    } else {
      f.x = room.x + room.widthCm / 2;
    }
    if (maxY >= minY) {
      f.y = f.y.clamp(minY, maxY);
    } else {
      f.y = room.y + room.depthCm / 2;
    }
  }

  Widget _furnitureWidget(FurnitureItem f) {
    final selected = _selectedFurnitureId == f.id;
    final w = math.max(f.widthCm * PlanCanvasPanel.pxPerCm, 28.0);
    final h = math.max(f.depthCm * PlanCanvasPanel.pxPerCm, 28.0);
    final cx = f.x * PlanCanvasPanel.pxPerCm;
    final cy = f.y * PlanCanvasPanel.pxPerCm;
    final label = SceneCatalog.labelOf(f.type);
    return Positioned(
      left: cx - w / 2,
      top: cy - h / 2,
      width: w,
      height: h,
      child: Transform.rotate(
        angle: f.rotation * math.pi / 180,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() {
            _selectedFurnitureId = f.id;
            _selectedRoomId = null;
            _selectedWallId = null;
            _selectedDoorId = null;
            _selectedWindowId = null;
          }),
          onPanStart: selected
              ? (_) => setState(() {
                    _draggingFurniture = true;
                    _selectedFurnitureId = f.id;
                    _selectedRoomId = null;
                    _selectedWallId = null;
                    _selectedDoorId = null;
                    _selectedWindowId = null;
                  })
              : null,
          onPanUpdate: selected
              ? (d) {
                  setState(() {
                    f.x += d.delta.dx / PlanCanvasPanel.pxPerCm;
                    f.y += d.delta.dy / PlanCanvasPanel.pxPerCm;
                    _constrainFurnitureInRoom(f);
                  });
                  widget.onChanged();
                }
              : null,
          onPanEnd: selected
              ? (_) {
                  setState(() {
                    _draggingFurniture = false;
                    f.x = _snap(f.x);
                    f.y = _snap(f.y);
                    _constrainFurnitureInRoom(f);
                  });
                  widget.onChanged();
                }
              : null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.brandSoft,
              border: Border.all(
                color: AppColors.brand,
                width: selected ? 2.5 : 1.2,
              ),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textPrimary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _selectedFurnitureActionBar() {
    final f = _selectedFurniture;
    if (f == null) return const [];
    final cx = f.x * PlanCanvasPanel.pxPerCm;
    final cy = f.y * PlanCanvasPanel.pxPerCm;
    final halfH = math.max(f.depthCm, f.widthCm) * PlanCanvasPanel.pxPerCm / 2;
    final left = (cx - 72).clamp(4.0, 900.0 - 152);
    final top = (cy - halfH - 48).clamp(4.0, 700.0 - 48);
    return [
      Positioned(
        left: left,
        top: top,
        child: Material(
          color: AppColors.surface,
          elevation: 3,
          borderRadius: BorderRadius.circular(8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '旋转',
                iconSize: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                onPressed: () {
                  setState(() {
                    f.rotation = (f.rotation + 90) % 360;
                    _constrainFurnitureInRoom(f);
                  });
                  widget.onChanged();
                },
                icon: const Icon(Icons.rotate_right),
                color: AppColors.brand,
              ),
              IconButton(
                tooltip: '改尺寸',
                iconSize: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                onPressed: () => _editFurnitureSize(f),
                icon: const Icon(Icons.straighten),
                color: AppColors.brand,
              ),
              IconButton(
                tooltip: '删除',
                iconSize: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                onPressed: () {
                  _captureUndo();
                  setState(() {
                    plan.furniture.removeWhere((e) => e.id == f.id);
                    _selectedFurnitureId = null;
                    _draggingFurniture = false;
                  });
                  widget.onChanged();
                },
                icon: const Icon(Icons.delete_outline),
                color: AppColors.danger,
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Future<void> _editFurnitureSize(FurnitureItem f) async {
    final wCtrl = TextEditingController(text: AppConstants.formatMm(f.widthCm));
    final dCtrl = TextEditingController(text: AppConstants.formatMm(f.depthCm));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('改尺寸 · ${SceneCatalog.labelOf(f.type)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: wCtrl,
              decoration: const InputDecoration(labelText: '面宽 mm'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: dCtrl,
              decoration: const InputDecoration(labelText: '进深 mm'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        f.widthCm = _snap(
          AppConstants.mmToCm(double.tryParse(wCtrl.text) ?? f.widthCm * 10),
        ).clamp(20, 600);
        f.depthCm = _snap(
          AppConstants.mmToCm(double.tryParse(dCtrl.text) ?? f.depthCm * 10),
        ).clamp(20, 600);
        _constrainFurnitureInRoom(f);
      });
      widget.onChanged();
    }
    wCtrl.dispose();
    dCtrl.dispose();
  }

  Future<void> _editRoom(RoomRect r) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final wCtrl = TextEditingController(text: AppConstants.formatMm(r.widthCm));
    final dCtrl = TextEditingController(text: AppConstants.formatMm(r.depthCm));
    var storage = r.hasStorageZone;
    // 弹窗内只 pop(result)，不在 onPressed 里 setState；关闭后再应用
    final result = await showDialog<({double w, double d, bool storage})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('编辑 ${r.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: wCtrl,
                decoration: const InputDecoration(labelText: '面宽 mm'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: dCtrl,
                decoration: const InputDecoration(labelText: '进深 mm'),
                keyboardType: TextInputType.number,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('已有收纳区'),
                value: storage,
                onChanged: (v) => setLocal(() => storage = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                FocusManager.instance.primaryFocus?.unfocus();
                Navigator.pop(ctx);
              },
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                FocusManager.instance.primaryFocus?.unfocus();
                final w = AppConstants.mmToCm(
                  double.tryParse(wCtrl.text) ?? r.widthCm * 10,
                );
                final d = AppConstants.mmToCm(
                  double.tryParse(dCtrl.text) ?? r.depthCm * 10,
                );
                Navigator.pop(ctx, (w: w, d: d, storage: storage));
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
    FocusManager.instance.primaryFocus?.unfocus();
    // 先读值再 dispose，避免 focus 仍挂在已 dispose 的 controller 上
    final applied = result;
    wCtrl.dispose();
    dCtrl.dispose();
    if (applied == null || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        final nw = _snap(applied.w);
        final nd = _snap(applied.d);
        r.setAabbTransformingPolygon(
          r.x,
          r.y,
          nw < _minRoomCm ? _minRoomCm : nw,
          nd < _minRoomCm ? _minRoomCm : nd,
        );
        r.hasStorageZone = applied.storage;
        plan.rebuildWallsFromRooms();
        _preserveOpeningsAfterRebuild();
      });
      widget.onChanged();
    });
  }

  Future<void> _chamferSelectedRoom() async {
    final r = _selectedRoom;
    if (r == null) return;
    r.ensurePolygonFromRect();
    final n = r.polygon!.length;
    final labels = <String>[
      for (var i = 0; i < n; i++)
        n == 4
            ? const ['左上', '右上', '右下', '左下'][i]
            : '顶点 ${i + 1}',
    ];
    var cut = _defaultChamferCm;
    final maxCut = math.max(40.0, math.min(200.0, math.min(r.widthCm, r.depthCm) / 2));
    if (cut > maxCut) cut = maxCut;
    var corner = 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('切角'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('选择角落，沿两边各切一段（适合 L 形起步）'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < n; i++)
                    ChoiceChip(
                      label: Text(labels[i]),
                      selected: corner == i,
                      onSelected: (_) => setLocal(() => corner = i),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text('切角边长 ${AppConstants.formatMm(cut)} mm'),
              Slider(
                value: cut,
                min: 40,
                max: maxCut,
                divisions: 16,
                label: '${AppConstants.formatMm(cut)} mm',
                onChanged: (v) => setLocal(() => cut = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('切角'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    _captureUndo();
    final done = r.chamferVertex(corner, cut);
    if (!done) {
      _undoSnapshot = null;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('切角失败：边太短，请减小切角边长')),
      );
      return;
    }
    setState(() {
      _vertexEditMode = true;
      plan.rebuildWallsFromRooms();
      _preserveOpeningsAfterRebuild();
    });
    widget.onChanged();
  }

  /// 墙网重建后：按开口原世界坐标重挂最近异形边，并尽量保留沿墙参数。
  void _preserveOpeningsAfterRebuild() {
    for (final d in plan.doors) {
      _resnapOpeningToNearestEdge(
        roomId: d.roomId,
        wallIdSetter: (id) => d.wallId = id,
        centerSetter: (c) => d.centerCm = c,
        halfWidth: d.widthCm / 2,
        previousWallId: d.wallId,
        previousCenter: d.centerCm,
      );
    }
    for (final w in plan.windows) {
      _resnapOpeningToNearestEdge(
        roomId: w.roomId,
        wallIdSetter: (id) => w.wallId = id,
        centerSetter: (c) => w.centerCm = c,
        halfWidth: w.widthCm / 2,
        previousWallId: w.wallId,
        previousCenter: w.centerCm,
      );
    }
  }

  void _resnapOpeningToNearestEdge({
    required String roomId,
    required void Function(String id) wallIdSetter,
    required void Function(double c) centerSetter,
    required double halfWidth,
    String? previousWallId,
    required double previousCenter,
  }) {
    final rooms = plan.rooms.where((r) => r.id == roomId);
    if (rooms.isEmpty || plan.walls.isEmpty) return;
    final room = rooms.first;

    WallSeg? best;
    var bestDist = double.infinity;
    var bestT = 0.5;
    for (final w in plan.walls) {
      if (!_wallTouchesRoom(w, room)) continue;
      final len = _wallLen(w);
      final tPrefer = previousCenter / (len <= 0 ? 1 : len);
      final t = tPrefer.clamp(0.15, 0.85);
      final px = w.x1 + (w.x2 - w.x1) * t;
      final py = w.y1 + (w.y2 - w.y1) * t;
      final dist = room.minDistanceToEdges(px, py);
      final score = dist + (previousWallId == w.id ? 0 : 0.01);
      if (score < bestDist) {
        bestDist = score;
        best = w;
        bestT = t;
      }
    }
    if (best == null) {
      for (final w in plan.walls) {
        final mx = (w.x1 + w.x2) / 2;
        final my = (w.y1 + w.y2) / 2;
        final dist = room.minDistanceToEdges(mx, my);
        if (dist < bestDist) {
          bestDist = dist;
          best = w;
          bestT = 0.5;
        }
      }
    }
    if (best == null) return;
    final len = _wallLen(best);
    wallIdSetter(best.id);
    final center =
        _snap(bestT * len).clamp(halfWidth + 10, len - halfWidth - 10);
    centerSetter(center.toDouble());
  }

  void _snapDoorToNearestWall(DoorOpening door) {
    _resnapOpeningToNearestEdge(
      roomId: door.roomId,
      wallIdSetter: (id) => door.wallId = id,
      centerSetter: (c) => door.centerCm = c,
      halfWidth: door.widthCm / 2,
      previousWallId: door.wallId,
      previousCenter: door.centerCm,
    );
  }

  void _snapWindowToNearestWall(WindowOpening win) {
    _resnapOpeningToNearestEdge(
      roomId: win.roomId,
      wallIdSetter: (id) => win.wallId = id,
      centerSetter: (c) => win.centerCm = c,
      halfWidth: win.widthCm / 2,
      previousWallId: win.wallId,
      previousCenter: win.centerCm,
    );
  }

  bool _wallTouchesRoom(WallSeg w, RoomRect r) {
    return r.wallTouchesByEdges(w.x1, w.y1, w.x2, w.y2, tol: 18);
  }
}
class _DashedRectPainter extends CustomPainter {
  _DashedRectPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    const dash = 6.0;
    const gap = 4.0;
    void dashLine(Offset a, Offset b) {
      final dx = b.dx - a.dx;
      final dy = b.dy - a.dy;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len < 1) return;
      final ux = dx / len;
      final uy = dy / len;
      var t = 0.0;
      while (t < len) {
        final t1 = math.min(t + dash, len);
        canvas.drawLine(
          Offset(a.dx + ux * t, a.dy + uy * t),
          Offset(a.dx + ux * t1, a.dy + uy * t1),
          paint,
        );
        t += dash + gap;
      }
    }

    final rect = Offset.zero & size;
    dashLine(rect.topLeft, rect.topRight);
    dashLine(rect.topRight, rect.bottomRight);
    dashLine(rect.bottomRight, rect.bottomLeft);
    dashLine(rect.bottomLeft, rect.topLeft);
    canvas.drawRect(
      rect,
      Paint()..color = color.withValues(alpha: 0.08),
    );
  }

  @override
  bool shouldRepaint(covariant _DashedRectPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _CanvasPainter extends CustomPainter {
  _CanvasPainter({
    required this.plan,
    required this.selectedWallId,
    required this.pxPerCm,
    required this.palette,
    this.sketch,
    this.liveStroke,
  });

  final PlanDocument plan;
  final String? selectedWallId;
  final double pxPerCm;
  final CanvasPalette palette;
  final List<Offset>? sketch;
  final List<Offset>? liveStroke;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = palette.background,
    );

    final grid = Paint()
      ..color = palette.grid
      ..strokeWidth = 0.5;
    final step = PlanCanvasPanel.gridCm * pxPerCm;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    void drawStroke(List<Offset> pts, Color c, double width) {
      if (pts.length < 2) return;
      final p = Paint()
        ..color = c
        ..strokeWidth = width
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      canvas.drawPath(path, p);
    }

    if (sketch != null) {
      drawStroke(sketch!, palette.roomBorder.withValues(alpha: 0.35), 2.5);
    }
    if (liveStroke != null) {
      drawStroke(liveStroke!, palette.selectedBorder, 3);
    }

    final wallPaint = Paint()
      ..color = palette.wallStroke
      ..strokeWidth = palette.sketchy ? 3.2 : 3
      ..style = PaintingStyle.stroke
      ..strokeCap = palette.sketchy ? StrokeCap.round : StrokeCap.butt;
    final bearingPaint = Paint()
      ..color = AppColors.danger
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke;
    final selectedPaint = Paint()
      ..color = palette.selectedBorder
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    for (final w in plan.walls) {
      final bearing = plan.constraints
          .any((c) => c.type == 'load_bearing' && c.wallId == w.id);
      final paint = w.id == selectedWallId
          ? selectedPaint
          : (bearing ? bearingPaint : wallPaint);
      _drawWallWithGaps(canvas, w, paint);
    }
  }

  double _wallLen(WallSeg w) {
    final dx = w.x2 - w.x1;
    final dy = w.y2 - w.y1;
    final len = dx * dx + dy * dy;
    return len <= 0 ? 1 : math.sqrt(len);
  }

  void _drawWallWithGaps(Canvas canvas, WallSeg w, Paint paint) {
    final len = _wallLen(w);
    final openings = <({double centerCm, double widthCm})>[
      for (final d in plan.doors)
        if (d.wallId == w.id) (centerCm: d.centerCm, widthCm: d.widthCm),
      for (final win in plan.windows)
        if (win.wallId == w.id) (centerCm: win.centerCm, widthCm: win.widthCm),
    ]..sort((a, b) => a.centerCm.compareTo(b.centerCm));

    void segment(double fromCm, double toCm) {
      if (toCm - fromCm < 1) return;
      final t0 = fromCm / len;
      final t1 = toCm / len;
      final a = Offset(
        (w.x1 + (w.x2 - w.x1) * t0) * pxPerCm,
        (w.y1 + (w.y2 - w.y1) * t0) * pxPerCm,
      );
      final b = Offset(
        (w.x1 + (w.x2 - w.x1) * t1) * pxPerCm,
        (w.y1 + (w.y2 - w.y1) * t1) * pxPerCm,
      );
      if (palette.sketchy) {
        final mid = Offset((a.dx + b.dx) / 2 + 1.2, (a.dy + b.dy) / 2 - 0.8);
        final path = Path()
          ..moveTo(a.dx, a.dy)
          ..quadraticBezierTo(mid.dx, mid.dy, b.dx, b.dy);
        canvas.drawPath(path, paint);
      } else {
        canvas.drawLine(a, b, paint);
      }
    }

    if (openings.isEmpty) {
      segment(0, len);
      return;
    }
    var cursor = 0.0;
    for (final o in openings) {
      final half = o.widthCm / 2;
      final g0 = (o.centerCm - half).clamp(0.0, len);
      final g1 = (o.centerCm + half).clamp(0.0, len);
      segment(cursor, g0);
      cursor = g1;
    }
    segment(cursor, len);
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter oldDelegate) => true;
}

/// I10.2：门洞建筑符号叠层（画在房间之上）
class _DoorOverlayPainter extends CustomPainter {
  _DoorOverlayPainter({
    required this.plan,
    required this.selectedDoorId,
    required this.pxPerCm,
    required this.palette,
  });

  final PlanDocument plan;
  final String? selectedDoorId;
  final double pxPerCm;
  final CanvasPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    for (final d in plan.doors) {
      _drawDoorSymbol(canvas, d);
    }
  }

  double _wallLen(WallSeg w) {
    final dx = w.x2 - w.x1;
    final dy = w.y2 - w.y1;
    final len = dx * dx + dy * dy;
    return len <= 0 ? 1 : math.sqrt(len);
  }

  RoomRect? _roomOf(DoorOpening d) {
    for (final r in plan.rooms) {
      if (r.id == d.roomId) return r;
    }
    return null;
  }

  void _drawDoorSymbol(Canvas canvas, DoorOpening d) {
    WallSeg? wall;
    for (final w in plan.walls) {
      if (w.id == d.wallId) {
        wall = w;
        break;
      }
    }
    if (wall == null) return;
    final w = wall;
    final len = _wallLen(w);
    final half = d.widthCm / 2;
    final t = (d.centerCm / len).clamp(0.05, 0.95);
    final cx = w.x1 + (w.x2 - w.x1) * t;
    final cy = w.y1 + (w.y2 - w.y1) * t;
    final ux = (w.x2 - w.x1) / len;
    final uy = (w.y2 - w.y1) / len;
    var nx = -uy;
    var ny = ux;
    final room = _roomOf(d);
    if (room != null) {
      final rcx = room.x + room.widthCm / 2;
      final rcy = room.y + room.depthCm / 2;
      if (nx * (rcx - cx) + ny * (rcy - cy) < 0) {
        nx = -nx;
        ny = -ny;
      }
    }

    final hinge = Offset(
      (cx - ux * half) * pxPerCm,
      (cy - uy * half) * pxPerCm,
    );
    final leafEnd = Offset(
      (cx + ux * half) * pxPerCm,
      (cy + uy * half) * pxPerCm,
    );
    final centerPx = Offset(cx * pxPerCm, cy * pxPerCm);
    final radius = d.widthCm * pxPerCm;
    final selected = d.id == selectedDoorId;

    final doorPaint = Paint()
      ..color = selected ? palette.selectedBorder : AppColors.brand
      ..strokeWidth = selected ? 2.2 : 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final nPx = Offset(nx * 4, ny * 4);
    canvas.drawLine(hinge - nPx, hinge + nPx, doorPaint);
    canvas.drawLine(leafEnd - nPx, leafEnd + nPx, doorPaint);

    final type = d.doorType;
    final useSliding = type == 'sliding' || d.positionType == 'II';
    if (useSliding) {
      _drawSlidingDoor(canvas, centerPx, ux, uy, nx, ny, radius, doorPaint);
    } else if (type == 'double') {
      _drawDoubleDoor(
        canvas,
        hinge,
        leafEnd,
        ux,
        uy,
        nx,
        ny,
        radius,
        d.positionType,
        doorPaint,
      );
    } else if (type == 'folding') {
      _drawFoldingDoor(canvas, hinge, leafEnd, nx, ny, radius, doorPaint);
    } else {
      final inward = d.positionType != 'O';
      final openNx = inward ? nx : -nx;
      final openNy = inward ? ny : -ny;
      final openEnd = Offset(
        hinge.dx + openNx * radius,
        hinge.dy + openNy * radius,
      );
      canvas.drawLine(hinge, openEnd, doorPaint);

      final start = math.atan2(uy, ux);
      final end = math.atan2(openNy, openNx);
      var sweep = end - start;
      while (sweep > math.pi) {
        sweep -= 2 * math.pi;
      }
      while (sweep < -math.pi) {
        sweep += 2 * math.pi;
      }
      if (sweep.abs() < math.pi / 6) {
        sweep = sweep >= 0 ? math.pi / 2 : -math.pi / 2;
      }
      canvas.drawArc(
        Rect.fromCircle(center: hinge, radius: radius),
        start,
        sweep,
        false,
        doorPaint,
      );
    }

    final tp = TextPainter(
      text: TextSpan(
        text: d.positionType,
        style: TextStyle(
          color: selected ? palette.selectedBorder : AppColors.brand,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(
        centerPx.dx + nx * 14 - tp.width / 2,
        centerPx.dy + ny * 14 - tp.height / 2,
      ),
    );
  }

  void _drawDoubleDoor(
    Canvas canvas,
    Offset hinge,
    Offset leafEnd,
    double ux,
    double uy,
    double nx,
    double ny,
    double radius,
    String positionType,
    Paint paint,
  ) {
    final inward = positionType != 'O';
    final openNx = inward ? nx : -nx;
    final openNy = inward ? ny : -ny;
    final halfR = radius * 0.5;

    final leftEnd = Offset(
      hinge.dx + openNx * halfR,
      hinge.dy + openNy * halfR,
    );
    canvas.drawLine(hinge, leftEnd, paint);
    final leftStart = math.atan2(uy, ux);
    final leftOpen = math.atan2(openNy, openNx);
    var leftSweep = leftOpen - leftStart;
    while (leftSweep > math.pi) {
      leftSweep -= 2 * math.pi;
    }
    while (leftSweep < -math.pi) {
      leftSweep += 2 * math.pi;
    }
    if (leftSweep.abs() < math.pi / 6) {
      leftSweep = leftSweep >= 0 ? math.pi / 2 : -math.pi / 2;
    }
    canvas.drawArc(
      Rect.fromCircle(center: hinge, radius: halfR),
      leftStart,
      leftSweep,
      false,
      paint,
    );

    final rightEnd = Offset(
      leafEnd.dx + openNx * halfR,
      leafEnd.dy + openNy * halfR,
    );
    canvas.drawLine(leafEnd, rightEnd, paint);
    final rightStart = math.atan2(-uy, -ux);
    final rightOpen = math.atan2(openNy, openNx);
    var rightSweep = rightOpen - rightStart;
    while (rightSweep > math.pi) {
      rightSweep -= 2 * math.pi;
    }
    while (rightSweep < -math.pi) {
      rightSweep += 2 * math.pi;
    }
    if (rightSweep.abs() < math.pi / 6) {
      rightSweep = rightSweep >= 0 ? math.pi / 2 : -math.pi / 2;
    }
    canvas.drawArc(
      Rect.fromCircle(center: leafEnd, radius: halfR),
      rightStart,
      rightSweep,
      false,
      paint,
    );
  }

  void _drawFoldingDoor(
    Canvas canvas,
    Offset hinge,
    Offset leafEnd,
    double nx,
    double ny,
    double radius,
    Paint paint,
  ) {
    const segs = 4;
    final zig = radius * 0.28;
    final path = Path();
    for (var i = 0; i <= segs; i++) {
      final t = i / segs;
      final along = Offset(
        hinge.dx + (leafEnd.dx - hinge.dx) * t,
        hinge.dy + (leafEnd.dy - hinge.dy) * t,
      );
      final off = (i % 2 == 0) ? 0.0 : zig;
      final p = Offset(along.dx + nx * off, along.dy + ny * off);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(path, paint);
  }

  void _drawSlidingDoor(
    Canvas canvas,
    Offset center,
    double ux,
    double uy,
    double nx,
    double ny,
    double widthPx,
    Paint paint,
  ) {
    final half = widthPx / 2;
    const trackOff = 5.0;
    for (final s in [-1.0, 1.0]) {
      final o = Offset(nx * trackOff * s, ny * trackOff * s);
      final a = Offset(
        center.dx - ux * half + o.dx,
        center.dy - uy * half + o.dy,
      );
      final b = Offset(
        center.dx + ux * half + o.dx,
        center.dy + uy * half + o.dy,
      );
      canvas.drawLine(a, b, paint);
    }
    final tip = half * 0.55;
    const head = 5.0;
    final left = Offset(center.dx - ux * tip, center.dy - uy * tip);
    final right = Offset(center.dx + ux * tip, center.dy + uy * tip);
    canvas.drawLine(left, right, paint);
    canvas.drawLine(
      left,
      Offset(
        left.dx + ux * head + nx * head * 0.6,
        left.dy + uy * head + ny * head * 0.6,
      ),
      paint,
    );
    canvas.drawLine(
      left,
      Offset(
        left.dx + ux * head - nx * head * 0.6,
        left.dy + uy * head - ny * head * 0.6,
      ),
      paint,
    );
    canvas.drawLine(
      right,
      Offset(
        right.dx - ux * head + nx * head * 0.6,
        right.dy - uy * head + ny * head * 0.6,
      ),
      paint,
    );
    canvas.drawLine(
      right,
      Offset(
        right.dx - ux * head - nx * head * 0.6,
        right.dy - uy * head - ny * head * 0.6,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _DoorOverlayPainter oldDelegate) => true;
}

/// I12：窗户建筑符号叠层（四线窗）
class _WindowOverlayPainter extends CustomPainter {
  _WindowOverlayPainter({
    required this.plan,
    required this.selectedWindowId,
    required this.pxPerCm,
    required this.palette,
  });

  final PlanDocument plan;
  final String? selectedWindowId;
  final double pxPerCm;
  final CanvasPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    for (final w in plan.windows) {
      _drawWindowSymbol(canvas, w);
    }
  }

  double _wallLen(WallSeg w) {
    final dx = w.x2 - w.x1;
    final dy = w.y2 - w.y1;
    final len = dx * dx + dy * dy;
    return len <= 0 ? 1 : math.sqrt(len);
  }

  RoomRect? _roomOf(WindowOpening win) {
    for (final r in plan.rooms) {
      if (r.id == win.roomId) return r;
    }
    return null;
  }

  void _drawWindowSymbol(Canvas canvas, WindowOpening win) {
    WallSeg? wall;
    for (final w in plan.walls) {
      if (w.id == win.wallId) {
        wall = w;
        break;
      }
    }
    if (wall == null) return;
    final w = wall;
    final len = _wallLen(w);
    final half = win.widthCm / 2;
    final t = (win.centerCm / len).clamp(0.05, 0.95);
    final cx = w.x1 + (w.x2 - w.x1) * t;
    final cy = w.y1 + (w.y2 - w.y1) * t;
    final ux = (w.x2 - w.x1) / len;
    final uy = (w.y2 - w.y1) / len;
    var nx = -uy;
    var ny = ux;
    final room = _roomOf(win);
    if (room != null) {
      final rcx = room.x + room.widthCm / 2;
      final rcy = room.y + room.depthCm / 2;
      if (nx * (rcx - cx) + ny * (rcy - cy) < 0) {
        nx = -nx;
        ny = -ny;
      }
    }

    final a = Offset((cx - ux * half) * pxPerCm, (cy - uy * half) * pxPerCm);
    final b = Offset((cx + ux * half) * pxPerCm, (cy + uy * half) * pxPerCm);
    final centerPx = Offset(cx * pxPerCm, cy * pxPerCm);
    final selected = win.id == selectedWindowId;
    final color = selected ? palette.selectedBorder : AppColors.accent;

    final paint = Paint()
      ..color = color
      ..strokeWidth = selected ? 2.0 : 1.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final tick = win.type == 'floor' ? 7.0 : 5.0;
    final nTick = Offset(nx * tick, ny * tick);
    canvas.drawLine(a - nTick, a + nTick, paint);
    canvas.drawLine(b - nTick, b + nTick, paint);

    final lineCount = win.type == 'floor' ? 4 : 3;
    final depth = win.type == 'floor' ? 14.0 : 10.0;
    for (var i = 1; i <= lineCount; i++) {
      final o = depth * i / (lineCount + 0.5);
      final oa = Offset(a.dx + nx * o, a.dy + ny * o);
      final ob = Offset(b.dx + nx * o, b.dy + ny * o);
      canvas.drawLine(oa, ob, paint);
    }

    if (win.type == 'bay') {
      const bump = 8.0;
      final outA = Offset(a.dx - nx * bump, a.dy - ny * bump);
      final outB = Offset(b.dx - nx * bump, b.dy - ny * bump);
      canvas.drawLine(a, outA, paint);
      canvas.drawLine(outA, outB, paint);
      canvas.drawLine(outB, b, paint);
    }

    final badge = switch (win.type) {
      'floor' => '落',
      'bay' => '飘',
      _ => '窗',
    };
    final tp = TextPainter(
      text: TextSpan(
        text: badge,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(
        centerPx.dx + nx * 18 - tp.width / 2,
        centerPx.dy + ny * 18 - tp.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _WindowOverlayPainter oldDelegate) => true;
}

/// I12：尺寸自动标注（外轮廓 / 房间 / 门窗宽）——显示 mm，字号随边长缩放并降密
class _DimensionOverlayPainter extends CustomPainter {
  _DimensionOverlayPainter({
    required this.plan,
    required this.pxPerCm,
  });

  final PlanDocument plan;
  final double pxPerCm;

  @override
  void paint(Canvas canvas, Size size) {
    if (plan.rooms.isEmpty) return;
    final line = Paint()
      ..color = AppColors.textSecondary.withValues(alpha: 0.45)
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;

    double minX = plan.rooms.first.x;
    double minY = plan.rooms.first.y;
    double maxX = plan.rooms.first.x + plan.rooms.first.widthCm;
    double maxY = plan.rooms.first.y + plan.rooms.first.depthCm;
    for (final r in plan.rooms) {
      minX = math.min(minX, r.x);
      minY = math.min(minY, r.y);
      maxX = math.max(maxX, r.x + r.widthCm);
      maxY = math.max(maxY, r.y + r.depthCm);
    }

    final overallW = maxX - minX;
    final overallD = maxY - minY;
    // 边长像素过短则不标；字号相对墙段收敛
    final minEdgeCm = math.max(90.0, 36.0 / pxPerCm);
    final edgeFont = (5.2 + pxPerCm * 3.5).clamp(5.0, 7.5);
    final overallFont = (edgeFont + 1.2).clamp(6.0, 8.5);
    const ext = 14.0;
    const tick = 3.0;

    // 顶部总宽
    final topY = minY * pxPerCm - ext;
    final leftX = minX * pxPerCm;
    final rightX = maxX * pxPerCm;
    canvas.drawLine(Offset(leftX, topY), Offset(rightX, topY), line);
    canvas.drawLine(
      Offset(leftX, topY - tick),
      Offset(leftX, topY + tick),
      line,
    );
    canvas.drawLine(
      Offset(rightX, topY - tick),
      Offset(rightX, topY + tick),
      line,
    );
    _label(
      canvas,
      AppConstants.formatMm(overallW),
      Offset((leftX + rightX) / 2, topY - 10),
      overallFont,
      AppColors.textSecondary,
    );

    // 左侧总进深
    final sideX = minX * pxPerCm - ext;
    final topCy = minY * pxPerCm;
    final botCy = maxY * pxPerCm;
    canvas.drawLine(Offset(sideX, topCy), Offset(sideX, botCy), line);
    canvas.drawLine(
      Offset(sideX - tick, topCy),
      Offset(sideX + tick, topCy),
      line,
    );
    canvas.drawLine(
      Offset(sideX - tick, botCy),
      Offset(sideX + tick, botCy),
      line,
    );
    _label(
      canvas,
      AppConstants.formatMm(overallD),
      Offset(sideX - 12, (topCy + botCy) / 2 - 5),
      overallFont,
      AppColors.textSecondary,
    );

    for (final r in plan.rooms) {
      if (r.hasPolygon) {
        final poly = r.polygon!;
        final n = poly.length;
        for (var i = 0; i < n; i++) {
          final a = poly[i];
          final b = poly[(i + 1) % n];
          final dx = b[0] - a[0];
          final dy = b[1] - a[1];
          final len = math.sqrt(dx * dx + dy * dy);
          if (len < minEdgeCm) continue;
          final mx = (a[0] + b[0]) / 2 * pxPerCm;
          final my = (a[1] + b[1]) / 2 * pxPerCm;
          final nx = -dy / len;
          final ny = dx / len;
          final fs = (edgeFont * (len / (len + 120))).clamp(5.0, edgeFont);
          _label(
            canvas,
            AppConstants.formatMm(len),
            Offset(mx + nx * 8, my + ny * 8 - 4),
            fs,
            AppColors.textSecondary.withValues(alpha: 0.85),
          );
        }
      } else {
        if (r.widthCm >= minEdgeCm) {
          final cx = (r.x + r.widthCm / 2) * pxPerCm;
          _label(
            canvas,
            AppConstants.formatMm(r.widthCm),
            Offset(cx, r.y * pxPerCm - 10),
            edgeFont,
            AppColors.textSecondary.withValues(alpha: 0.85),
          );
        }
        if (r.depthCm >= minEdgeCm) {
          final cy = (r.y + r.depthCm / 2) * pxPerCm;
          _label(
            canvas,
            AppConstants.formatMm(r.depthCm),
            Offset(r.x * pxPerCm - 14, cy - 4),
            edgeFont,
            AppColors.textSecondary.withValues(alpha: 0.85),
          );
        }
      }
    }

    for (final d in plan.doors) {
      _openingWidthLabel(canvas, d.wallId, d.centerCm, d.widthCm, edgeFont);
    }
    for (final w in plan.windows) {
      _openingWidthLabel(canvas, w.wallId, w.centerCm, w.widthCm, edgeFont);
    }
  }

  void _openingWidthLabel(
    Canvas canvas,
    String? wallId,
    double centerCm,
    double widthCm,
    double edgeFont,
  ) {
    if (wallId == null) return;
    // 开口宽标注仅在足够宽时显示，避免与墙长数字叠死
    if (widthCm * pxPerCm < 18) return;
    WallSeg? wall;
    for (final w in plan.walls) {
      if (w.id == wallId) {
        wall = w;
        break;
      }
    }
    if (wall == null) return;
    final len = _wallLen(wall);
    final t = (centerCm / len).clamp(0.05, 0.95);
    final cx = (wall.x1 + (wall.x2 - wall.x1) * t) * pxPerCm;
    final cy = (wall.y1 + (wall.y2 - wall.y1) * t) * pxPerCm;
    final ux = (wall.x2 - wall.x1) / len;
    final uy = (wall.y2 - wall.y1) / len;
    final nx = -uy;
    final ny = ux;
    _label(
      canvas,
      AppConstants.formatMm(widthCm),
      Offset(cx + nx * 9 - 6, cy + ny * 9 - 4),
      (edgeFont - 0.5).clamp(5.0, 7.0),
      AppColors.textSecondary.withValues(alpha: 0.75),
    );
  }

  double _wallLen(WallSeg w) {
    final dx = w.x2 - w.x1;
    final dy = w.y2 - w.y1;
    final len = dx * dx + dy * dy;
    return len <= 0 ? 1 : math.sqrt(len);
  }

  void _label(
    Canvas canvas,
    String text,
    Offset at,
    double fontSize,
    Color color,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w400,
          height: 1,
          letterSpacing: -0.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(at.dx - tp.width / 2, at.dy));
  }

  @override
  bool shouldRepaint(covariant _DimensionOverlayPainter oldDelegate) => true;
}

class _RoomPolygonClipper extends CustomClipper<Path> {
  _RoomPolygonClipper(this.points);

  final List<Offset> points;

  @override
  Path getClip(Size size) {
    final path = Path();
    if (points.isEmpty) return path;
    path.moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant _RoomPolygonClipper oldClipper) => true;
}

class _RoomPolygonPainter extends CustomPainter {
  _RoomPolygonPainter({
    required this.points,
    required this.fill,
    required this.border,
    required this.strokeWidth,
  });

  final List<Offset> points;
  final Color fill;
  final Color border;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 3) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    path.close();
    if (fill != Colors.transparent) {
      canvas.drawPath(path, Paint()..color = fill);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RoomPolygonPainter oldDelegate) => true;
}
