import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import '../klondike_world.dart';
import '../rules/eat_reds_rules.dart';

/// Score display component for Eat Reds foundation piles
class EatRedsScoreDisplay extends TextComponent with HasWorldReference<KlondikeWorld> {
  EatRedsScoreDisplay({required this.playerIndex, required Vector2 position})
    : super(
        text: '0',
        textRenderer: TextPaint(
          style: const TextStyle(
            color: Color(0xFF000000),
            fontSize: 18,
            fontWeight: FontWeight.bold,
            backgroundColor: Color(0xFFFFFFFF),
          ),
        ),
        anchor: Anchor.center,
        position: position,
      );

  final int playerIndex;
  int _lastScore = 0;

  @override
  void update(double dt) {
    super.update(dt);

    // Update score display
    final rules = world.rules;
    if (rules is EatRedsRules) {
      final currentScore = rules.getPlayerScore(playerIndex);
      if (_lastScore != currentScore) {
        _lastScore = currentScore;
        text = '$currentScore';
      }
    }
  }
}
