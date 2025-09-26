import 'dart:math';

import 'package:flame/components.dart';

import '../components/card.dart';
import '../components/foundation_pile.dart';
import '../components/stock_pile.dart';
import '../components/tableau_pile.dart';
import '../components/waste_pile.dart';
import '../klondike_game.dart';
import 'game_rules.dart';

class KlondikeRules implements GameRules {
  @override
  String get name => 'Klondike';

  @override
  bool get usesBaseCard => true;
  @override
  bool get usesWaste => true;
  @override
  bool get usesKlondikeFoundationSequence => true;

  @override
  Vector2 get playAreaSize => Vector2(
    7 * KlondikeGame.cardSpaceWidth + KlondikeGame.cardGap,
    4 * KlondikeGame.cardSpaceHeight + KlondikeGame.topGap,
  );

  @override
  void setupPiles({
    required Vector2 cardSize,
    required double cardGap,
    required double topGap,
    required double cardSpaceWidth,
    required double cardSpaceHeight,
    required StockPile stock,
    required WastePile waste,
    required List<FoundationPile> foundations,
    required List<TableauPile> tableaus,
    required void Function() checkWin,
  }) {
    stock.position = Vector2(cardGap, topGap);
    waste.position = Vector2(cardSpaceWidth + cardGap, topGap);

    foundations.clear();
    for (var i = 0; i < 4; i++) {
      foundations.add(
        FoundationPile(i, checkWin, position: Vector2((i + 3) * cardSpaceWidth + cardGap, topGap)),
      );
    }

    tableaus.clear();
    for (var i = 0; i < 7; i++) {
      tableaus.add(
        TableauPile(position: Vector2(i * cardSpaceWidth + cardGap, cardSpaceHeight + topGap)),
      );
    }
  }

  @override
  void deal({
    required List<Card> deck,
    required List<TableauPile> tableaus,
    required StockPile stock,
    required WastePile waste,
    required int seed,
  }) {
    // Shuffle
    deck.shuffle(Random(seed));

    // Priorities visible while dealing
    var prio = 1;
    for (final c in deck) {
      c.priority = prio++;
    }

    // Tableau fan deal
    var idx = deck.length - 1;
    for (var i = 0; i < tableaus.length; i++) {
      for (var j = i; j < tableaus.length; j++) {
        final card = deck[idx--];
        card.doMove(
          tableaus[j].position,
          speed: 15,
          start: (i + j) * 0.1,
          startPriority: 100 + (i + j),
          onComplete: () {
            // Place the card on the tableau.
            tableaus[j].acquireCard(card);
            // When i == j this is the last (top) card for tableau j in Klondike.
            // Flip it face-up after it lands.
            if (i == j) {
              tableaus[j].flipTopCard(start: 0.1);
            }
          },
        );
      }
    }

    // Remaining to stock
    for (var n = 0; n <= idx; n++) {
      stock.acquireCard(deck[n]);
    }
  }

  @override
  bool canMoveFromTableau(Card card) => card.isFaceUp;

  @override
  bool canDropOnTableau({required Card moving, required Card? onTop}) {
    if (onTop == null) {
      return moving.rank.value == 13; // King on empty
    }
    return moving.suit.isRed == !onTop.suit.isRed && moving.rank.value == onTop.rank.value - 1;
  }

  @override
  bool canDropOnFoundation({required Card moving, required FoundationPile foundation}) {
    // Let FoundationPile.canAcceptCard enforce exact rules in current codebase.
    // This method can be tightened when pile logic is delegated to GameRules.
    return true;
  }

  @override
  bool canDrawFromStock(StockPile stock) => true;

  @override
  bool checkWin({required List<FoundationPile> foundations}) => foundations.every((f) => f.isFull);
}
