import 'dart:ui';

import 'package:flame/components.dart';

import '../klondike_game.dart';
import '../pile.dart';
import '../rules/eat_pairs_rules.dart';
import 'card.dart';
import 'waste_pile.dart';
import 'foundation_pile.dart';
import 'tableau_pile.dart';

class StockPile extends PositionComponent with HasGameReference<KlondikeGame> implements Pile {
  StockPile({super.position}) : super(size: KlondikeGame.cardSize);

  /// Which cards are currently placed onto this pile. The first card in the
  /// list is at the bottom, the last card is on top.
  final List<Card> _cards = [];

  //#region Pile API

  @override
  bool canMoveCard(Card card, MoveMethod method) => false;
  // Can be moved by onTapUp callback (see below).

  @override
  bool canAcceptCard(Card card) => false;

  @override
  void removeCard(Card card, MoveMethod method) => throw StateError('cannot remove cards');

  @override
  // Card cannot be removed but could have been dragged out of place.
  void returnCard(Card card) => card.priority = _cards.indexOf(card);

  @override
  void acquireCard(Card card) {
    assert(card.isFaceDown);
    card.pile = this;
    card.position = position;
    card.priority = _cards.length;
    _cards.add(card);
  }

  //#endregion

  void handleTapUp(Card card) {
    final wastePile = parent!.firstChild<WastePile>()!;

    // Special handling for Eat Pairs game
    if (game.rules is EatPairsRules) {
      if (_cards.isEmpty) {
        return; // No recycling in Eat Pairs
      }

      // Delegate draw policy to rules
      if (!game.rules.canDrawFromStock(this)) {
        return;
      }

      final eatPairsRules = game.rules as EatPairsRules;

      // Draw and distribute the card
      if (eatPairsRules.drawAndDistributeFromStock(
        this,
        parent!.children.whereType<TableauPile>().toList(),
        parent!.children.whereType<FoundationPile>().toList(),
        wastePile,
      )) {
        // Draw the card and move it to waste pile
        if (_cards.isNotEmpty) {
          final drawnCard = _cards.removeLast();

          // Flip the card face-up immediately
          if (drawnCard.isFaceDown) {
            drawnCard.flip();
          }

          // Animate to waste pile (like Eat Reds)
          drawnCard.doMove(
            wastePile.position,
            speed: 10,
            onComplete: () {
              // Clear pile association from stock
              if (drawnCard.pile is StockPile) {
                drawnCard.pile = null;
              }

              wastePile.acquireCard(drawnCard);

              // Add a small delay before processing to make animations visible
              Future.delayed(const Duration(milliseconds: 100), () {
                // Process the drawn card for matching
                eatPairsRules.processDrawnCard(
                  drawnCard,
                  parent!.children.whereType<TableauPile>().toList(),
                  parent!.children.whereType<FoundationPile>().toList(),
                  wastePile,
                );
              });
            },
          );
        }
      }
      return;
    }

    // Default behavior for other games
    if (_cards.isEmpty) {
      assert(card.isBaseCard, 'Stock Pile is empty, but no Base Card present');
      card.position = position; // Force Base Card (back) into correct position.
      wastePile.removeAllCards().reversed.forEach((card) {
        card.flip();
        acquireCard(card);
      });
    } else {
      // Delegate draw policy to rules (how many to draw, etc.)
      if (!game.rules.canDrawFromStock(this)) {
        return;
      }
      final drawCount = game.rules.getStockDrawCount();
      for (var i = 0; i < drawCount; i++) {
        if (_cards.isNotEmpty) {
          final card = _cards.removeLast();
          card.doMoveAndFlip(
            wastePile.position,
            whenDone: () {
              wastePile.acquireCard(card);
            },
          );
        }
      }
    }
  }

  //#region Rendering

  final _borderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 10
    ..color = const Color(0xFF3F5B5D);
  final _circlePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 100
    ..color = const Color(0x883F5B5D);

  @override
  void render(Canvas canvas) {
    canvas.drawRRect(KlondikeGame.cardRRect, _borderPaint);
    canvas.drawCircle(Offset(width / 2, height / 2), KlondikeGame.cardWidth * 0.3, _circlePaint);
  }

  //#endregion
}
