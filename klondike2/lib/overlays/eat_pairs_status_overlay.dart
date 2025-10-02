import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../klondike_game.dart';
import '../rules/eat_pairs_rules.dart';

/// Overlay showing player hand counts and game status for Eat Pairs game.
class EatPairsStatusOverlay extends PositionComponent with HasGameReference<KlondikeGame> {
  EatPairsStatusOverlay(this.rules) : super(position: Vector2(20, 10), size: Vector2(4800, 1200));
  final EatPairsRules rules;

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
      // Game in progress - show player status
      buf.write('Eat Pairs (Siku) - Player Hand Counts:\n');

      // Guard: check if game is initialized
      if (rules.handCounts.isEmpty) {
        buf.write('Game initializing...\n');
      } else {
        for (int i = 0; i < rules.playerCount && i < rules.handCounts.length; i++) {
          final handCount = rules.handCounts[i];
          final isDealer = i == rules.dealerIndex ? ' (Dealer)' : '';
          final isCurrent = i == rules.currentPlayerIndex ? ' ← Current' : '';
          final isLeader = i == rules.leadPlayerIndex ? ' [LEAD]' : '';
          buf.write('Player ${i + 1}: $handCount cards$isDealer$isCurrent$isLeader\n');
        }
      }

      // Show game status
      if (rules.awaitingMatch && rules.activeCard != null) {
        final card = rules.activeCard!;
        buf.write('\nActive card: ${card.rank.label}${card.suit.label}');
        buf.write('\nAll Players: Match this card or Draw from stock!');
      } else if (rules.selectedHandCard != null) {
        final card = rules.selectedHandCard!;
        buf.write('\nSelected: ${card.rank.label}${card.suit.label}');
        if (rules.canPlay) {
          buf.write(' (Click Play!)');
        } else {
          buf.write(' (Cannot play - must draw from stock!)');
        }
      } else if (!rules.awaitingMatch) {
        // Check if dealer has played their first card yet
        final dealerPlayed =
            rules.handCounts.isNotEmpty &&
            rules.handCounts[rules.dealerIndex] < (rules.dealerIndex == rules.dealerIndex ? 8 : 7);
        if (!dealerPlayed) {
          buf.write('\n>>> Dealer (P${rules.dealerIndex + 1}): Play ONE card to start! <<<');
        } else {
          buf.write('\n>>> Lead Player (P${rules.leadPlayerIndex + 1}): Draw from stock! <<<');
        }
      } else {
        buf.write('\nWaiting for match or draw from stock...');
      }

      // Show stock remaining
      buf.write('\nStock cards remaining: ${rules.stockCardsRemaining}');
    } else {
      // Game over - show winner
      buf.write('Game Over!\n');
      buf.write('Player ${winner + 1} wins! 🏆\n');
      buf.write('They successfully emptied their hand!');
    }

    canvas.save();
    // Enlarge for readability (same scale as other games)
    const scaleFactor = 8.0;
    canvas.scale(scaleFactor, scaleFactor);
    // Shift text upward so it doesn't overlap with game elements
    const worldShiftUp = 1800.0;
    final scaledShift = worldShiftUp / scaleFactor;
    canvas.translate(0, -scaledShift);
    _textPaint.render(canvas, buf.toString(), Vector2.zero());
    canvas.restore();
  }

  // Never intercept taps; buttons beneath work.
  @override
  bool containsPoint(Vector2 point) => false;
}
