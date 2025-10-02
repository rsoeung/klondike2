import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../klondike_game.dart';
import '../klondike_world.dart';
import '../rules/eat_pairs_rules.dart';
import 'card.dart';

/// Button for drawing a card from stock when no match is found
class EatPairsNoMatchButton extends RectangleComponent
    with TapCallbacks, HasWorldReference<KlondikeWorld> {
  EatPairsNoMatchButton({required Vector2 position})
    : super(
        position: position,
        size: Vector2(KlondikeGame.cardWidth * 1.5, 0.6 * KlondikeGame.topGap),
        paint: Paint()..color = const Color(0xFFFF9800), // Orange color
      );

  late TextComponent _textComponent;
  bool _enabled = false;

  @override
  Future<void> onLoad() async {
    _textComponent = TextComponent(
      text: 'Draw Card',
      textRenderer: TextPaint(
        style: TextStyle(
          fontSize: 0.5 * size.y,
          fontWeight: FontWeight.bold,
          color: const Color(0xffdbaf58), // Gold color
          shadows: [
            Shadow(color: const Color(0xFF000000), offset: const Offset(1, 1), blurRadius: 2),
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
    if (rules is EatPairsRules) {
      // Enable when stock has cards and can draw
      final shouldEnable = rules.stockCardsRemaining > 0;
      if (_enabled != shouldEnable) {
        _enabled = shouldEnable;
        _updateAppearance();
      }
    }
  }

  void _updateAppearance() {
    if (_enabled) {
      paint.color = const Color(0xFFFF9800); // Orange - enabled
      _textComponent.textRenderer = TextPaint(
        style: TextStyle(
          fontSize: 0.5 * size.y,
          fontWeight: FontWeight.bold,
          color: const Color(0xffdbaf58),
        ),
      );
    } else {
      paint.color = const Color(0xFF757575); // Gray - disabled
      _textComponent.textRenderer = TextPaint(
        style: TextStyle(
          fontSize: 0.5 * size.y,
          fontWeight: FontWeight.bold,
          color: const Color(0xFFBDBDBD), // Lighter text when disabled
        ),
      );
    }
  }

  @override
  bool onTapDown(TapDownEvent event) {
    if (_enabled) {
      final rules = world.rules;
      if (rules is EatPairsRules) {
        // Trigger stock pile draw
        // Find and tap the stock pile
        final stockPile = world.stock;
        if (stockPile.children.isNotEmpty) {
          final topCard = stockPile.children.last;
          if (topCard is Card) {
            stockPile.handleTapUp(topCard);
            debugPrint('Draw Card button pressed - drawing from stock');
          }
        }
      }
    }
    return true;
  }
}
