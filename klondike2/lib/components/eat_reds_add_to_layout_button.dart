import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../klondike_game.dart';
import '../klondike_world.dart';
import '../rules/eat_reds_rules.dart';

/// Button for adding a card to layout when no captures are possible
class EatRedsAddToLayoutButton extends RectangleComponent
    with TapCallbacks, HasWorldReference<KlondikeWorld> {
  EatRedsAddToLayoutButton({required Vector2 position})
    : super(
        position: position,
        size: Vector2(KlondikeGame.cardWidth * 1.5, 0.6 * KlondikeGame.topGap), // Increased width
        paint: Paint()
          ..color = const Color(0xFF2196F3), // Blue color (different from Play button's green)
      );

  late TextComponent _textComponent;
  bool _enabled = false;

  @override
  Future<void> onLoad() async {
    _textComponent = TextComponent(
      text: 'Add to Layout',
      textRenderer: TextPaint(
        style: TextStyle(
          fontSize: 0.5 * size.y, // Same dynamic sizing as Play button
          fontWeight: FontWeight.bold,
          color: const Color(0xffdbaf58), // Same gold color as Play button
          shadows: [
            Shadow(
              color: const Color(0xFF000000), // Black shadow for text border
              offset: const Offset(1, 1),
              blurRadius: 2,
            ),
          ],
        ),
      ),
      anchor: Anchor.center,
      position: size / 2,
    );
    add(_textComponent);
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Check if the button should be enabled
    final rules = world.rules;
    if (rules is EatRedsRules) {
      final shouldEnable =
          rules.selectedHandCard != null &&
          !rules.layoutCards.contains(rules.selectedHandCard!) &&
          rules.canPlayNonCapturing();
      if (_enabled != shouldEnable) {
        _enabled = shouldEnable;
        // Update button appearance based on enabled state
        if (_enabled) {
          paint.color = const Color(0xFF2196F3); // Blue when enabled
        } else {
          paint.color = const Color(0xFF424242); // Gray when disabled
        }
      }
    }
  }

  @override
  bool onTapDown(TapDownEvent event) {
    if (!_enabled) return false;

    final rules = world.rules;
    if (rules is! EatRedsRules) return false;

    final selectedCard = rules.selectedHandCard;
    if (selectedCard == null) return false;

    // Execute non-capturing play
    final foundations = world.foundations;
    if (rules.executeNonCapturingPlay(selectedCard, foundations)) {
      debugPrint('Added card to layout - player must now draw from stock');
    }
    return true;
  }
}
