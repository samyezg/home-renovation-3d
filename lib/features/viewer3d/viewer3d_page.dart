import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/constants.dart';
import '../../data/catalogs.dart';
import '../../models/domain.dart';
import '../../models/plan.dart';
import '../../services/repositories.dart';
import '../../theme/app_colors.dart';
import '../../theme/style_mode.dart';
import '../../widgets/style_mode_sheet.dart';
import '../renov/renov_flow_page.dart';

class Viewer3dPage extends StatefulWidget {
  const Viewer3dPage({super.key, this.plan, this.spawnSku});

  final PlanDocument? plan;
  final String? spawnSku;

  @override
  State<Viewer3dPage> createState() => _Viewer3dPageState();
}

class _Viewer3dPageState extends State<Viewer3dPage> {
  late final WebViewController _controller;
  var _ready = false;
  /// 仅调试用途；release 不展示
  var _status = '加载中…';
  String? _pendingSpawn;
  /// 墙透明度：1 不透明 / 0.35 半透明默认 / 0.08 近隐
  var _wallOpacity = 0.35;
  var _styleMode = View3dStyleMode.cartoon;
  var _tone = StyleTone.warmWood;
  var _modulesExpanded = true;

  static const _wallTiers = <(String, double)>[
    ('半透明', 0.35),
    ('近隐', 0.08),
    ('不透明', 1.0),
  ];

  String get _wallLabel {
    for (final t in _wallTiers) {
      if ((t.$2 - _wallOpacity).abs() < 0.02) return t.$1;
    }
    return '半透明';
  }

  @override
  void initState() {
    super.initState();
    _pendingSpawn = widget.spawnSku;
    _loadPrefs();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.bg)
      ..addJavaScriptChannel(
        'QingZhuangJiaFlutter',
        onMessageReceived: _onJsMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (kDebugMode) {
              setState(() => _status = '页面已加载，等待 bridge.ready…');
            }
          },
        ),
      );
    _loadLocalHtml();
  }

  Future<void> _loadPrefs() async {
    final s = await SettingsRepository().load();
    if (!mounted) return;
    setState(() {
      final v = s['wall_opacity'];
      final n = v is num ? v.toDouble() : double.tryParse('$v');
      if (n != null) _wallOpacity = n.clamp(0.02, 1.0);
      _styleMode =
          StyleModeCatalog.parseView3d(s['view3d_style_mode'] as String?);
      _tone = StyleModeCatalog.parseTone(s['style_tone'] as String?);
    });
  }

  Future<void> _persistStyle() async {
    final s = await SettingsRepository().load();
    s['view3d_style_mode'] = _styleMode.name;
    s['style_tone'] = _tone.name;
    s['wall_opacity'] = _wallOpacity;
    await SettingsRepository().save(s);
  }

  Future<void> _pushStyleToJs() async {
    if (!_ready) return;
    final payload = StyleModeCatalog.view3dThemePayload(_styleMode, _tone);
    payload['wall_opacity'] = _wallOpacity;
    await _sendToJs({
      'v': 1,
      'id': 'style_1',
      'type': 'style.set',
      'ts': DateTime.now().millisecondsSinceEpoch,
      'payload': payload,
    });
  }

  Future<void> _openStyleSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StyleModeSheet.view3d(
        view3dMode: _styleMode,
        tone: _tone,
        onView3dMode: (m) async {
          setState(() => _styleMode = m);
          await _persistStyle();
          await _pushStyleToJs();
        },
        onTone: (t) async {
          setState(() => _tone = t);
          await _persistStyle();
          await _pushStyleToJs();
        },
      ),
    );
  }

  Future<void> _setWallOpacity(double v, {bool persist = true}) async {
    setState(() => _wallOpacity = v.clamp(0.02, 1.0));
    if (_ready) {
      await _sendToJs({
        'v': 1,
        'id': 'wall_op',
        'type': 'wall.opacity',
        'ts': DateTime.now().millisecondsSinceEpoch,
        'payload': {'opacity': _wallOpacity},
      });
    }
    if (persist) {
      final s = await SettingsRepository().load();
      s['wall_opacity'] = _wallOpacity;
      await SettingsRepository().save(s);
    }
  }

  void _cycleWallOpacity() {
    final i = _wallTiers.indexWhere((t) => (t.$2 - _wallOpacity).abs() < 0.02);
    final next = _wallTiers[(i + 1) % _wallTiers.length];
    _setWallOpacity(next.$2);
  }

  Future<void> _sendCameraView(String mode) async {
    if (!_ready) return;
    await _sendToJs({
      'v': 1,
      'id': 'view_$mode',
      'type': 'camera.view',
      'ts': DateTime.now().millisecondsSinceEpoch,
      'payload': {'mode': mode},
    });
  }

  Future<void> _loadLocalHtml() async {
    try {
      final html = await rootBundle.loadString('webview_3d/index.html');
      final three = await rootBundle.loadString('webview_3d/js/three.min.js');
      final bridge = await rootBundle.loadString('webview_3d/js/bridge_stub.js');
      final scene = await rootBundle.loadString('webview_3d/js/scene.js');
      final injected = html
          .replaceFirst(
            '<script src="js/three.min.js"></script>',
            '<script>$three</script>',
          )
          .replaceFirst(
            '<script src="js/bridge_stub.js"></script>',
            '<script>$bridge</script>',
          )
          .replaceFirst(
            '<script src="js/scene.js"></script>',
            '<script>$scene</script>',
          );
      await _controller.loadHtmlString(injected, baseUrl: 'about:blank');
    } catch (e) {
      if (kDebugMode) {
        setState(() => _status = '资源读取失败：$e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('3D 资源加载失败：$e')),
        );
      }
    }
  }

  void _onJsMessage(JavaScriptMessage message) async {
    try {
      final map = jsonDecode(message.message) as Map<String, dynamic>;
      final type = map['type'] as String? ?? '';
      if (type == 'bridge.ready') {
        setState(() {
          _ready = true;
          if (kDebugMode) _status = 'Bridge ready · Three.js';
        });
        await _sendToJs({
          'v': 1,
          'id': 'theme_1',
          'type': 'theme.set',
          'ts': DateTime.now().millisecondsSinceEpoch,
          'payload': {
            ...StyleModeCatalog.view3dThemePayload(_styleMode, _tone),
            'wall_opacity': _wallOpacity,
          },
        });
        await _pushStyleToJs();
        await _sendToJs({
          'v': 1,
          'id': 'wall_1',
          'type': 'wall.opacity',
          'ts': DateTime.now().millisecondsSinceEpoch,
          'payload': {'opacity': _wallOpacity},
        });
        await _sendToJs({
          'v': 1,
          'id': 'cat_1',
          'type': 'catalog.set',
          'ts': DateTime.now().millisecondsSinceEpoch,
          'payload': {'items': SceneCatalog.modules()},
        });
        if (widget.plan != null) {
          widget.plan!.rebuildWallsFromRooms();
          await _sendToJs({
            'v': 1,
            'id': 'plan_1',
            'type': 'plan.load',
            'ts': DateTime.now().millisecondsSinceEpoch,
            'payload': {'plan': widget.plan!.toJson()},
          });
        }
        if (_pendingSpawn != null) {
          await _sendToJs({
            'v': 1,
            'id': 'spawn_1',
            'type': 'scene.spawn',
            'ts': DateTime.now().millisecondsSinceEpoch,
            'payload': {'sku_id': _pendingSpawn},
          });
          _pendingSpawn = null;
        }
        return;
      }

      if (type == 'style.degraded') {
        setState(() {
          _styleMode = View3dStyleMode.cartoon;
          if (kDebugMode) _status = '轻拟真性能不足，已降级为卡通';
        });
        await _persistStyle();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('轻拟真过载，已自动切回卡通档')),
          );
        }
        return;
      }

      // 已知结果：静默处理，不污染 UI
      if (type == 'scene.list.result') {
        await _ingestSceneList(map['payload'] as Map<String, dynamic>?);
        return;
      }
      if (type == 'view.screenshot.result') {
        await _saveScreenshot(map['payload'] as Map<String, dynamic>?);
        return;
      }
      if (type.endsWith('.result') ||
          type == 'validate.warning' ||
          type == 'bridge.error') {
        if (kDebugMode) {
          if (type == 'validate.warning') {
            final code = map['payload']?['code'] ?? '';
            final msg = map['payload']?['message'] ?? '';
            setState(() => _status = '校验：$code $msg');
          } else {
            setState(() => _status = '收到：$type');
          }
        }
        return;
      }

      if (kDebugMode) {
        setState(() => _status = '收到：$type');
      }
    } catch (_) {
      if (kDebugMode) {
        setState(() => _status = '收到非 JSON');
      }
    }
  }

  Future<void> _saveScreenshot(Map<String, dynamic>? payload) async {
    final dataUrl = payload?['data_url'] as String?;
    if (dataUrl == null || !dataUrl.contains(',')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('截图失败')),
        );
      }
      return;
    }
    final b64 = dataUrl.split(',').last;
    final bytes = base64Decode(b64);
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/screenshots');
    if (!await dir.exists()) await dir.create(recursive: true);
    final name = 'shot_${DateTime.now().millisecondsSinceEpoch}.png';
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes);

    final plan = widget.plan;
    if (plan != null) {
      final paths = [...plan.annotations.screenshotPaths, file.path];
      plan.annotations.screenshotPaths = paths;
      await PlanRepository().save(plan);
    }
    if (kDebugMode) {
      setState(() => _status = '截图已回写方案');
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('截图已保存${plan == null ? '' : '并写入方案'}'),
          action: SnackBarAction(
            label: '放大查看',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _ScreenshotZoomPage(path: file.path),
                ),
              );
            },
          ),
        ),
      );
    }
  }

  Future<void> _ingestSceneList(Map<String, dynamic>? payload) async {
    if (payload == null) return;
    final objects = payload['objects'] as List? ?? [];
    final repo = ChecklistRepository();
    final plan = widget.plan;
    String? roomNameOf(String? roomId) {
      if (plan == null || roomId == null || roomId.isEmpty) return null;
      for (final r in plan.rooms) {
        if (r.id == roomId) return r.name;
      }
      return null;
    }

    for (final o in objects) {
      final m = o as Map<String, dynamic>;
      final sku = m['sku_id'] as String? ?? 'module';
      final depth = m['depth_cm'];
      final roomId = m['room_id'] as String?;
      await repo.add(
        ChecklistLine(
          id: 'cl_${const Uuid().v4().substring(0, 8)}',
          category: '3D模块',
          title: SceneCatalog.labelOf(sku),
          specHint: depth == null ? null : '深 ${depth}cm',
          source: 'scene.list',
          depthCm: depth is int ? depth : int.tryParse('$depth'),
          skuId: sku,
          price: null,
          roomHint: roomNameOf(roomId),
        ),
      );
    }
    if (mounted && objects.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已将 ${objects.length} 个模块写入改造清单')),
      );
    }
  }

  Future<void> _sendToJs(Map<String, dynamic> envelope) async {
    final raw = jsonEncode(envelope);
    final escaped = raw.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    await _controller.runJavaScript(
      "window.QingZhuangJiaBridge && window.QingZhuangJiaBridge.onMessage('$escaped');",
    );
  }

  Future<void> _pullSceneAndPop() async {
    if (_ready) {
      await _sendToJs({
        'v': 1,
        'id': 'list_exit',
        'type': 'scene.list',
        'ts': DateTime.now().millisecondsSinceEpoch,
        'payload': {},
      });
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    // PopScope(canPop: false) 下 maybePop 不会退出，须显式 pop。
    if (mounted) Navigator.of(context).pop();
  }

  Widget _sideFab({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return Material(
      elevation: 2,
      color: AppColors.surface.withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(28),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, color: AppColors.textPrimary),
      ),
    );
  }

  Widget _viewChip(String label, String mode) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        elevation: 1,
        color: AppColors.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: !_ready ? null : () => _sendCameraView(mode),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: _ready ? AppColors.textPrimary : AppColors.textDisabled,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final webSupported = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _pullSceneAndPop();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          title: const Text('3D 预览'),
          leading: IconButton(
            tooltip: '返回',
            icon: const Icon(Icons.arrow_back),
            onPressed: _pullSceneAndPop,
          ),
          actions: [
            IconButton(
              tooltip: '缩小',
              onPressed: !_ready
                  ? null
                  : () => _sendToJs({
                        'v': 1,
                        'id': 'zoom_out',
                        'type': 'camera.zoom',
                        'ts': DateTime.now().millisecondsSinceEpoch,
                        'payload': {'factor': 1.25},
                      }),
              icon: const Icon(Icons.zoom_out),
            ),
            IconButton(
              tooltip: '放大',
              onPressed: !_ready
                  ? null
                  : () => _sendToJs({
                        'v': 1,
                        'id': 'zoom_in',
                        'type': 'camera.zoom',
                        'ts': DateTime.now().millisecondsSinceEpoch,
                        'payload': {'factor': 0.8},
                      }),
              icon: const Icon(Icons.zoom_in),
            ),
            IconButton(
              tooltip: '全部显示·俯视45°',
              onPressed: !_ready
                  ? null
                  : () => _sendToJs({
                        'v': 1,
                        'id': 'cam_1',
                        'type': 'camera.fit',
                        'ts': DateTime.now().millisecondsSinceEpoch,
                        'payload': {},
                      }),
              icon: const Icon(Icons.center_focus_strong),
            ),
            IconButton(
              tooltip: '视角上移（平移）',
              onPressed: !_ready
                  ? null
                  : () => _sendToJs({
                        'v': 1,
                        'id': 'pan_up',
                        'type': 'camera.pan',
                        'ts': DateTime.now().millisecondsSinceEpoch,
                        'payload': {'dx': 0, 'dy': 80},
                      }),
              icon: const Icon(Icons.swipe_up_alt_outlined),
            ),
            IconButton(
              tooltip: '视角下移（平移）',
              onPressed: !_ready
                  ? null
                  : () => _sendToJs({
                        'v': 1,
                        'id': 'pan_down',
                        'type': 'camera.pan',
                        'ts': DateTime.now().millisecondsSinceEpoch,
                        'payload': {'dx': 0, 'dy': -80},
                      }),
              icon: const Icon(Icons.swipe_down_alt_outlined),
            ),
            IconButton(
              tooltip: '拍照改造',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RenovFlowPage()),
                );
              },
              icon: const Icon(Icons.camera_enhance_outlined),
            ),
            IconButton(
              tooltip: '截图回写方案',
              onPressed: !_ready
                  ? null
                  : () => _sendToJs({
                        'v': 1,
                        'id': 'shot_1',
                        'type': 'view.screenshot',
                        'ts': DateTime.now().millisecondsSinceEpoch,
                        'payload': {},
                      }),
              icon: const Icon(Icons.camera_alt_outlined),
            ),
          ],
        ),
        body: Column(
          children: [
            if (kDebugMode)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                color: AppColors.brandSoft,
                child: Text(
                  '$_status · ${StyleModeCatalog.view3dLabel(_styleMode)} · '
                  '${StyleModeCatalog.toneLabel(_tone)} · 墙$_wallLabel',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            Expanded(
              child: webSupported
                  ? Stack(
                      children: [
                        WebViewWidget(controller: _controller),
                        Positioned(
                          right: 12,
                          top: 12,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _sideFab(
                                tooltip:
                                    '样式·${StyleModeCatalog.view3dLabel(_styleMode)}',
                                icon: Icons.palette_outlined,
                                onPressed: !_ready ? null : _openStyleSheet,
                              ),
                              const SizedBox(height: 8),
                              _sideFab(
                                tooltip: '墙体：$_wallLabel',
                                icon: Icons.opacity,
                                onPressed: !_ready ? null : _cycleWallOpacity,
                              ),
                              const SizedBox(height: 12),
                              _viewChip('顶视', 'top'),
                              _viewChip('前视', 'front'),
                              _viewChip('侧视', 'side'),
                              _viewChip('45°', 'iso'),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'WebView 3D 请在 Android / iOS 运行。\n'
                          '${kDebugMode ? '$_status\n\n' : ''}'
                          '${AppConstants.disclaimer}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    ),
            ),
            if (webSupported)
              ColoredBox(
                color: AppColors.surface,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ActionChip(
                          avatar: Icon(
                            _modulesExpanded
                                ? Icons.expand_more
                                : Icons.chevron_right,
                            size: 18,
                            color: AppColors.brand,
                          ),
                          label: Text(
                            _modulesExpanded ? '模块' : '模块 · 展开',
                            style: const TextStyle(color: AppColors.textPrimary),
                          ),
                          backgroundColor: AppColors.brandSoft,
                          side: BorderSide.none,
                          onPressed: () => setState(
                            () => _modulesExpanded = !_modulesExpanded,
                          ),
                        ),
                      ),
                    ),
                    if (_modulesExpanded)
                      SizedBox(
                        height: 56,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          children: [
                            for (final m in SceneCatalog.modules())
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 8,
                                ),
                                child: ActionChip(
                                  label: Text(m['name'] as String),
                                  onPressed: !_ready
                                      ? null
                                      : () => _sendToJs({
                                            'v': 1,
                                            'id': 'spawn_${m['sku_id']}',
                                            'type': 'scene.spawn',
                                            'ts': DateTime.now()
                                                .millisecondsSinceEpoch,
                                            'payload': {
                                              'sku_id': m['sku_id'],
                                            },
                                          }),
                                ),
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 期次 W：截图后可捏合放大查看
class _ScreenshotZoomPage extends StatelessWidget {
  const _ScreenshotZoomPage({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final f = File(path);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('截图放大'),
      ),
      body: f.existsSync()
          ? InteractiveViewer(
              minScale: 0.5,
              maxScale: 8,
              child: Center(
                child: Image.file(f, fit: BoxFit.contain),
              ),
            )
          : const Center(
              child: Text('文件不存在', style: TextStyle(color: Colors.white70)),
            ),
    );
  }
}
