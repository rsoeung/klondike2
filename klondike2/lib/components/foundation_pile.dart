import 'dart:ui';

import 'package:flame/components.dart';

import '../klondike_game.dart';
import '../pile.dart';
import '../suit.dart';
import 'card.dart';

class FoundationPile extends PositionComponent with HasGameReference<KlondikeGame> implements Pile {
  FoundationPile(int intSuit, this.checkWin, {super.position})
    : suit = Suit.fromInt(intSuit),
      super(size: KlondikeGame.cardSize);

  final VoidCallback checkWin;

  final Suit suit;
  final List<Card> _cards = [];

  //#region Pile API

  bool get isFull => _cards.length == 13;

  @override
  bool canMoveCard(Card card, MoveMethod method) =>
      _cards.isNotEmpty && card == _cards.last && method != MoveMethod.tap;

  @override
  bool canAcceptCard(Card card) {
    // Delegate to rules first; if a ruleset allows all, fall back to default.
    final rules = game.rules;
    final allow = rules.canDropOnFoundation(moving: card, foundation: this);
    if (!allow) return false;
    if (!rules.usesKlondikeFoundationSequence) {
      // Non-Klondike sequence: accept any single top card (no building rules enforced here).
      return card.attachedCards.isEmpty;
    }
    // Klondike behavior: suit match & ascending rank.
    final topCardRank = _cards.isEmpty ? 0 : _cards.last.rank.value;
    return card.suit == suit && card.rank.value == topCardRank + 1 && card.attachedCards.isEmpty;
  }

  @override
  void removeCard(Card card, MoveMethod method) {
    assert(canMoveCard(card, method));
    _cards.removeLast();
  }

  @override
  void returnCard(Card card) {
    card.position = position;
    card.priority = _cards.indexOf(card);
  }

  @override
  void acquireCard(Card card) {
    assert(card.isFaceUp);
    card.position = position;
    card.priority = _cards.length;
    card.pile = this;
    _cards.add(card);
    if (isFull) {
      checkWin(); // Get KlondikeWorld to check all FoundationPiles.
    }
  }

  //#endregion

  //#region Rendering

  final _borderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 10
    ..color = const Color(0x50ffffff);
  late final _suitPaint = Paint()
    ..color = suit.isRed ? const Color(0x3a000000) : const Color(0x64000000)
    ..blendMode = BlendMode.luminosity;

  @override
  void render(Canvas canvas) {
    canvas.drawRRect(KlondikeGame.cardRRect, _borderPaint);
    // Only show suit icon for classic Klondike-style foundations.
    if (game.rules.usesKlondikeFoundationSequence) {
      suit.sprite.render(
        canvas,
        position: size / 2,
        anchor: Anchor.center,
        size: Vector2.all(KlondikeGame.cardWidth * 0.6),
        overridePaint: _suitPaint,
      );
    }
  }

  //#endregion
}
