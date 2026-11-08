import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 解码并 bake EXIF Orientation，保证显示与像素处理同一坐标系。
abstract final class ImageOrientation {
  static img.Image? decodeBaked(List<int> bytes) {
    try {
      final decoded = img.decodeImage(Uint8List.fromList(bytes));
      if (decoded == null) return null;
      return img.bakeOrientation(decoded);
    } catch (_) {
      return null;
    }
  }

  /// 写出 bake 后的 JPEG；失败则返回原文件。
  static Future<File> normalizeToFile(File source) async {
    try {
      final bytes = await source.readAsBytes();
      final baked = decodeBaked(bytes);
      if (baked == null) return source;
      final dir = source.parent;
      final name = 'orient_${source.uri.pathSegments.last}';
      final out = File('${dir.path}${Platform.pathSeparator}$name');
      await out.writeAsBytes(img.encodeJpg(baked, quality: 90), flush: true);
      return out;
    } catch (_) {
      return source;
    }
  }
}
