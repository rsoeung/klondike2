import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';

import '../components/card.dart';
import '../components/foundation_pile.dart';
import '../components/stock_pile.dart';
import '../components/tableau_pile.dart';
import '../components/waste_pile.dart';
import '../klondike_game.dart';
import 'game_rules.dart';

/// CatTe rules:
/// - 6 tableau piles in a single row
/// - 6 foundation piles directly above each tableau (1:1 mapping)
/// - Deal: 6 face-up cards to each tableau (total 36 cards). Remaining cards go to waste.
/// - Waste is inert (no draws, no moves from it).
/// - Stock is unused (no base card needed).
/// - Any single face-up card from a tableau column may be moved directly to
///   its corresponding foundation column (same index). Interior cards do NOT
///   drag any cards that were above them; those cards collapse downward.
class CatTeRules implements GameRules {
  // Track which tableau's turn it is. This is mutable game state.
  int currentTurn = 0;

  @override
  String get name => 'CatTe';

  @override
  bool get usesBaseCard => false; // No stock placeholder needed.
  @override
  bool get usesWaste => false; // Remove waste pile entirely.
  @override
  bool get usesKlondikeFoundationSequence => false;

  @override
  Vector2 get playAreaSize => Vector2(
    6 * KlondikeGame.cardSpaceWidth + KlondikeGame.cardGap,
    // Two rows (foundations + tableau) plus a gap region below for waste.
    2 * KlondikeGame.cardSpaceHeight + KlondikeGame.topGap,
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
    required VoidCallback checkWin,
  }) {
    // Position 6 foundations across the top row.
    foundations.clear();
    for (var i = 0; i < 6; i++) {
      // Use modulo to map 6 columns onto 4 available suit sprites.
      foundations.add(
        FoundationPile(i % 4, checkWin, position: Vector2(i * cardSpaceWidth + cardGap, topGap)),
      );
    }

    // Position 6 tableau piles directly below foundations.
    tableaus.clear();
    for (var i = 0; i < 6; i++) {
      tableaus.add(
        TableauPile(position: Vector2(i * cardSpaceWidth + cardGap, topGap + cardSpaceHeight)),
      );
    }

    // Hide stock & waste (not used in CatTe).
    stock.position = Vector2(-99999, -99999);
    waste.position = Vector2(-99999, -99999);

    currentTurn = 0;
    debugPrint('CatTe setup complete. Starting turn index: $currentTurn');
  }

  @override
  void deal({
    required List<Card> deck,
    required List<TableauPile> tableaus,
    required StockPile stock,
    required WastePile waste,
    required int seed,
  }) {
    // Shuffle deck.
    deck.shuffle(Random(seed));
    // Deal exactly 6 cards face-up to each tableau (total 36) and ignore rest.
    var idx = 0;
    for (var t = 0; t < 6; t++) {
      for (var c = 0; c < 6; c++) {
        final card = deck[idx++];
        card.position = tableaus[t].position;
        if (card.isFaceDown) card.flip();
        tableaus[t].acquireCard(card);
      }
    }
    debugPrint('CatTe deal complete. 6 cards per tableau; remaining cards unused.');
  }

  @override
  bool canMoveFromTableau(Card card) {
    // Any single face-up card may be selected (top or interior). Interior
    // selection will not bring along cards above it.
    final pile = card.pile;
    if (pile is! TableauPile) return false;
    return card.isFaceUp;
  }

  @override
  bool canDropOnTableau({required Card moving, required Card? onTop}) => false; // No tableau building.

  @override
  bool canDropOnFoundation({required Card moving, required FoundationPile foundation}) {
    // Allow drop if the card came from the tableau column directly beneath this
    // foundation (same index). It can be an interior card; CatTe permits
    // plucking single interior cards. Top-ness is not required.
    final pile = moving.pile;
    if (pile is! TableauPile) return false;
    final game = pile.game;
    final world = game.world as dynamic;
    final tableaus = world.tableauPiles as List<TableauPile>;
    final foundationsList = world.foundations as List<FoundationPile>;
    final tableauIndex = tableaus.indexOf(pile);
    final foundationIndex = foundationsList.indexOf(foundation);
    final allowed = foundationIndex == tableauIndex && moving.isFaceUp;
    debugPrint(
      'CatTe canDropOnFoundation tableau=$tableauIndex foundation=$foundationIndex faceUp=${moving.isFaceUp} => $allowed',
    );
    return allowed;
  }

  @override
  bool canDrawFromStock(StockPile stock) => false; // Disabled.

  @override
  bool checkWin({required List<FoundationPile> foundations}) {
    // Placeholder: win when each foundation has at least one card.
    // Placeholder: Win when every foundation has at least one card.
    return false; // Win logic not defined yet.
  }
}
