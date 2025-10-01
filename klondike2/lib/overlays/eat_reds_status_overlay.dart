import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../klondike_game.dart';
import '../rules/eat_reds_rules.dart';

/// Overlay showing player scores and game status for Eat Reds game.
class EatRedsStatusOverlay extends PositionComponent with HasGameReference<KlondikeGame> {
  EatRedsStatusOverlay(this.rules) : super(position: Vector2(20, 10), size: Vector2(4800, 1200));
  final EatRedsRules rules;

  late TextPaint _textPaint;

  @override
  Future<void> onLoad() async {
    _textPaint = TextPaint(); // default settings; size handled via canvas scaling
    await super.onLoad();
  }

  @override
  void render(Canvas canvas) {
    final winner = rules.gameWinnerIndex;
    final buf = StringBuffer();

    if (winner == null) {
      // Game in progress - show current scores
      buf.write('Eat Reds - Current Scores:\n');

      for (int i = 0; i < rules.playerCount; i++) {
        final score = rules.getPlayerScore(i);
        final indicator = i == rules.currentPlayerIndex ? ' ← Current' : '';
        buf.write('Player ${i + 1}: $score points$indicator\n');
      }

      // Show game status
      if (rules.awaitingStockDraw) {
        buf.write('\nClick stock pile to draw replacement card');
      } else if (rules.selectedHandCard != null) {
        final card = rules.selectedHandCard!;

        // Check if selected card is from layout (stock card)
        final isStockCard = rules.layoutCards.contains(card);
        final cardType = isStockCard ? 'Stock card' : 'Hand card';

        buf.write('\n$cardType selected: ${card.rank.label}${card.suit.label}');
        if (rules.selectedLayoutCard != null) {
          final layoutCard = rules.selectedLayoutCard!;
          buf.write(' → ${layoutCard.rank.label}${layoutCard.suit.label}');
          if (rules.canPlay) {
            buf.write(' (Click Play!)');
          } else {
            buf.write(' (Invalid capture)');
          }
        } else if (isStockCard) {
          buf.write(' (Select a layout card to capture)');
        } else {
          // Hand card selected - show capture option or add to layout option
          if (rules.canPlayNonCapturing()) {
            buf.write(' (Select layout card to capture, or Add to Layout if no captures)');
          } else {
            buf.write(' (Select layout card)');
          }
        }
      } else {
        final hasCaptures = rules.currentPlayerHasValidCaptures();
        if (hasCaptures) {
          buf.write('\nPlayer ${rules.currentPlayerIndex + 1}: Select a card from your hand');
        } else {
          buf.write(
            '\nPlayer ${rules.currentPlayerIndex + 1}: No captures available - select card to add to layout',
          );
        }
      }

      // Show stock remaining
      buf.write('\nStock cards remaining: ${rules.stockCardsRemaining}');
    } else {
      // Game over - show final scores and winner
      buf.write('Game Over! Final Scores:\n');

      for (int i = 0; i < rules.playerCount; i++) {
        final score = rules.getPlayerScore(i);
        final winnerMark = i == winner ? ' 🏆 WINNER!' : '';
        buf.write('Player ${i + 1}: $score points$winnerMark\n');
      }
    }

    canvas.save();
    // Enlarge for readability (same scale as Cat Te)
    const scaleFactor = 8.0;
    canvas.scale(scaleFactor, scaleFactor);
    // Shift text upward so it doesn't overlap with game elements
    const worldShiftUp = 1800.0;
    final scaledShift = worldShiftUp / scaleFactor;
    canvas.translate(0, -scaledShift);
    _textPaint.render(canvas, buf.toString(), Vector2.zero());
    canvas.restore();
  }
}
