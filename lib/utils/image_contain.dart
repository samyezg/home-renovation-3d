import 'dart:ui';

/// BoxFit.contain 下内容在视口中的实际绘制矩形。
Rect containRect(Size viewport, double contentAspect) {
  if (viewport.width <= 0 || viewport.height <= 0 || contentAspect <= 0) {
    return Offset.zero & viewport;
  }
  final viewAspect = viewport.width / viewport.height;
  if (viewAspect > contentAspect) {
    final h = viewport.height;
    final w = h * contentAspect;
    return Rect.fromLTWH((viewport.width - w) / 2, 0, w, h);
  }
  final w = viewport.width;
  final h = w / contentAspect;
  return Rect.fromLTWH(0, (viewport.height - h) / 2, w, h);
}

Offset viewportToNorm(Offset local, Rect contentBox) {
  if (contentBox.width < 1 || contentBox.height < 1) {
    return Offset.zero;
  }
  return Offset(
    ((local.dx - contentBox.left) / contentBox.width).clamp(0.0, 1.0),
    ((local.dy - contentBox.top) / contentBox.height).clamp(0.0, 1.0),
  );
}

Offset normToViewport(double nx, double ny, Rect contentBox) {
  return Offset(
    contentBox.left + nx.clamp(0.0, 1.0) * contentBox.width,
    contentBox.top + ny.clamp(0.0, 1.0) * contentBox.height,
  );
}
