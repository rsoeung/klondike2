import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';

import '../klondike_game.dart';
import '../rules/catte_trick_rules.dart';
import '../components/tableau_pile.dart';

/// Overlay showing current trick / turn info for CatTe trick rules.
class CatTeTrickStatusOverlay extends PositionComponent with HasGameReference<KlondikeGame> {
  CatTeTrickStatusOverlay(this.rules) : super(position: Vector2(20, 10), size: Vector2(4800, 1200));
  final CatTeTrickRules rules;
  // Larger readable text (cards are huge, so scale accordingly).
  late TextPaint _textPaint;

  @override
  Future<void> onLoad() async {
    _textPaint = TextPaint(); // default settings; size handled via canvas scaling
    await super.onLoad();
  }

  int _lastTrickShown = -1;
  int? _lastWinner;

  @override
  void render(Canvas canvas) {
    final winner = rules.winnerIndex;
    final trick = rules.trickNumber;
    final buf = StringBuffer();
    if (winner == null) {
      buf.write('Trick $trick / 6  ');
      buf.write('Turn: P${rules.currentPlayerIndex + 1}  ');
      buf.write('Region: ${rules.region.name} (tap)\n');
      final lead = rules.leadSuit;
      if (lead != null && rules.trickNumber < 6) {
        buf.write('Lead suit: ${lead.label}  ');
        buf.write('Follow if possible. ');
      } else if (rules.trickNumber == 6) {
        buf.write('Final trick: any suit allowed. ');
      }
      buf.write('\nFolding: Always permitted; folded card cannot win.');
      final sel = rules.selectedCard;
      if (sel != null) {
        buf.write('\nSelected: ${sel.rank.label}${sel.suit.label}');
      } else {
        buf.write('\nTap a card to select.');
      }
    } else {
      buf.write('Winner: Player ${winner + 1}');
    }
    canvas.save();
    // Enlarge for readability.
    const scaleFactor = 8.0;
    canvas.scale(scaleFactor, scaleFactor);
    // Shift text upward so its bottom is above the button row (which starts ~y=100).
    // Approximate needed world shift (pre-scale) ~470 => divide by scaleFactor in scaled space.
    const worldShiftUp = 800.0; // tune if still overlapping
    final scaledShift = worldShiftUp / scaleFactor;
    canvas.translate(0, -scaledShift);
    _textPaint.render(canvas, buf.toString(), Vector2.zero());
    canvas.restore();
  }

  // Never intercept taps; buttons beneath work.
  @override
  bool containsPoint(Vector2 point) => false;

  @override
  void update(double dt) {
    super.update(dt);
    if (_lastTrickShown != rules.trickNumber || _lastWinner != rules.winnerIndex) {
      _lastTrickShown = rules.trickNumber;
      _lastWinner = rules.winnerIndex;
      debugPrint('CatTe Status: trick=${rules.trickNumber} winner=${rules.winnerIndex}');
    }
    _dimEliminatedPiles();
  }

  void _dimEliminatedPiles() {
    final world = game.world as dynamic;
    if (world.tableauPiles is! List<TableauPile>) return;
    final tableaus = world.tableauPiles as List<TableauPile>;
    for (var i = 0; i < tableaus.length; i++) {
      final pile = tableaus[i];
      final eliminated = (i < rules.eliminatedView.length) ? rules.eliminatedView[i] : false;
      // Dim eliminated players by adding overlay component per card.
      for (final card in pile.cards) {
        // If card already has a dim overlay skip; else add one.
        final existing = card.children.whereType<_DimOverlay>().firstOrNull;
        if (eliminated) {
          if (existing == null) {
            card.add(_DimOverlay());
          }
        } else {
          existing?.removeFromParent();
        }
      }
    }
  }
}

/// A glowing frame added to the active player's tableau pile.
class CatTeHighlightFrame extends PositionComponent {
  CatTeHighlightFrame() : super(priority: 999);

  static final _paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 25
    ..color = const Color(0xAAFFD54F);

  @override
  void render(Canvas canvas) {
    final parentSize = (parent as PositionComponent).size;
    final rect = Rect.fromLTWH(0, 0, parentSize.x, parentSize.y);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(KlondikeGame.cardRadius));
    canvas.drawRRect(rrect, _paint);
  }
}

// Semi-transparent overlay to visually dim eliminated player's cards.
class _DimOverlay extends PositionComponent {
  static final _paint = Paint()..color = const Color(0x88000000);

  @override
  void render(Canvas canvas) {
    final parentComponent = parent as PositionComponent;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, parentComponent.size.x, parentComponent.size.y),
        const Radius.circular(KlondikeGame.cardRadius),
      ),
      _paint,
    );
  }
}

// (Button dimming now handled in world for aligned top-row buttons.)
