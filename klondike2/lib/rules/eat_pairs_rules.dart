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

/// EatPairsRules implements the "Eat Pairs" (Siku in Khmer) card game.
///
/// Objective: Be the first player to get rid of all cards by forming pairs by rank.
///
/// Game Flow:
/// 1. Deal 7 cards to each player (dealer gets 8)
/// 2. Players immediately lay down any pairs they have
/// 3. Dealer (with 8 cards) plays ONE card from hand to start the game
/// 4. Other players race to match the rank - first to match wins both cards
/// 5. Matching player becomes the "lead player" and draws from stock
/// 6. Drawn card is offered to players in order - first match wins both cards
/// 7. That player becomes the new lead player and draws from stock
/// 8. Repeat: lead draws from stock, someone matches, they become lead
/// 9. First player to empty their hand wins
///
/// Key Rule: ONLY the dealer can play from hand ONCE to start.
/// After that, ALL cards come from stock draws only.
class EatPairsRules implements GameRules {
  EatPairsRules({int playerCount = 2}) : _playerCount = playerCount;

  int _playerCount; // 2-6 players supported
  int _currentPlayerIndex = 0;
  int _dealerIndex = 0;
  int _leadPlayerIndex = 0; // The player who played the last card (can draw from stock)
  int? _gameWinnerIndex;
  bool _gameOver = false;
  int _stockCardsRemaining = 0;

  // Getter for current player count
  int get playerCount => _playerCount;

  // Method to change player count (triggers re-deal)
  void setPlayerCount(int count) {
    if (count >= 2 && count <= 6) {
      _playerCount = count;
      debugPrint('EatPairs player count changed to $_playerCount');
    }
  }

  // Pairs laid out by each player (using foundations as pair piles)
  final List<List<Card>> _playerPairs = [];

  // Currently active card on the table (the card players are trying to match)
  Card? _activeCard;

  // Track if we're waiting for players to match the active card
  bool _awaitingMatch = false;

  // Card selection system
  Card? _selectedHandCard;

  // Track cards in each player's hand count
  final List<int> _handCounts = [];

  // Track if dealer has played their initial card
  bool _dealerHasPlayedFirstCard = false;

  // Store reference to foundations for initial pair laying
  List<FoundationPile>? _foundationsRef;

  @override
  String get name => 'Eat Pairs (Siku)';

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
  int get dealerIndex => _dealerIndex;
  int get leadPlayerIndex => _leadPlayerIndex;
  int? get gameWinnerIndex => _gameWinnerIndex;
  bool get gameOver => _gameOver;
  bool get awaitingMatch => _awaitingMatch;
  int get stockCardsRemaining => _stockCardsRemaining;
  Card? get activeCard => _activeCard;
  Card? get selectedHandCard => _selectedHandCard;
  List<int> get handCounts => List.unmodifiable(_handCounts);

  /// Check if play button should be enabled
  bool get canPlay {
    if (_selectedHandCard == null) return false;
    if (_awaitingMatch && _activeCard != null) {
      // Matching phase: Any player can match if they have the matching rank
      return _selectedHandCard!.rank.value == _activeCard!.rank.value;
    } else if (!_awaitingMatch && !_dealerHasPlayedFirstCard) {
      // Initial play: ONLY the dealer can play ONE card from hand to start
      return _currentPlayerIndex == _dealerIndex;
    }
    // After dealer plays first card, NO ONE can play from hand
    // All cards must come from stock draws
    return false;
  }

  /// Select a card from current player's hand
  void selectHandCard(Card card, List<TableauPile> tableaus) {
    // Guard: ensure game is initialized
    if (_handCounts.isEmpty) {
      debugPrint('Cannot select card - game not initialized');
      return;
    }

    // Only allow selection from current player's tableau
    final currentTableau = card.pile;
    if (currentTableau is TableauPile) {
      final tableauIndex = tableaus.indexOf(currentTableau);
      if (tableauIndex != _currentPlayerIndex) {
        debugPrint('Cannot select card from another player\'s hand');
        return;
      }

      // Check if this player is allowed to play based on game state
      if (!_awaitingMatch && !_dealerHasPlayedFirstCard) {
        // Initial play: Only the dealer can select/play ONE card from hand
        if (tableauIndex != _dealerIndex) {
          debugPrint('Only the dealer (P$_dealerIndex) can play the first card from hand');
          return;
        }
      } else if (!_awaitingMatch && _dealerHasPlayedFirstCard) {
        // After first card: NO ONE can play from hand - must draw from stock
        debugPrint('Cannot play from hand - all cards must come from stock draws');
        return;
      } else if (_awaitingMatch && _activeCard != null) {
        // Matching phase: Only allow selection if the card matches the active card's rank
        if (card.rank.value != _activeCard!.rank.value) {
          debugPrint(
            'Cannot select - card does not match active card rank (need ${_activeCard!.rank.label})',
          );
          return;
        }
        debugPrint('Card matches active card rank - can select');
      }

      // Clear previous hand card selection
      if (_selectedHandCard != null) {
        _selectedHandCard!.setSelected(false);
      }

      _selectedHandCard = card;
      card.setSelected(true);
      debugPrint('Selected hand card: ${card.rank.label} of ${card.suit.label}');
    }
  }

  /// Clear card selections
  void clearSelections() {
    if (_selectedHandCard != null) {
      _selectedHandCard!.setSelected(false);
      _selectedHandCard = null;
    }
    debugPrint('Card selections cleared');
  }

  /// Execute the play action with selected card
  bool executePlay(
    List<TableauPile> tableaus,
    List<FoundationPile> foundations,
    StockPile stock,
    WastePile waste,
  ) {
    if (_selectedHandCard == null) return false;

    if (_awaitingMatch && _activeCard != null) {
      // Player is attempting to match the active card
      if (_selectedHandCard!.rank.value == _activeCard!.rank.value) {
        // Successful match!
        debugPrint('Player $_currentPlayerIndex matched ${_activeCard!.rank.label}!');

        // Remove the selected card from player's hand
        final sourceTableau = _selectedHandCard!.pile as TableauPile;
        sourceTableau.removeCard(_selectedHandCard!, MoveMethod.tap);

        // Place both cards face-up in front of the matching player
        final playerFoundation = foundations[_currentPlayerIndex];
        playerFoundation.acquireCard(_selectedHandCard!);
        if (_activeCard != null) {
          playerFoundation.acquireCard(_activeCard!);
        }

        // Update hand count
        final tableauIndex = tableaus.indexOf(sourceTableau);
        if (tableauIndex >= 0 && tableauIndex < _handCounts.length) {
          _handCounts[tableauIndex]--;
        }

        // Clear active card and selection
        _activeCard = null;
        clearSelections();

        // Check if this player won
        if (_currentPlayerIndex < _handCounts.length && _handCounts[_currentPlayerIndex] == 0) {
          _gameWinnerIndex = _currentPlayerIndex;
          _gameOver = true;
          debugPrint('Player $_currentPlayerIndex wins!');
          return true;
        }

        // Matching player becomes the lead player and can now play a card from hand
        _leadPlayerIndex = _currentPlayerIndex;
        _awaitingMatch = false;
        debugPrint('Player $_currentPlayerIndex is now the lead player and can play a card');
        return true;
      } else {
        debugPrint('Card does not match active card rank');
        return false;
      }
    } else if (!_awaitingMatch) {
      // This section handles playing from hand
      // ONLY the dealer can play from hand, and ONLY their first card
      if (_dealerHasPlayedFirstCard) {
        debugPrint('Cannot play from hand - dealer already played their first card');
        return false;
      }

      if (_currentPlayerIndex != _dealerIndex) {
        debugPrint('Only the dealer (P$_dealerIndex) can play from hand');
        return false;
      }

      // Dealer is playing their FIRST and ONLY card from hand
      debugPrint(
        'Dealer $_currentPlayerIndex plays their first card: ${_selectedHandCard!.rank.label}',
      );

      // Store the played card's rank for matching
      final playedRank = _selectedHandCard!.rank.value;

      // Remove the selected card from player's hand
      final sourceTableau = _selectedHandCard!.pile as TableauPile;
      sourceTableau.removeCard(_selectedHandCard!, MoveMethod.tap);

      // Update hand count
      final tableauIndex = tableaus.indexOf(sourceTableau);
      if (tableauIndex >= 0 && tableauIndex < _handCounts.length) {
        _handCounts[tableauIndex]--;
      }

      // Check if this player won by playing their last card
      if (_currentPlayerIndex < _handCounts.length && _handCounts[_currentPlayerIndex] == 0) {
        _gameWinnerIndex = _currentPlayerIndex;
        _gameOver = true;
        debugPrint('Player $_currentPlayerIndex wins by playing last card!');

        // Place card in foundation as pair
        final playerFoundation = foundations[_currentPlayerIndex];
        playerFoundation.acquireCard(_selectedHandCard!);
        clearSelections();
        return true;
      }

      // Store the played card for matching
      final playedCard = _selectedHandCard;

      // Place card face-up on waste pile (center of table)
      waste.acquireCard(_selectedHandCard!);
      _activeCard = _selectedHandCard;
      clearSelections();

      // Mark that dealer has played their first (and only) card from hand
      _dealerHasPlayedFirstCard = true;
      debugPrint('Dealer has played their first card - no more hand plays allowed');

      // Now check if any player has a matching rank in their hand
      // Search through all players starting from next player
      Card? matchingCard;
      int matchingPlayerIndex = -1;

      for (int i = 1; i <= _playerCount; i++) {
        final checkPlayerIndex = (_currentPlayerIndex + i) % _playerCount;
        final playerTableau = tableaus[checkPlayerIndex];

        // Check if this player has a card with matching rank
        for (final card in playerTableau.cards) {
          if (card.rank.value == playedRank) {
            matchingCard = card;
            matchingPlayerIndex = checkPlayerIndex;
            break;
          }
        }

        if (matchingCard != null) break;
      }

      // If a matching card was found, automatically pair them
      if (matchingCard != null && matchingPlayerIndex >= 0) {
        debugPrint(
          'Auto-match: Player $matchingPlayerIndex has matching ${matchingCard.rank.label}!',
        );

        // Remove matching card from that player's hand
        final matchingTableau = tableaus[matchingPlayerIndex];
        matchingTableau.removeCard(matchingCard, MoveMethod.tap);

        // Remove played card from waste
        waste.removeCard(playedCard!, MoveMethod.tap);

        // Move both cards to the matching player's foundation
        final matchingPlayerFoundation = foundations[matchingPlayerIndex];

        // Animate both cards to foundation
        playedCard.doMove(
          matchingPlayerFoundation.position,
          speed: 15,
          start: 0,
          onComplete: () {
            matchingPlayerFoundation.acquireCard(playedCard);
          },
        );

        matchingCard.doMove(
          matchingPlayerFoundation.position,
          speed: 15,
          start: 0.1,
          onComplete: () {
            matchingPlayerFoundation.acquireCard(matchingCard!);
          },
        );

        // Update hand count
        if (matchingPlayerIndex < _handCounts.length) {
          _handCounts[matchingPlayerIndex]--;
        }

        // Check if matching player won
        if (matchingPlayerIndex < _handCounts.length && _handCounts[matchingPlayerIndex] == 0) {
          _gameWinnerIndex = matchingPlayerIndex;
          _gameOver = true;
          debugPrint('Player $matchingPlayerIndex wins!');
          return true;
        }

        // Clear active card
        _activeCard = null;

        // Matching player becomes the lead player and current player
        _currentPlayerIndex = matchingPlayerIndex;
        _leadPlayerIndex = matchingPlayerIndex;
        _awaitingMatch = false;
        debugPrint('Player $_currentPlayerIndex is now the lead player and can play a card');
        return true;
      }

      // No automatic match found - no player has this rank in their hand
      // The played card stays on waste, but we allow drawing from stock to continue
      _awaitingMatch = false;
      debugPrint('No player has matching ${_activeCard!.rank.label} - dealer can draw from stock');

      // Dealer remains as lead player and can draw from stock
      return true;
    }

    return false;
  }

  /// Draw a card from stock and distribute to players for matching
  /// The card is offered to players in order starting after the lead player
  /// If a player has a matching rank, they automatically pair and become lead
  /// If no match after all players, lead player draws another card
  bool drawAndDistributeFromStock(
    StockPile stock,
    List<TableauPile> tableaus,
    List<FoundationPile> foundations,
    WastePile waste,
  ) {
    // Check if stock has cards
    if (_stockCardsRemaining <= 0) {
      debugPrint('Stock is empty, cannot draw');
      return false;
    }

    // Can only draw when not awaiting a match or when no active card
    if (_awaitingMatch && _activeCard != null) {
      debugPrint('Cannot draw - still waiting for match on active card');
      return false;
    }

    debugPrint('Lead player (P$_leadPlayerIndex) draws card from stock');

    // Get the top card from stock (we'll simulate the draw)
    // In actual implementation, the stock pile's handleTapUp will do the physical draw
    // For now, we just decrement and mark that we need to process the drawn card
    _stockCardsRemaining--;

    // The actual card will be drawn by the stock pile and placed on waste
    // We'll set up the state to handle it when it arrives
    // Mark that we're waiting for the drawn card to be distributed
    _awaitingMatch = false; // Clear any previous match state

    debugPrint('Card drawn - will check players for match');
    return true;
  }

  /// Process a card drawn from stock - check if any player can match it
  /// This is called after the card is physically moved to the waste pile
  void processDrawnCard(
    Card drawnCard,
    List<TableauPile> tableaus,
    List<FoundationPile> foundations,
    WastePile waste,
  ) {
    debugPrint('Processing drawn card: ${drawnCard.rank.label}${drawnCard.suit.label}');

    final drawnRank = drawnCard.rank.value;

    // Check players in order starting from the player after the lead player
    for (int i = 1; i <= _playerCount; i++) {
      final checkPlayerIndex = (_leadPlayerIndex + i) % _playerCount;
      final playerTableau = tableaus[checkPlayerIndex];

      // Check if this player has a card with matching rank
      for (final card in playerTableau.cards) {
        if (card.rank.value == drawnRank) {
          debugPrint('Player $checkPlayerIndex has matching ${card.rank.label}!');

          // Remove matching card from player's hand
          playerTableau.removeCard(card, MoveMethod.tap);

          // Remove drawn card from waste
          waste.removeCard(drawnCard, MoveMethod.tap);

          // Move both cards to the matching player's foundation
          final playerFoundation = foundations[checkPlayerIndex];

          // Animate both cards to foundation
          drawnCard.doMove(
            playerFoundation.position,
            speed: 15,
            start: 0,
            onComplete: () {
              playerFoundation.acquireCard(drawnCard);
            },
          );

          card.doMove(
            playerFoundation.position,
            speed: 15,
            start: 0.1,
            onComplete: () {
              playerFoundation.acquireCard(card);
            },
          );

          // Update hand count
          if (checkPlayerIndex < _handCounts.length) {
            _handCounts[checkPlayerIndex]--;
          }

          // Check if this player won
          if (checkPlayerIndex < _handCounts.length && _handCounts[checkPlayerIndex] == 0) {
            _gameWinnerIndex = checkPlayerIndex;
            _gameOver = true;
            debugPrint('Player $checkPlayerIndex wins!');
            return;
          }

          // Matching player becomes the new lead player
          _currentPlayerIndex = checkPlayerIndex;
          _leadPlayerIndex = checkPlayerIndex;
          _awaitingMatch = false;
          _activeCard = null;
          debugPrint('Player $checkPlayerIndex is now the lead player');
          return;
        }
      }
    }

    // No match found - leave card on waste but allow lead player to draw again
    _activeCard = drawnCard;
    _awaitingMatch = false; // Allow drawing again from stock
    debugPrint('No automatic match found - lead player can draw again from stock');
  }

  /// Called when no player can match the active card
  /// The lead player draws a card from stock and places it face-up in front of a player
  /// Then players try to match this drawn card
  bool handleNoMatch(StockPile stock, List<TableauPile> tableaus, int targetPlayerIndex) {
    if (!_awaitingMatch || _activeCard == null) return false;

    debugPrint(
      'No match for ${_activeCard!.rank.label}, lead player (P$_leadPlayerIndex) draws card',
    );

    // Check if stock has cards
    if (_stockCardsRemaining <= 0) {
      debugPrint('Stock is empty, cannot draw card');
      // Game might end here depending on rules interpretation
      return false;
    }

    // Note: We can't directly access stock._cards, so we rely on tracking count
    // The actual card drawing should be handled by the stock pile's handleTapUp
    // For now, we just decrement the count and let the system handle it
    _stockCardsRemaining--;

    // Note: The actual card distribution will be handled by the UI/stock pile interaction
    // This method just manages the game state
    debugPrint('Lead player (P$_leadPlayerIndex) draws stock card for player $targetPlayerIndex');

    return true;
  }

  /// Lay down initial pairs from hand before play begins
  void layDownInitialPairs(List<TableauPile> tableaus, List<FoundationPile> foundations) {
    debugPrint('Laying down initial pairs from all players\' hands');

    for (int playerIndex = 0; playerIndex < _playerCount; playerIndex++) {
      // Ensure handCounts list is properly sized
      if (playerIndex >= _handCounts.length) {
        debugPrint('ERROR: handCounts not initialized for player $playerIndex');
        continue;
      }

      if (playerIndex >= tableaus.length || playerIndex >= foundations.length) {
        debugPrint('ERROR: Not enough tableaus/foundations for player $playerIndex');
        continue;
      }

      final tableau = tableaus[playerIndex];
      final foundation = foundations[playerIndex];
      final hand = List<Card>.from(tableau.cards);

      // Find pairs in hand
      final Map<int, List<Card>> rankGroups = {};
      for (final card in hand) {
        rankGroups.putIfAbsent(card.rank.value, () => []).add(card);
      }

      // Lay down pairs (2 cards per pair, keep 3rd if exists, lay all 4 if exists)
      int delayMultiplier = 0;
      for (final entry in rankGroups.entries) {
        final cards = entry.value;
        if (cards.length >= 2) {
          // Lay down pairs of 2
          int pairsToLay = cards.length ~/ 2;
          for (int i = 0; i < pairsToLay * 2; i++) {
            final card = cards[i];
            tableau.removeCard(card, MoveMethod.tap);

            // Animate card to foundation pile
            final delay = delayMultiplier * 0.1;
            card.doMove(
              foundation.position,
              speed: 15,
              start: delay,
              onComplete: () {
                foundation.acquireCard(card);
              },
            );

            if (playerIndex < _handCounts.length) {
              _handCounts[playerIndex]--;
            }
            debugPrint('Player $playerIndex lays down ${card.rank.label} of ${card.suit.label}');
            delayMultiplier++;
          }
        }
      }
    }

    debugPrint('Initial pairs laid down');
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
    debugPrint('EatPairs setupPiles called with $_playerCount players');

    // Clear existing piles
    foundations.clear();
    tableaus.clear();

    // Store reference to foundations for initial pair laying
    _foundationsRef = foundations;

    // Stock pile on the right side to avoid button overlap
    stock.position = Vector2(5.5 * cardSpaceWidth + cardGap, topGap);

    // Waste pile in center (for the active card being matched)
    waste.position = Vector2(2.5 * cardSpaceWidth + cardGap, topGap);

    // Foundation piles (paired cards) - one per player, arranged in a row below stock/waste
    for (int i = 0; i < _playerCount; i++) {
      foundations.add(
        FoundationPile(
          i % 4,
          checkWin,
          position: Vector2((i + 0.5) * cardSpaceWidth + cardGap, 1.5 * cardSpaceHeight + topGap),
        ),
      );
    }

    // Tableau piles (player hands) - arranged in a row at the bottom
    for (int i = 0; i < _playerCount; i++) {
      tableaus.add(
        TableauPile(
          position: Vector2((i + 0.5) * cardSpaceWidth + cardGap, 2.5 * cardSpaceHeight + topGap),
        ),
      );
    }

    debugPrint('EatPairs piles positioned');
  }

  @override
  void deal({
    required List<Card> deck,
    required List<TableauPile> tableaus,
    required StockPile stock,
    required WastePile waste,
    required int seed,
  }) {
    debugPrint('EatPairs deal started with seed $seed');

    // Shuffle deck
    deck.shuffle(Random(seed));

    // Initialize hand counts
    _handCounts.clear();
    for (int i = 0; i < _playerCount; i++) {
      _handCounts.add(0);
    }

    // Deal cards: 7 to each player, dealer gets 8
    // For simplicity, player 0 is the dealer
    _dealerIndex = 0;
    _currentPlayerIndex = _dealerIndex;
    _leadPlayerIndex = _dealerIndex; // Dealer starts as the lead player (can play first)

    // Calculate total cards to deal to players
    int totalPlayerCards = (_playerCount - 1) * 7 + 8; // 7 per player, dealer gets 8
    int dealIndex = 0;
    int remaining = totalPlayerCards;

    void afterAllLanded() {
      debugPrint('EatPairs deal complete (animated). Laying down initial pairs...');
      // Lay down initial pairs after all cards have been dealt
      if (_foundationsRef != null) {
        layDownInitialPairs(tableaus, _foundationsRef!);
      } else {
        debugPrint('WARNING: _foundationsRef is null, cannot lay down initial pairs');
      }
    }

    // Deal cards to players in round-robin style (animated like Eat Reds)
    int maxCards = 8; // Dealer gets 8, others get 7
    for (var round = 0; round < maxCards; round++) {
      for (var player = 0; player < _playerCount; player++) {
        // Dealer gets 8 cards, others get 7
        final cardsForThisPlayer = (player == _dealerIndex) ? 8 : 7;
        if (round < cardsForThisPlayer) {
          final cardIndex = dealIndex;
          if (cardIndex < deck.length && cardIndex < totalPlayerCards) {
            final card = deck[cardIndex];
            final targetPile = tableaus[player];
            final delay = dealIndex * 0.08; // Same timing as Eat Reds

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
                _handCounts[player]++;
                remaining--;
                if (remaining == 0) afterAllLanded();
              },
            );
            dealIndex++;
          }
        }
      }
    }

    // Remaining cards go to stock (no animation needed)
    for (var i = totalPlayerCards; i < deck.length; i++) {
      final card = deck[i];
      card.position = stock.position;
      stock.acquireCard(card);
      _stockCardsRemaining++;
    }

    debugPrint('Stock has $_stockCardsRemaining cards');

    // Reset game state
    _activeCard = null;
    _awaitingMatch = false;
    _gameOver = false;
    _gameWinnerIndex = null;
    _selectedHandCard = null;
    _playerPairs.clear();
    _dealerHasPlayedFirstCard = false; // Reset for new game

    debugPrint('EatPairs deal completed');
  }

  @override
  bool canMoveFromTableau(Card card) {
    // In Eat Pairs, cards can only be played via the executePlay mechanism
    // Disable drag-and-drop from tableau
    return false;
  }

  @override
  bool canDropOnTableau({required Card moving, required Card? onTop}) {
    // No dropping on tableau in Eat Pairs
    return false;
  }

  @override
  bool canDropOnFoundation({required Card moving, required FoundationPile foundation}) {
    // No dropping on foundation in Eat Pairs (pairs are laid automatically)
    return false;
  }

  @override
  bool canDrawFromStock(StockPile stock) {
    // Allow drawing from stock in Eat Pairs when:
    // 1. There's no active card waiting for match, OR
    // 2. There's an active card but no one has matched yet (draw another to try)
    // Stock has cards remaining
    return _stockCardsRemaining > 0;
  }

  @override
  int getStockDrawCount() => 1;

  @override
  bool checkWin({required List<FoundationPile> foundations}) {
    // Win condition: a player has emptied their hand
    return _gameOver && _gameWinnerIndex != null;
  }
}
