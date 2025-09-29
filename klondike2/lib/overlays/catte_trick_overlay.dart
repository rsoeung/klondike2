import 'package:flame/components.dart';
import 'package:flutter/material.dart';

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
      buf.write('Leader: P${rules.leaderIndex + 1}  ');
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

/// A crown indicator to show which player is the leader of the current trick.
class CatTeLeaderIndicator extends PositionComponent {
  CatTeLeaderIndicator() : super(priority: 1000);

  static final _paint = Paint()
    ..style = PaintingStyle.fill
    ..color = const Color(0xFFFFD700); // Gold color

  static final _strokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth =
        5 // Much thicker outline
    ..color = const Color(0xFF8B4513); // Brown outline

  @override
  void render(Canvas canvas) {
    final parentSize = (parent as PositionComponent).size;
    final centerX = parentSize.x / 2;
    final topY = -130.0; // Position higher above the pile

    // Draw a larger, more visible crown shape
    final crownPath = Path();
    final crownWidth = 200.0; // Much larger width
    final crownHeight = 100.0; // Much larger height

    // Crown base
    crownPath.moveTo(centerX - crownWidth / 2, topY + crownHeight);
    crownPath.lineTo(centerX + crownWidth / 2, topY + crownHeight);
    crownPath.lineTo(centerX + crownWidth / 2, topY + crownHeight * 0.7);

    // Crown peaks (more pronounced)
    crownPath.lineTo(centerX + crownWidth * 0.3, topY + crownHeight * 0.2);
    crownPath.lineTo(centerX + crownWidth * 0.15, topY + crownHeight * 0.4);
    crownPath.lineTo(centerX, topY);
    crownPath.lineTo(centerX - crownWidth * 0.15, topY + crownHeight * 0.4);
    crownPath.lineTo(centerX - crownWidth * 0.3, topY + crownHeight * 0.2);
    crownPath.lineTo(centerX - crownWidth / 2, topY + crownHeight * 0.7);
    crownPath.close();

    // Draw crown with shadow effect
    final shadowPath = Path.from(crownPath);
    shadowPath.shift(const Offset(3, 3));
    canvas.drawPath(shadowPath, Paint()..color = const Color(0x88000000)); // Shadow
    canvas.drawPath(crownPath, _paint);
    canvas.drawPath(crownPath, _strokePaint);

    // Add larger "LEADER" text below the crown
    final textSpan = TextSpan(
      text: 'LEADER',
      style: TextStyle(
        color: const Color(0xFFFFFFFF),
        fontSize: 18, // Larger font
        fontWeight: FontWeight.bold,
        shadows: [
          Shadow(blurRadius: 2.0, color: const Color(0xFF000000), offset: Offset(1.0, 1.0)),
        ],
      ),
    );
    final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
    textPainter.layout();
    textPainter.paint(canvas, Offset(centerX - textPainter.width / 2, topY + crownHeight + 8));
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
