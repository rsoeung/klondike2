import 'package:flutter/foundation.dart';
import 'dart:ui';

import 'package:flame/components.dart';

import '../klondike_game.dart';
import '../pile.dart';
import 'card.dart';
import '../rules/catte_rules.dart';
import '../rules/catte_trick_rules.dart';

class TableauPile extends PositionComponent with HasGameReference<KlondikeGame> implements Pile {
  TableauPile({super.position}) : super(size: KlondikeGame.cardSize) {
    debugPrint('TableauPile created at position: [32m$position[0m');
  }

  /// Which cards are currently placed onto this pile.
  final List<Card> _cards = [];

  /// Read-only exposure of cards for non-Klondike rule engines (e.g., CatTe).
  List<Card> get cards => List.unmodifiable(_cards);
  final Vector2 _fanOffset1 = Vector2(0, KlondikeGame.cardHeight * 0.05);
  final Vector2 _fanOffset2 = Vector2(0, KlondikeGame.cardHeight * 0.2);

  //#region Pile API

  @override
  bool canMoveCard(Card card, MoveMethod method) {
    final result = card.isFaceUp && (method == MoveMethod.drag || card == _cards.last);
    debugPrint('canMoveCard called for card: $card, method: $method, result: $result');
    return result;
  }
  // Drag can move multiple cards: tap can move last card only (to Foundation).

  @override
  bool canAcceptCard(Card card) {
    // Delegate to rules first; if rules veto, return false.
    final rules = game.rules;
    // Find top card if present to pass context.
    final Card? topCard = _cards.isEmpty ? null : _cards.last;
    try {
      if (!rules.canDropOnTableau(moving: card, onTop: topCard)) {
        return false;
      }
    } catch (_) {
      // If rules not wired yet, fall back silently
    }
    if (_cards.isEmpty) {
      debugPrint('canAcceptCard: pile empty, card rank: ${card.rank.value}');
      return card.rank.value == 13;
    } else {
      final topCard = _cards.last;
      final result =
          card.suit.isRed == !topCard.suit.isRed && card.rank.value == topCard.rank.value - 1;
      debugPrint('canAcceptCard: topCard: $topCard, card: $card, result: $result');
      return result;
    }
  }

  @override
  void removeCard(Card card, MoveMethod method) {
    // In CatTe trick mode a card may be removed after being intentionally folded
    // face-down. So only enforce face-up invariant for Klondike (stacking) mode.
    if (game.rules is! CatTeTrickRules) {
      assert(_cards.contains(card) && card.isFaceUp);
    } else {
      assert(_cards.contains(card));
    }
    debugPrint('removeCard called for card: $card, method: $method');
    final index = _cards.indexOf(card);

    // CatTe variants: allow plucking a single interior card without taking the stack above it.
    if (game.rules is CatTeRules || game.rules is CatTeTrickRules) {
      _cards.removeAt(index);
      // Reassign priorities to maintain stable ordering.
      for (var i = 0; i < _cards.length; i++) {
        _cards[i].priority = i;
      }
      layOutCards();
      return;
    }

    // Klondike (and other stacking games): remove the card and everything above it.
    _cards.removeRange(index, _cards.length);
    if (_cards.isNotEmpty && _cards.last.isFaceDown) {
      debugPrint('removeCard: flipping top card');
      flipTopCard();
      return;
    }
    layOutCards();
  }

  @override
  void returnCard(Card card) {
    debugPrint('returnCard called for card: $card');
    card.priority = _cards.indexOf(card);
    layOutCards();
  }

  @override
  void acquireCard(Card card) {
    debugPrint('acquireCard called for card: $card');
    card.pile = this;
    card.priority = _cards.length;
    _cards.add(card);
    layOutCards();
  }

  //#endregion

  void dropCards(Card firstCard, [List<Card> attachedCards = const []]) {
    debugPrint('dropCards called for firstCard: $firstCard, attachedCards: $attachedCards');
    final cardList = [firstCard];
    cardList.addAll(attachedCards);
    Vector2 nextPosition = _cards.isEmpty ? position : _cards.last.position;
    var nCardsToMove = cardList.length;
    for (final card in cardList) {
      card.pile = this;
      card.priority = _cards.length;
      if (_cards.isNotEmpty) {
        nextPosition = nextPosition + (card.isFaceDown ? _fanOffset1 : _fanOffset2);
      }
      _cards.add(card);
      card.doMove(
        nextPosition,
        startPriority: card.priority,
        onComplete: () {
          nCardsToMove--;
          debugPrint('dropCards: card moved, remaining: $nCardsToMove');
          if (nCardsToMove == 0) {
            debugPrint('dropCards: all cards moved, expanding hit-area');
            calculateHitArea(); // Expand the hit-area.
          }
        },
      );
    }
  }

  void flipTopCard({double start = 0.1}) {
    assert(_cards.last.isFaceDown);
    debugPrint('flipTopCard called, flipping: ${_cards.last}');
    _cards.last.turnFaceUp(
      start: start,
      onComplete: () {
        debugPrint('flipTopCard: card flipped, laying out cards');
        layOutCards();
      },
    );
  }

  void layOutCards() {
    debugPrint('layOutCards called, cards: $_cards');
    if (_cards.isEmpty) {
      debugPrint('layOutCards: pile empty, shrinking hit-area');
      calculateHitArea(); // Shrink hit-area when all cards have been removed.
      return;
    }
    _cards[0].position.setFrom(position);
    _cards[0].priority = 0;
    for (var i = 1; i < _cards.length; i++) {
      _cards[i].priority = i;
      _cards[i].position
        ..setFrom(_cards[i - 1].position)
        ..add(_cards[i - 1].isFaceDown ? _fanOffset1 : _fanOffset2);
    }
    calculateHitArea(); // Adjust hit-area to more cards or fewer cards.
  }

  void calculateHitArea() {
    height =
        KlondikeGame.cardHeight * 1.5 + (_cards.length < 2 ? 0.0 : _cards.last.y - _cards.first.y);
    debugPrint('calculateHitArea called, new height: $height');
  }

  List<Card> cardsOnTop(Card card) {
    assert(card.isFaceUp && _cards.contains(card));
    final index = _cards.indexOf(card);
    debugPrint('cardsOnTop called for card: $card, index: $index');
    return _cards.getRange(index + 1, _cards.length).toList();
  }

  //#region Rendering

  final _borderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 10
    ..color = const Color(0x50ffffff);

  @override
  void render(Canvas canvas) {
    //debugPrint('render called for TableauPile at position: $position');
    canvas.drawRRect(KlondikeGame.cardRRect, _borderPaint);
  }

  //#endregion
}
