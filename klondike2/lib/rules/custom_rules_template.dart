import 'package:flame/components.dart';

import '../components/card.dart';
import '../components/foundation_pile.dart';
import '../components/stock_pile.dart';
import '../components/tableau_pile.dart';
import '../components/waste_pile.dart';
import '../klondike_game.dart';
import 'game_rules.dart';

/// A minimal example ruleset you can modify to build your custom game.
class CustomRules implements GameRules {
  @override
  String get name => 'Custom';

  @override
  bool get usesBaseCard => false;

  @override
  Vector2 get playAreaSize => Vector2(
    6 * KlondikeGame.cardSpaceWidth + KlondikeGame.cardGap,
    3 * KlondikeGame.cardSpaceHeight + KlondikeGame.topGap,
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
    // Example: two rows of tableaus, no foundations.
    foundations.clear();

    tableaus.clear();
    for (var i = 0; i < 6; i++) {
      tableaus.add(
        TableauPile(position: Vector2(i * cardSpaceWidth + cardGap, topGap)),
      );
    }
    for (var i = 0; i < 6; i++) {
      tableaus.add(
        TableauPile(
          position: Vector2(
            i * cardSpaceWidth + cardGap,
            topGap + cardSpaceHeight,
          ),
        ),
      );
    }

    stock.position = Vector2(cardGap, topGap + 2 * cardSpaceHeight);
    waste.position = Vector2(
      cardSpaceWidth + cardGap,
      topGap + 2 * cardSpaceHeight,
    );
  }

  @override
  void deal({
    required List<Card> deck,
    required List<TableauPile> tableaus,
    required StockPile stock,
    required WastePile waste,
    required int seed,
  }) {
    // Simple deal: first half to top row, next half to bottom row.
    final half = deck.length ~/ 2;
    var idx = 0;
    for (var i = 0; i < tableaus.length && idx < half; i++) {
      final card = deck[idx++];
      card.position = tableaus[i].position;
      tableaus[i].acquireCard(card);
    }
    for (var i = 0; i < tableaus.length && idx < deck.length; i++) {
      final card = deck[idx++];
      card.position = tableaus[i].position;
      tableaus[i].acquireCard(card);
    }
  }

  @override
  bool canMoveFromTableau(Card card) => card.isFaceUp;

  @override
  bool canDropOnTableau({required Card moving, required Card? onTop}) => true;

  @override
  bool canDropOnFoundation({
    required Card moving,
    required FoundationPile foundation,
  }) => true;

  @override
  bool canDrawFromStock(StockPile stock) => true;

  @override
  bool checkWin({required List<FoundationPile> foundations}) => false;
}
