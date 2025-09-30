import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';

import '../components/card.dart';
import '../components/foundation_pile.dart';
import '../components/stock_pile.dart';
import '../components/tableau_pile.dart';
import '../components/waste_pile.dart';
import '../klondike_game.dart';
import '../klondike_world.dart';
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

  // Card selection system for manual play
  Card? _selectedHandCard;
  Card? _selectedLayoutCard;

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
  Card? get selectedHandCard => _selectedHandCard;
  Card? get selectedLayoutCard => _selectedLayoutCard;

  /// Check if play button should be enabled
  bool get canPlay {
    if (_selectedHandCard == null || _selectedLayoutCard == null) return false;
    return _canCapture(_selectedHandCard!, _selectedLayoutCard!);
  }

  /// Check if a hand card can capture a layout card
  bool _canCapture(Card handCard, Card layoutCard) {
    // Check for rank matching (face cards, 10s, aces)
    if (handCard.rank.value >= 10 || handCard.rank.value == 1) {
      return handCard.rank.value == layoutCard.rank.value;
    } else {
      // Check for sum-to-10 pairing
      final handValue = handCard.rank.value;
      final layoutValue = layoutCard.rank.value == 1 ? 1 : layoutCard.rank.value; // Ace = 1
      return handValue + layoutValue == 10;
    }
  }

  /// Select a card from current player's hand
  void selectHandCard(Card card) {
    // Only allow selection from current player's tableau
    final currentTableau = card.pile;
    if (currentTableau is TableauPile) {
      // Clear previous hand card selection
      if (_selectedHandCard != null) {
        _selectedHandCard!.setSelected(false);
      }

      // Check if this tableau belongs to current player
      // This assumes tableaus are indexed by player
      _selectedHandCard = card;
      card.setSelected(true);
      debugPrint('Selected hand card: ${card.rank} of ${card.suit}');
    }
  }

  /// Select a card from the center layout
  void selectLayoutCard(Card card) {
    if (_layoutCards.contains(card)) {
      // Clear previous layout card selection
      if (_selectedLayoutCard != null) {
        _selectedLayoutCard!.setSelected(false);
      }

      _selectedLayoutCard = card;
      card.setSelected(true);
      debugPrint('Selected layout card: ${card.rank} of ${card.suit}');
    }
  }

  /// Clear card selections
  void clearSelections() {
    if (_selectedHandCard != null) {
      _selectedHandCard!.setSelected(false);
      _selectedHandCard = null;
    }
    if (_selectedLayoutCard != null) {
      _selectedLayoutCard!.setSelected(false);
      _selectedLayoutCard = null;
    }
    debugPrint('Card selections cleared');
  }

  /// Execute the play action with selected cards
  bool executePlay(List<FoundationPile> foundations) {
    if (!canPlay) return false;

    final handCard = _selectedHandCard!;
    final layoutCard = _selectedLayoutCard!;

    // Remove cards from their current locations
    if (handCard.pile is TableauPile) {
      (handCard.pile as TableauPile).removeCard(handCard, MoveMethod.tap);
    }
    _layoutCards.remove(layoutCard);

    // Add both cards to current player's captured pile
    _capturedCards[_currentPlayerIndex].add(handCard);
    _capturedCards[_currentPlayerIndex].add(layoutCard);

    // Move cards to foundation pile (visually)
    _moveCardsToFoundation(handCard, layoutCard, _currentPlayerIndex, foundations);

    // Clear selections
    clearSelections();

    // After playing from hand, must draw from stock
    _awaitingStockDraw = true;

    debugPrint(
      'Player $_currentPlayerIndex captured cards. Score: ${getPlayerScore(_currentPlayerIndex)}',
    );
    return true;
  }

  /// Move captured cards to the foundation pile for visual representation
  void _moveCardsToFoundation(
    Card handCard,
    Card layoutCard,
    int playerIndex,
    List<FoundationPile> foundations,
  ) {
    if (playerIndex < foundations.length) {
      final foundation = foundations[playerIndex];

      // Ensure cards are face up before moving to foundation
      if (!handCard.isFaceUp) handCard.flip();
      if (!layoutCard.isFaceUp) layoutCard.flip();

      // Move both cards to the foundation pile
      foundation.acquireCard(handCard);
      foundation.acquireCard(layoutCard);
    }
  }

  /// Calculate player's score from captured cards
  int getPlayerScore(int playerIndex) {
    if (playerIndex >= _capturedCards.length) return 0;

    int score = 0;
    for (final card in _capturedCards[playerIndex]) {
      if (card.suit.isRed) {
        if (card.rank.value == 1) {
          // Red ace
          score += 20;
        } else if (card.rank.value >= 9) {
          // Red face cards, 10s, 9s
          score += 10;
        } else {
          // Other red cards
          score += card.rank.value;
        }
      }
      // Black cards = 0 points
    }
    return score;
  }

  /// Calculate position for a layout card based on its index in the layout
  Vector2 _getLayoutCardPosition(int index, Vector2 centerPos) {
    if (index < 4) {
      // Initial 4 cards in 2x2 grid
      final row = index ~/ 2;
      final col = index % 2;
      final offsetX = (col - 0.5) * (KlondikeGame.cardWidth + 20);
      final offsetY = (row - 0.5) * (KlondikeGame.cardHeight + 15);
      return centerPos + Vector2(offsetX, offsetY);
    } else {
      // Additional cards arranged in expanding spiral pattern
      final extraIndex = index - 4;
      final radius = 120.0 + (extraIndex ~/ 8) * 40; // Expanding rings
      final angle = (extraIndex % 8) * (pi * 2 / 8); // 8 positions per ring
      final offsetX = radius * cos(angle);
      final offsetY = radius * sin(angle);
      return centerPos + Vector2(offsetX, offsetY);
    }
  }

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

    // Waste pile serves as the center layout area - positioned higher and more centered
    waste.position = Vector2(2.5 * cardSpaceWidth + cardGap, 1.5 * cardSpaceHeight + topGap);

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

    // Deal 4 cards to center layout in a 2x2 grid pattern
    for (var i = 0; i < 4; i++) {
      final cardIndex = totalPlayerCards + i;
      if (cardIndex < deck.length) {
        final card = deck[cardIndex];
        final targetPos = _getLayoutCardPosition(i, waste.position);
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
  bool attemptCapture(Card playedCard, Vector2 centerPos) {
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
      // No capture - add played card to layout with proper positioning
      final newIndex = _layoutCards.length;
      final targetPos = _getLayoutCardPosition(newIndex, centerPos);
      playedCard.position = targetPos;
      _layoutCards.add(playedCard);
      debugPrint('Player $_currentPlayerIndex added card to layout. No capture.');
      return false;
    }
  }

  /// Draw a card from stock and add to layout (legacy method, interception handled in canDrawFromStock)
  void drawFromStock(StockPile stock, WastePile waste) {
    // The actual interception is now handled in canDrawFromStock and redirectWasteToLayout
    debugPrint('EatReds drawFromStock called - interception should be set up');
  }

  // Flag to intercept the next card that goes to waste pile
  bool _interceptNextWasteDraw = false;
  int _cardsInterceptedThisDraw = 0; // Track how many cards intercepted from current stock draw

  /// Check if we should intercept waste pile operations for EatReds
  bool shouldInterceptWaste() {
    if (!_interceptNextWasteDraw) return false;

    // Only intercept the first card from a multi-card stock draw
    if (_cardsInterceptedThisDraw >= 1) {
      return false;
    }

    return true;
  }

  /// Handle redirecting a card from waste to layout
  void redirectWasteToLayout(Card card, WastePile waste) {
    if (!shouldInterceptWaste()) return;

    _cardsInterceptedThisDraw++;
    debugPrint(
      'Intercepting card for layout: ${card.rank} of ${card.suit} (card #$_cardsInterceptedThisDraw)',
    );

    // After intercepting first card, disable further interception for this stock draw
    if (_cardsInterceptedThisDraw >= 1) {
      _interceptNextWasteDraw = false;
    }

    // Find the first empty position in the layout grid
    // Check positions 0-3 first (the initial 2x2 grid), then expand outward
    int targetIndex = _layoutCards.length; // Default to next position

    // For the initial 4 positions, try to find an empty spot
    if (_layoutCards.length < 4) {
      // Find first available position in the 2x2 grid
      final availablePositions = <int>[];
      for (int i = 0; i < 4; i++) {
        availablePositions.add(i);
      }

      // Remove positions that are occupied
      final occupiedPositions = <int>[];
      for (final layoutCard in _layoutCards) {
        // Calculate which grid position this card occupies based on its current position
        final cardPos = layoutCard.position;
        final wastePos = waste.position;
        final relativePos = cardPos - wastePos;

        // Determine grid position from relative coordinates
        for (int i = 0; i < 4; i++) {
          final testPos = _getLayoutCardPosition(i, wastePos);
          final testRelative = testPos - wastePos;
          if ((testRelative - relativePos).length < 10) {
            // Small tolerance for position matching
            occupiedPositions.add(i);
            break;
          }
        }
      }

      availablePositions.removeWhere((pos) => occupiedPositions.contains(pos));

      if (availablePositions.isNotEmpty) {
        targetIndex = availablePositions.first;
      }
    }

    final targetPos = _getLayoutCardPosition(targetIndex, waste.position);

    // Move card to layout position with animation
    card.doMove(
      targetPos,
      speed: 10,
      onComplete: () {
        // Add to layout cards for gameplay
        _layoutCards.add(card);
        debugPrint(
          'Drew card from stock to layout: ${card.rank} of ${card.suit} at position $targetIndex',
        );

        // Player can now make another selection
        _awaitingStockDraw = false;

        // Clear any existing selections to start fresh
        clearSelections();
      },
    );

    _stockCardsRemaining--;
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

    // Allow selection for current player (not awaiting stock draw)
    return playerIndex == _currentPlayerIndex && !_awaitingStockDraw;
  }

  /// Handle card tap for selection (replaces old automatic play)
  bool handleCardTap(Card card) {
    if (_gameOver) {
      debugPrint('Cannot select card: game is over');
      return false;
    }

    debugPrint('Attempting to select card: ${card.rank} of ${card.suit}');
    debugPrint('Current player: $_currentPlayerIndex, awaiting stock draw: $_awaitingStockDraw');

    // Check if it's a hand card from current player
    if (card.pile is TableauPile) {
      final pile = card.pile as TableauPile;
      final game = pile.game;
      final world = game.world as dynamic;
      final tableaus = world.tableauPiles as List<TableauPile>;
      final playerIndex = tableaus.indexOf(pile);

      debugPrint('Card is in tableau pile for player: $playerIndex');

      if (playerIndex == _currentPlayerIndex && !_awaitingStockDraw) {
        debugPrint('Selecting hand card');
        selectHandCard(card);
        return true;
      } else {
        debugPrint('Cannot select hand card: wrong player or awaiting stock draw');
      }
    }

    // Check if it's a layout card
    if (_layoutCards.contains(card)) {
      debugPrint('Selecting layout card');
      selectLayoutCard(card);
      return true;
    }

    debugPrint('Card selection failed: not a valid card to select');
    return false;
  }

  @override
  bool canDropOnTableau({required Card moving, required Card? onTop}) => false;

  @override
  bool canDropOnFoundation({required Card moving, required FoundationPile foundation}) => false;

  @override
  bool canDrawFromStock(StockPile stock) {
    if (_gameOver || _stockCardsRemaining <= 0) return false;

    if (_awaitingStockDraw) {
      // Reset counter and set up interception for the next waste pile card
      _cardsInterceptedThisDraw = 0;
      _interceptNextWasteDraw = true;
      debugPrint('EatReds: Setting up stock draw interception');
      return true;
    }

    return false;
  }

  @override
  bool checkWin({required List<FoundationPile> foundations}) => _gameOver;

  /// Public method for UI to play a card (now handles selection)
  bool playCard(Card card, List<TableauPile> tableaus, StockPile stock) {
    // Use the new selection system instead of immediate play
    return handleCardTap(card);
  }
}
