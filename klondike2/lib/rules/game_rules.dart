import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';

import '../components/card.dart';
import '../components/foundation_pile.dart';
import '../components/stock_pile.dart';
import '../components/tableau_pile.dart';
import '../components/waste_pile.dart';

/// GameRules is an abstraction over pile setup, dealing, moves, and win checks.
/// Implement this to create new card games without rewriting rendering/UX.
abstract class GameRules {
  String get name;

  // Layout
  Vector2 get playAreaSize; // computed after setup if dynamic

  // Whether the Stock pile should show a base/back card in the stack
  bool get usesBaseCard => false;

  // Setup piles & cards positions
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
    required VoidCallback checkWin,
  });

  // Initial dealing/shuffling
  void deal({
    required List<Card> deck,
    required List<TableauPile> tableaus,
    required StockPile stock,
    required WastePile waste,
    required int seed,
  });

  // Move/accept rules
  bool canMoveFromTableau(Card card);
  bool canDropOnTableau({required Card moving, required Card? onTop});
  bool canDropOnFoundation({
    required Card moving,
    required FoundationPile foundation,
  });
  bool canDrawFromStock(StockPile stock);

  // Win condition
  bool checkWin({required List<FoundationPile> foundations});
}
