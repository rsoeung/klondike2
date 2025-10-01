import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Card;

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
  int get stockCardsRemaining => _stockCardsRemaining;
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
    // Get pip values for gameplay (different from scoring values)
    final handPipValue = _getGameplayValue(handCard);
    final layoutPipValue = _getGameplayValue(layoutCard);

    // Face cards and 10s are captured by rank matching
    if ((handCard.rank.value >= 10) || (layoutCard.rank.value >= 10)) {
      return handCard.rank.value == layoutCard.rank.value;
    } else {
      // All other cards (A, 2-9) are captured by sum-to-10 pairing
      return handPipValue + layoutPipValue == 10;
    }
  }

  /// Get the gameplay/pip value of a card (different from scoring value)
  int _getGameplayValue(Card card) {
    if (card.rank.value == 1) {
      return 1; // Ace = 1 for gameplay
    } else if (card.rank.value >= 10) {
      return 10; // Face cards and 10 = 10 for gameplay
    } else {
      return card.rank.value; // 2-9 = pip value
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
      debugPrint('Selected hand card: ${card.rank.label} of ${card.suit.label}');

      // Update capture highlights for layout cards
      _updateCaptureHighlights();
    }
  }

  /// Select a card from the center layout
  void selectLayoutCard(Card card) {
    debugPrint('selectLayoutCard called for: ${card.rank.label} of ${card.suit.label}');
    debugPrint('Layout cards count: ${_layoutCards.length}');
    debugPrint('Card in layout cards: ${_layoutCards.contains(card)}');
    debugPrint('Game over: $_gameOver, awaiting stock draw: $_awaitingStockDraw');
    debugPrint('Current player: $_currentPlayerIndex');

    if (_layoutCards.contains(card)) {
      // Clear previous layout card selection
      if (_selectedLayoutCard != null) {
        _selectedLayoutCard!.setSelected(false);
        debugPrint('Cleared previous layout card selection');
      }

      _selectedLayoutCard = card;
      card.setSelected(true);
      debugPrint('Selected layout card: ${card.rank.label} of ${card.suit.label}');
    } else {
      debugPrint('ERROR: Card not found in layout cards list!');
      debugPrint('Available layout cards:');
      for (int i = 0; i < _layoutCards.length; i++) {
        final layoutCard = _layoutCards[i];
        debugPrint('  [$i]: ${layoutCard.rank.label} of ${layoutCard.suit.label}');
      }
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

    // Clear capture highlights when selections are cleared
    _clearCaptureHighlights();

    debugPrint('Card selections cleared');
  }

  /// Clear selection if the card was removed from play
  void _clearSelectionIfRemoved(Card card) {
    if (_selectedHandCard == card) {
      _selectedHandCard = null;
      debugPrint('Cleared selected hand card that was removed from play');
    }
    if (_selectedLayoutCard == card) {
      _selectedLayoutCard = null;
      debugPrint('Cleared selected layout card that was removed from play');
    }
  }

  /// Execute the play action with selected cards
  bool executePlay(List<FoundationPile> foundations) {
    if (!canPlay) return false;

    final handCard = _selectedHandCard!;
    final layoutCard = _selectedLayoutCard!;

    // Check if "hand card" is actually from layout (stock card)
    final isStockCardCapture = _layoutCards.contains(handCard);

    // Remove cards from their current locations
    if (!isStockCardCapture && handCard.pile is TableauPile) {
      (handCard.pile as TableauPile).removeCard(handCard, MoveMethod.tap);
    }

    // Remove both cards from layout if it's a stock card capture
    if (isStockCardCapture) {
      _layoutCards.remove(handCard);
      _clearSelectionIfRemoved(handCard);
    }
    _layoutCards.remove(layoutCard);
    _clearSelectionIfRemoved(layoutCard);

    // Refresh layout positions to maintain compact grid
    _refreshLayoutPositions();

    // Add both cards to current player's captured pile
    _capturedCards[_currentPlayerIndex].add(handCard);
    _capturedCards[_currentPlayerIndex].add(layoutCard);

    debugPrint('Added cards to player $_currentPlayerIndex captured pile:');
    debugPrint(
      '  Hand card: ${handCard.rank} of ${handCard.suit} (${handCard.suit.isRed ? "RED" : "BLACK"})',
    );
    debugPrint(
      '  Layout card: ${layoutCard.rank} of ${layoutCard.suit} (${layoutCard.suit.isRed ? "RED" : "BLACK"})',
    );
    debugPrint(
      '  Total captured cards for player $_currentPlayerIndex: ${_capturedCards[_currentPlayerIndex].length}',
    );

    // Move cards to foundation pile (visually)
    _moveCardsToFoundation(handCard, layoutCard, _currentPlayerIndex, foundations);

    // Clear selections
    clearSelections();

    if (isStockCardCapture) {
      // Stock card capture - advance to next player immediately
      _advanceToNextPlayer();
      debugPrint('Player $_currentPlayerIndex captured with stock card, advancing to next player');
    } else {
      // Regular hand card capture - must draw from stock
      _awaitingStockDraw = true;
      debugPrint('Player $_currentPlayerIndex captured with hand card, must draw from stock');
    }

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
    // debugPrint('Calculating score for player $playerIndex:');
    for (final card in _capturedCards[playerIndex]) {
      int cardPoints = 0;
      if (card.suit.isRed) {
        if (card.rank.value == 1) {
          // Red ace
          cardPoints = 20;
        } else if (card.rank.value >= 9) {
          // Red face cards, 10s, 9s
          cardPoints = 10;
        } else {
          // Other red cards
          cardPoints = card.rank.value;
        }
        score += cardPoints;
        // debugPrint('  ${card.rank.label} of ${card.suit.label}: +$cardPoints points');
      } else {
        // debugPrint('  ${card.rank.label} of ${card.suit.label}: +0 points (black)');
      }
      // Black cards = 0 points
    }
    // debugPrint('  Total score for player $playerIndex: $score');
    return score;
  }

  /// Find the next available position for a layout card, using a compact grid pattern
  int _findNextAvailableLayoutPosition() {
    // Simply return the next index - we'll arrange cards in a compact grid
    return _layoutCards.length;
  }

  /// Calculate position for a layout card based on its index in a compact grid layout
  Vector2 _getLayoutCardPosition(int index, Vector2 centerPos) {
    // Define grid dimensions
    const int cardsPerRow = 5; // 5 cards per row for a nice grid
    const double cardSpacingX = KlondikeGame.cardWidth + 20;
    const double cardSpacingY = KlondikeGame.cardHeight + 15;

    // Calculate row and column for this index
    final row = index ~/ cardsPerRow;
    final col = index % cardsPerRow;

    // Calculate the grid starting position (top-left of the grid)
    // Center the grid around the centerPos
    final gridWidth = cardsPerRow * cardSpacingX;
    final startX = centerPos.x - (gridWidth / 2) + (cardSpacingX / 2);
    final startY = centerPos.y - (cardSpacingY / 2); // Start slightly above center

    // Calculate final position
    final x = startX + (col * cardSpacingX);
    final y = startY + (row * cardSpacingY);

    return Vector2(x, y);
  }

  /// Refresh the positions of all layout cards to maintain compact grid
  void _refreshLayoutPositions() {
    final centerPos = Vector2(
      3.5 * KlondikeGame.cardSpaceWidth + KlondikeGame.cardGap,
      1.5 * KlondikeGame.cardSpaceHeight + KlondikeGame.topGap,
    );

    for (int i = 0; i < _layoutCards.length; i++) {
      final card = _layoutCards[i];
      final targetPos = _getLayoutCardPosition(i, centerPos);

      // Animate card to new position if it's not already there
      final currentDistance = (card.position - targetPos).length;
      if (currentDistance > 5.0) {
        card.doMove(targetPos, speed: 15);
      }
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
    waste.position = Vector2(3.5 * cardSpaceWidth + cardGap, 1.5 * cardSpaceHeight + topGap);

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

    // Face cards and 10s are captured by rank matching
    if (playedCard.rank.value >= 10) {
      for (final layoutCard in _layoutCards) {
        if (layoutCard.rank.value == playedCard.rank.value) {
          captures.add(layoutCard);
          break; // Only capture one card per turn
        }
      }
    } else {
      // All other cards (A, 2-9) are captured by sum-to-10 pairing
      final playedValue = _getGameplayValue(playedCard);
      for (final layoutCard in _layoutCards) {
        final layoutValue = _getGameplayValue(layoutCard);
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
      // Refresh layout positions to maintain compact grid
      _refreshLayoutPositions();
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

  /// Check if we should intercept waste pile operations for EatReds
  bool shouldInterceptWaste() => _interceptNextWasteDraw;

  /// Handle redirecting a card from waste to layout
  void redirectWasteToLayout(Card card, WastePile waste) {
    if (!shouldInterceptWaste()) return;

    // Disable further interception for this stock draw
    _interceptNextWasteDraw = false;
    _awaitingStockDraw = false;
    debugPrint('Intercepting card for layout: ${card.rank} of ${card.suit}');
    debugPrint('EatReds: Stock draw completed, disabling further draws');

    // Don't advance to next player yet - check for capture opportunities first

    // Find the first available position in the 2x2 grid, then expand outward
    int targetIndex = _findNextAvailableLayoutPosition();

    final targetPos = _getLayoutCardPosition(targetIndex, waste.position);

    // Move card to layout position with animation
    card.doMove(
      targetPos,
      speed: 10,
      onComplete: () {
        // IMPORTANT: Remove the card from its pile to prevent pile association issues
        // Note: Don't try to remove from StockPile as it doesn't allow removal
        if (card.pile != null && card.pile is! StockPile) {
          card.pile!.removeCard(card, MoveMethod.tap);
        }
        // Clear pile association for stock cards manually
        if (card.pile is StockPile) {
          card.pile = null;
        }

        // Add to layout cards for gameplay
        _layoutCards.add(card);
        debugPrint(
          'Drew card from stock to layout: ${card.rank} of ${card.suit} at position $targetIndex',
        );
        debugPrint('Layout cards now contains ${_layoutCards.length} cards');
        debugPrint('Card pile after removal: ${card.pile?.runtimeType}');

        // Clear any existing selections to start fresh
        clearSelections();

        // Check if the new stock card can capture any layout cards
        _evaluateStockCardCapture(card);
      },
    );

    _stockCardsRemaining--;
  }

  /// Advance to the next player's turn
  void _advanceToNextPlayer() {
    _currentPlayerIndex = (_currentPlayerIndex + 1) % _playerCount;
    debugPrint('Turn advanced to Player $_currentPlayerIndex');
  }

  /// Allow player to skip stock card capture and advance to next player
  void skipStockCapture() {
    if (_selectedHandCard != null && _layoutCards.contains(_selectedHandCard)) {
      // Clear selections and advance turn
      clearSelections();
      _advanceToNextPlayer();
      debugPrint('Player skipped stock card capture, advancing to next player');
    }
  }

  /// Check if current player has any valid capture moves
  bool currentPlayerHasValidCaptures() {
    if (_gameOver || _awaitingStockDraw) return false;

    // Get current player's tableau from the world
    // We need to access the game world to get tableaus
    try {
      // Get tableaus from captured cards context (we know tableaus exist during gameplay)
      if (_capturedCards.isEmpty) return false;

      // Find current player's hand cards by checking each layout card's potential game reference
      // This is a workaround since we don't have direct access to world here
      // We'll check if any hand cards can capture layout cards by using a more direct approach

      // For now, return true to allow selection - the actual validation will happen in canPlay
      return true;
    } catch (e) {
      debugPrint('Error checking valid captures: $e');
      return true; // Default to allowing play
    }
  }

  /// Check if a non-capturing play is allowed (only when no captures are possible)
  bool canPlayNonCapturing() {
    if (_awaitingStockDraw) return false;

    // Check if the currently selected hand card can capture any layout cards
    if (_selectedHandCard != null && !_layoutCards.contains(_selectedHandCard)) {
      // This is a hand card - check if it can capture any layout cards
      for (final layoutCard in _layoutCards) {
        if (_canCapture(_selectedHandCard!, layoutCard)) {
          return false; // Cannot add to layout when captures are available
        }
      }
    }

    return true; // Can add to layout when no captures are possible
  }

  /// Execute a non-capturing play (add card to layout)
  bool executeNonCapturingPlay(Card handCard, List<FoundationPile> foundations) {
    if (_gameOver || _awaitingStockDraw) return false;

    // Verify this is from current player's hand
    if (handCard.pile is! TableauPile) return false;

    final pile = handCard.pile as TableauPile;

    // Remove card from player's hand
    pile.removeCard(handCard, MoveMethod.tap);

    // Add card to layout with proper positioning
    final newIndex = _findNextAvailableLayoutPosition();
    final centerPos = Vector2(
      3.5 * KlondikeGame.cardSpaceWidth + KlondikeGame.cardGap,
      1.5 * KlondikeGame.cardSpaceHeight + KlondikeGame.topGap,
    );
    final targetPos = _getLayoutCardPosition(newIndex, centerPos);
    handCard.position = targetPos;

    // Add to layout cards - card is now a layout card, not a hand card
    _layoutCards.add(handCard);

    // Clear selections
    clearSelections();

    // Must draw from stock after non-capturing play
    _awaitingStockDraw = true;

    debugPrint('Player $_currentPlayerIndex played non-capturing card to layout');
    debugPrint('Card pile after adding to layout: ${handCard.pile?.runtimeType}');
    return true;
  }

  /// Evaluate if the stock card can capture any layout cards and highlight valid options
  void _evaluateStockCardCapture(Card stockCard) {
    final validCaptures = <Card>[];

    // Find all layout cards that can be captured by the stock card
    for (final layoutCard in _layoutCards) {
      if (layoutCard != stockCard && _canCapture(stockCard, layoutCard)) {
        validCaptures.add(layoutCard);
      }
    }

    if (validCaptures.isNotEmpty) {
      if (validCaptures.length == 1) {
        // Exactly 1 capture - auto-capture after a brief delay for visual feedback
        final layoutCard = validCaptures.first;

        debugPrint(
          'Stock card ${stockCard.rank} of ${stockCard.suit} auto-capturing ${layoutCard.rank} of ${layoutCard.suit}',
        );

        // Animate both cards being captured
        _animateAutoCapture(stockCard, layoutCard);
      } else {
        // Multiple captures - let player choose
        _selectedHandCard = stockCard;
        stockCard.setSelected(true);

        // Use the capture highlighting system
        _updateCaptureHighlights();

        // Reset stock draw state so player can make the capture
        _awaitingStockDraw = false;

        debugPrint(
          'Stock card ${stockCard.rank} of ${stockCard.suit} can capture ${validCaptures.length} layout cards - player must choose',
        );
        debugPrint(
          'Highlighted stock card and valid capture targets - player can now select and capture',
        );
      }
    } else {
      debugPrint(
        'Stock card ${stockCard.rank} of ${stockCard.suit} cannot capture any layout cards',
      );
      // No valid captures, advance to next player
      _advanceToNextPlayer();
    }
  }

  /// Animate automatic capture of stock card and layout card
  void _animateAutoCapture(Card stockCard, Card layoutCard) {
    // Add a brief highlight to show what's being captured
    stockCard.add(_CaptureHighlight());
    layoutCard.add(_CaptureHighlight());

    // Delay the capture to show the animation
    Future.delayed(const Duration(milliseconds: 800), () {
      // Remove cards from layout
      _layoutCards.remove(stockCard);
      _layoutCards.remove(layoutCard);

      // Clear any selections for removed cards
      _clearSelectionIfRemoved(stockCard);
      _clearSelectionIfRemoved(layoutCard);

      // Refresh layout positions to maintain compact grid
      _refreshLayoutPositions();

      // Add both cards to current player's captured pile
      _capturedCards[_currentPlayerIndex].add(stockCard);
      _capturedCards[_currentPlayerIndex].add(layoutCard);

      debugPrint('Auto-captured cards added to player $_currentPlayerIndex captured pile:');
      debugPrint(
        '  Stock card: ${stockCard.rank} of ${stockCard.suit} (${stockCard.suit.isRed ? "RED" : "BLACK"})',
      );
      debugPrint(
        '  Layout card: ${layoutCard.rank} of ${layoutCard.suit} (${layoutCard.suit.isRed ? "RED" : "BLACK"})',
      );

      // Get foundation piles from the world through the card's world reference
      final world = stockCard.world;
      final foundations = world.foundations;

      // Move cards to foundation pile (visually)
      _moveCardsToFoundation(stockCard, layoutCard, _currentPlayerIndex, foundations);

      // Clear any selections and highlights
      clearSelections();

      // Advance to next player
      _advanceToNextPlayer();

      debugPrint(
        'Auto-capture complete. Player $_currentPlayerIndex score: ${getPlayerScore(_currentPlayerIndex)}',
      );
    });
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

    debugPrint('=== CARD TAP DEBUG ===');
    debugPrint('Attempting to select card: ${card.rank.label} of ${card.suit.label}');
    debugPrint('Card pile type: ${card.pile?.runtimeType}');
    debugPrint('Card position: ${card.position}');
    debugPrint('Current player: $_currentPlayerIndex, awaiting stock draw: $_awaitingStockDraw');
    debugPrint('Layout cards count: ${_layoutCards.length}');
    debugPrint('Card in layout: ${_layoutCards.contains(card)}');

    // PRIORITY 1: Check if it's a layout card first (regardless of pile association)
    if (_layoutCards.contains(card)) {
      debugPrint('Confirmed: Card is in layout, calling selectLayoutCard');
      selectLayoutCard(card);
      return true;
    }

    // PRIORITY 2: Check if it's a hand card from current player
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

    // DEBUG: Show what layout cards we have if selection failed
    debugPrint('Card selection failed - not a valid card to select');
    debugPrint('Available layout cards:');
    for (int i = 0; i < _layoutCards.length; i++) {
      final layoutCard = _layoutCards[i];
      debugPrint(
        '  Layout[$i]: ${layoutCard.rank.label} of ${layoutCard.suit.label} at ${layoutCard.position}',
      );
      debugPrint('    Pile: ${layoutCard.pile?.runtimeType}');
      debugPrint('    Same object: ${identical(card, layoutCard)}');
    }

    debugPrint('Card selection failed: not a valid card to select');
    debugPrint('=== END CARD TAP DEBUG ===');
    return false;
  }

  @override
  bool canDropOnTableau({required Card moving, required Card? onTop}) => false;

  @override
  bool canDropOnFoundation({required Card moving, required FoundationPile foundation}) => false;

  @override
  bool canDrawFromStock(StockPile stock) {
    debugPrint(
      'canDrawFromStock called - gameOver: $_gameOver, stockRemaining: $_stockCardsRemaining, awaitingStockDraw: $_awaitingStockDraw',
    );

    if (_gameOver || _stockCardsRemaining <= 0) return false;

    if (_awaitingStockDraw) {
      // Immediately set awaiting to false to prevent multiple rapid clicks
      _awaitingStockDraw = false;

      // Set up interception for the next waste pile card
      _interceptNextWasteDraw = true;
      debugPrint('EatReds: Setting up stock draw interception');
      return true;
    }

    debugPrint('EatReds: Cannot draw from stock - not awaiting stock draw');
    return false;
  }

  @override
  bool checkWin({required List<FoundationPile> foundations}) => _gameOver;

  @override
  int getStockDrawCount() => 1; // EatReds draws only 1 card from stock

  /// Public method for UI to play a card (now handles selection)
  bool playCard(Card card, List<TableauPile> tableaus, StockPile stock) {
    // Use the new selection system instead of immediate play
    return handleCardTap(card);
  }

  /// Update capture highlights for layout cards when a hand card is selected
  void _updateCaptureHighlights() {
    // Clear existing capture highlights
    _clearCaptureHighlights();

    // If no hand card is selected, no highlights needed
    if (_selectedHandCard == null) return;

    // Highlight layout cards that can be captured by the selected hand card
    for (final layoutCard in _layoutCards) {
      if (_canCapture(_selectedHandCard!, layoutCard)) {
        layoutCard.add(_CaptureHighlight());
      }
    }
  }

  /// Clear all capture highlights from layout cards
  void _clearCaptureHighlights() {
    for (final layoutCard in _layoutCards) {
      final toRemove = layoutCard.children.whereType<_CaptureHighlight>().toList();
      for (final highlight in toRemove) {
        layoutCard.remove(highlight);
      }
    }
  }
}

// Highlight overlay for layout cards that can be captured
class _CaptureHighlight extends PositionComponent {
  static final _paint = Paint()
    ..style = PaintingStyle.fill
    ..color = const Color(0x80FFFF00); // Semi-transparent yellow fill

  @override
  void render(Canvas canvas) {
    final parentComponent = parent as PositionComponent;
    final rect = Rect.fromLTWH(0, 0, parentComponent.size.x, parentComponent.size.y);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(KlondikeGame.cardRadius));
    canvas.drawRRect(rrect, _paint);
  }
}
