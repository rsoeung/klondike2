import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../klondike_game.dart';
import '../klondike_world.dart';
import '../rules/eat_pairs_rules.dart';

/// Play button for Eat Pairs game - executes the play/match when card is selected
class EatPairsPlayButton extends RectangleComponent
    with TapCallbacks, HasWorldReference<KlondikeWorld> {
  EatPairsPlayButton({required Vector2 position})
    : super(
        position: position,
        size: Vector2(KlondikeGame.cardWidth * 1.5, 0.6 * KlondikeGame.topGap),
        paint: Paint()..color = const Color(0xFF4CAF50), // Green color
      );

  late TextComponent _textComponent;
  bool _enabled = false;

  @override
  Future<void> onLoad() async {
    _textComponent = TextComponent(
      text: 'Play',
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
      final shouldEnable = rules.canPlay;
      if (_enabled != shouldEnable) {
        _enabled = shouldEnable;
        _updateAppearance();
      }
    }
  }

  void _updateAppearance() {
    if (_enabled) {
      paint.color = const Color(0xFF4CAF50); // Green - enabled
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
        // Execute the play action
        final success = rules.executePlay(
          world.tableauPiles,
          world.foundations,
          world.stock,
          world.waste,
        );
        if (success) {
          debugPrint('Play button pressed - action executed successfully');
        }
      }
    }
    return true;
  }
}
