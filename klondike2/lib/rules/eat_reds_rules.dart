import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';

import '../components/card.dart';
import '../components/foundation_pile.dart';
import '../components/stock_pile.dart';
import '../components/tableau_pile.dart';
import '../components/waste_pile.dart';
import '../klondike_game.dart';
import '../pile.dart';
import 'game_rules.dart';

/// EatRedsRules implements the "Eat Reds" (Chinese Ten) card game.
///
/// Objective: Capture red cards from the layout by pairing cards that sum to 10,
/// or matching face cards/10s with cards of the same rank.
///
/// Game Flow:
/// 1. Deal cards to players based on player count (24 cards total distributed)
/// 2. Place 4 cards face-up in the center as the initial layout
/// 3. Players take turns:
///    a. Play a card from hand to capture cards on table (if possible)
///    b. Draw a card from stock and attempt capture
/// 4. Game ends when stock is empty and last player runs out of cards
/// 5. Score captured red cards, highest score wins
class EatRedsRules implements GameRules {
  EatRedsRules({int playerCount = 2}) : _playerCount = playerCount;

  int _playerCount; // 2-4 players supported
  int _currentPlayerIndex = 0;
  int? _gameWinnerIndex;
  bool _gameOver = false;
  int _stockCardsRemaining = 0;

  // Getter for current player count
  int get playerCount => _playerCount;

  // Method to change player count (triggers re-deal)
  void setPlayerCount(int count) {
    if (count >= 2 && count <= 4) {
      _playerCount = count;
      debugPrint('EatReds player count changed to $_playerCount');
    }
  }

  // Captured cards piles for each player (using foundations as score piles)
  final List<List<Card>> _capturedCards = [];

  // Cards in the center layout (using waste pile area for layout)
  final List<Card> _layoutCards = [];

  // Track if we're in the card-drawing phase of a turn
  bool _awaitingStockDraw = false;

  @override
  String get name => 'Eat Reds (Chinese Ten)';

  @override
  Vector2 get playAreaSize => Vector2(
    7 * KlondikeGame.cardSpaceWidth + KlondikeGame.cardGap,
    4 * KlondikeGame.cardSpaceHeight + KlondikeGame.topGap,
  );

  @override
  bool get usesBaseCard => true;

  @override
  bool get usesWaste => true;

  @override
  bool get usesKlondikeFoundationSequence => false;

  int get currentPlayerIndex => _currentPlayerIndex;
  int? get gameWinnerIndex => _gameWinnerIndex;
  bool get gameOver => _gameOver;
  bool get awaitingStockDraw => _awaitingStockDraw;
  List<Card> get layoutCards => List.unmodifiable(_layoutCards);

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
    // Clear existing piles
    foundations.clear();
    tableaus.clear();
    _capturedCards.clear();
    _layoutCards.clear();

    // Stock pile in top-left
    stock.position = Vector2(cardGap, topGap);

    // Waste pile serves as the center layout area
    waste.position = Vector2(3 * cardSpaceWidth + cardGap, 2 * cardSpaceHeight + topGap);

    // Create tableau piles for each player's hand
    for (var i = 0; i < playerCount; i++) {
      final x = i * cardSpaceWidth + cardGap;
      final y = 3 * cardSpaceHeight + topGap; // Bottom row for player hands
      tableaus.add(TableauPile(position: Vector2(x, y)));
    }

    // Create foundation piles for captured cards (one per player)
    for (var i = 0; i < playerCount; i++) {
      final x = (i + 3) * cardSpaceWidth + cardGap; // Right side of board
      final y = topGap;
      foundations.add(FoundationPile(i % 4, checkWin, position: Vector2(x, y)));
      _capturedCards.add(<Card>[]);
    }

    // Reset game state
    _currentPlayerIndex = 0;
    _gameWinnerIndex = null;
    _gameOver = false;
    _awaitingStockDraw = false;

    debugPrint('EatRedsRules setup complete for $playerCount players.');
  }

  @override
  void deal({
    required List<Card> deck,
    required List<TableauPile> tableaus,
    required StockPile stock,
    required WastePile waste,
    required int seed,
  }) {
    // Animated round-robin dealing similar to Cat Te
    deck.shuffle(Random(seed));

    // Give every card a base priority so they stay above the table during flight
    var prio = 1;
    for (final c in deck) {
      c.priority = prio++;
    }

    // Calculate cards per player (24 total cards distributed)
    final cardsPerPlayer = 24 ~/ playerCount;
    final totalPlayerCards = playerCount * cardsPerPlayer;

    debugPrint(
      'Dealing $cardsPerPlayer cards to each of $playerCount players (total: $totalPlayerCards).',
    );

    // Origin point to "fly" from (center top area)
    final origin = Vector2(
      (playAreaSize.x - KlondikeGame.cardWidth) * 0.5,
      KlondikeGame.topGap * 0.5 + KlondikeGame.cardGap,
    );

    // Place cards at origin first (face-down) for consistent animation start
    for (var i = 0; i < deck.length; i++) {
      final card = deck[i];
      card.position = origin.clone();
      if (!card.isFaceDown) {
        card.flip(); // Keep face-down during dealing
      }
    }

    var dealIndex = 0;
    var remaining = totalPlayerCards + 4; // Player cards + 4 layout cards

    void afterAllLanded() {
      debugPrint('EatRedsRules deal complete (animated).');
      // Check for special initial layout conditions after all cards are dealt
      _checkInitialLayoutRules(tableaus);
    }

    // Deal cards to players first (round-robin style)
    for (var round = 0; round < cardsPerPlayer; round++) {
      for (var player = 0; player < playerCount; player++) {
        final cardIndex = round * playerCount + player;
        if (cardIndex < deck.length) {
          final card = deck[cardIndex];
          final targetPile = tableaus[player];
          final delay = dealIndex * 0.08; // Slightly slower for Eat Reds

          card.doMove(
            targetPile.position,
            speed: 16,
            start: delay,
            startPriority: 200 + dealIndex,
            onComplete: () {
              targetPile.acquireCard(card);
              if (card.isFaceDown) {
                card.flip(); // Flip face-up when landing
              }
              remaining--;
              if (remaining == 0) afterAllLanded();
            },
          );
          dealIndex++;
        }
      }
    }

    // Deal 4 cards to center layout
    for (var i = 0; i < 4; i++) {
      final cardIndex = totalPlayerCards + i;
      if (cardIndex < deck.length) {
        final card = deck[cardIndex];
        final offset = Vector2(i * 30, i * 8); // Spread layout cards
        final targetPos = waste.position + offset;
        final delay = dealIndex * 0.08;

        card.doMove(
          targetPos,
          speed: 16,
          start: delay,
          startPriority: 200 + dealIndex,
          onComplete: () {
            if (card.isFaceDown) {
              card.flip(); // Layout cards face-up
            }
            _layoutCards.add(card);
            remaining--;
            if (remaining == 0) afterAllLanded();
          },
        );
        dealIndex++;
      }
    }

    // Remaining cards go to stock (no animation needed)
    final stockStartIndex = totalPlayerCards + 4;
    for (var i = stockStartIndex; i < deck.length; i++) {
      final card = deck[i];
      card.position = stock.position;
      stock.acquireCard(card);
      _stockCardsRemaining++;
    }

    debugPrint('EatRedsRules animated dealing started. Total animations: $dealIndex');
  }

  /// Check special rules for initial layout (3-of-a-kind or all same rank)
  void _checkInitialLayoutRules(List<TableauPile> tableaus) {
    if (_layoutCards.length < 4) return;

    // Count ranks in initial layout
    final rankCounts = <int, int>{};
    for (final card in _layoutCards) {
      rankCounts.update(card.rank.value, (v) => v + 1, ifAbsent: () => 1);
    }

    // Check for 3-of-a-kind of face cards, 10s, or 5s
    for (final entry in rankCounts.entries) {
      final rank = entry.key;
      final count = entry.value;

      if (count >= 3 && (rank >= 10 || rank == 1 || rank == 5)) {
        // Face cards (J=11,Q=12,K=13), 10s, Aces, 5s
        debugPrint('Initial layout has $count cards of rank $rank - dealer captures them.');
        // Dealer (last player in turn order) captures these cards
        final dealerIndex = (playerCount - 1);
        final cardsToCapture = _layoutCards.where((c) => c.rank.value == rank).toList();
        for (final card in cardsToCapture) {
          _layoutCards.remove(card);
          _capturedCards[dealerIndex].add(card);
        }
      }
    }

    // Check if all 4 cards are face cards, 10s, or 5s
    final allSpecial = _layoutCards.every(
      (c) => c.rank.value >= 10 || c.rank.value == 1 || c.rank.value == 5,
    );

    if (allSpecial && _layoutCards.length == 4) {
      debugPrint('All initial layout cards are special ranks - dealer captures all.');
      final dealerIndex = (playerCount - 1);
      for (final card in _layoutCards.toList()) {
        _layoutCards.remove(card);
        _capturedCards[dealerIndex].add(card);
      }
    }
  }

  /// Attempt to capture cards from layout using the played card
  bool attemptCapture(Card playedCard, List<TableauPile> tableaus) {
    final captures = <Card>[];

    // Check for rank matching (face cards, 10s)
    if (playedCard.rank.value >= 10 || playedCard.rank.value == 1) {
      for (final layoutCard in _layoutCards) {
        if (layoutCard.rank.value == playedCard.rank.value) {
          captures.add(layoutCard);
          break; // Only capture one card per turn
        }
      }
    } else {
      // Check for sum-to-10 pairing
      final playedValue = playedCard.rank.value;
      for (final layoutCard in _layoutCards) {
        final layoutValue = layoutCard.rank.value == 1 ? 1 : layoutCard.rank.value; // Ace = 1
        if (playedValue + layoutValue == 10) {
          captures.add(layoutCard);
          break; // Only capture one card per turn
        }
      }
    }

    if (captures.isNotEmpty) {
      // Perform capture
      for (final captured in captures) {
        _layoutCards.remove(captured);
        _capturedCards[_currentPlayerIndex].add(captured);
        _capturedCards[_currentPlayerIndex].add(playedCard); // Add played card too
      }
      debugPrint('Player $_currentPlayerIndex captured ${captures.length + 1} cards.');
      return true;
    } else {
      // No capture - add played card to layout
      _layoutCards.add(playedCard);
      debugPrint('Player $_currentPlayerIndex added card to layout. No capture.');
      return false;
    }
  }

  /// Draw a card from stock and attempt capture
  void drawFromStock(StockPile stock, WastePile waste) {
    if (_stockCardsRemaining <= 0) {
      _endGame();
      return;
    }

    // For Eat Reds, we need to implement custom stock drawing since the standard
    // stock pile behavior goes to waste pile. We'll need to modify this approach.
    // For now, we'll handle this through the standard game mechanics.

    _stockCardsRemaining--;
    _awaitingStockDraw = false;
    _advanceTurn();
  }

  void _advanceTurn() {
    _currentPlayerIndex = (_currentPlayerIndex + 1) % playerCount;

    // Check if current player has any cards left
    // If not, continue to next player or end game
    // This will be handled by the UI/game logic
  }

  void _endGame() {
    _gameOver = true;

    // Calculate scores
    final scores = <int, int>{};
    for (var i = 0; i < playerCount; i++) {
      scores[i] = _calculateScore(_capturedCards[i]);
    }

    // Find winner (highest score)
    var maxScore = -1;
    for (final entry in scores.entries) {
      if (entry.value > maxScore) {
        maxScore = entry.value;
        _gameWinnerIndex = entry.key;
      }
    }

    debugPrint(
      'Game over! Scores: $scores. Winner: Player $_gameWinnerIndex with $maxScore points.',
    );
  }

  int _calculateScore(List<Card> cards) {
    var score = 0;
    for (final card in cards) {
      if (card.suit.value <= 1) {
        // Hearts (0) and Diamonds (1) are red
        if (card.rank.value == 1) {
          // Red Ace
          score += 20;
        } else if (card.rank.value >= 9) {
          // Red face cards, 10s, 9s
          score += 10;
        } else {
          score += card.rank.value; // Pip value
        }
      }
      // Black cards (Clubs=2, Spades=3) worth 0 points
    }
    return score;
  }

  // GameRules interface implementation

  @override
  bool canMoveFromTableau(Card card) {
    if (_gameOver) return false;

    // Only current player can move cards from their tableau
    final pile = card.pile;
    if (pile is! TableauPile) return false;

    // Find which player this tableau belongs to
    final game = pile.game;
    final world = game.world as dynamic;
    final tableaus = world.tableauPiles as List<TableauPile>;
    final playerIndex = tableaus.indexOf(pile);

    return playerIndex == _currentPlayerIndex && !_awaitingStockDraw;
  }

  @override
  bool canDropOnTableau({required Card moving, required Card? onTop}) => false;

  @override
  bool canDropOnFoundation({required Card moving, required FoundationPile foundation}) => false;

  @override
  bool canDrawFromStock(StockPile stock) {
    return !_gameOver && _awaitingStockDraw && _stockCardsRemaining > 0;
  }

  @override
  bool checkWin({required List<FoundationPile> foundations}) => _gameOver;

  /// Public method for UI to play a card
  bool playCard(Card card, List<TableauPile> tableaus, StockPile stock) {
    if (!canMoveFromTableau(card)) return false;

    final pile = card.pile as TableauPile;
    pile.removeCard(card, MoveMethod.tap);

    attemptCapture(card, tableaus);

    // After playing from hand, must draw from stock
    _awaitingStockDraw = true;

    return true;
  }
}
