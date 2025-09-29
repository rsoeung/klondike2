import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/text.dart';
import 'package:flutter/material.dart';

/// Minimal custom flat button that uses the new Flame event system (TapCallbacks)
/// instead of ButtonComponent (which seemed to stop firing onReleased).
class FlatButton extends PositionComponent with TapCallbacks {
  FlatButton(String text, {Vector2? size, this.onReleased, super.position})
    : super(size: size, anchor: Anchor.center) {
    _label = TextComponent(
      text: text,
      textRenderer: TextPaint(
        style: TextStyle(
          fontSize: size != null ? 0.5 * size.y : 20,
          fontWeight: FontWeight.bold,
          color: const Color(0xffdbaf58),
        ),
      ),
      anchor: Anchor.center,
      position: (size ?? Vector2.zero()) / 2,
    );
  }

  final VoidCallback? onReleased;
  late final TextComponent _label;
  bool _pressed = false;
  bool enabled = true;
  Color? activeColor; // optional fill when enabled
  static const _disabledFill = Color(0x55222222);

  static final _borderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..color = const Color(0xffece8a3)
    ..strokeWidth = 0; // will set in onMount

  @override
  Future<void> onLoad() async {
    await add(_label);
    return super.onLoad();
  }

  @override
  void onMount() {
    super.onMount();
    _borderPaint.strokeWidth = 0.05 * size.y;
  }

  @override
  void render(Canvas canvas) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.x, size.y),
      Radius.circular(0.3 * size.y),
    );
    // Border
    canvas.drawRRect(rrect, _borderPaint);
    // Background fill depending on state
    if (enabled) {
      if (activeColor != null) {
        final base = activeColor!;
        final opacity = _pressed ? 0.9 : 0.6;
        final fillColor = base.withValues(alpha: opacity);
        final fill = Paint()..color = fillColor;
        canvas.drawRRect(rrect, fill);
      }
    } else {
      final fill = Paint()..color = _disabledFill;
      canvas.drawRRect(rrect, fill);
    }
    if (_pressed) {
      final overlay = Paint()..color = const Color(0x33FF0000);
      canvas.drawRRect(rrect, overlay);
    }
    super.render(canvas);
  }

  @override
  bool containsPoint(Vector2 point) {
    // Component is anchored at center, so convert point to local space.
    final local = point - (absolutePosition - size / 2);
    return local.x >= 0 && local.y >= 0 && local.x <= size.x && local.y <= size.y;
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (!enabled) return;
    _pressed = true;
  }

  @override
  void onTapUp(TapUpEvent event) {
    if (!enabled) return;
    _pressed = false;
    onReleased?.call();
  }

  @override
  void onTapCancel(TapCancelEvent event) {
    _pressed = false;
  }
}
