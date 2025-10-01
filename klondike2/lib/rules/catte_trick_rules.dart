import 'dart:math';

import 'package:flame/components.dart';
import 'dart:ui';
import 'package:flutter/foundation.dart';

import '../components/card.dart';
import '../components/foundation_pile.dart'; // Only to satisfy GameRules signatures; not used for play.
import '../components/stock_pile.dart';
import '../components/tableau_pile.dart';
import '../components/waste_pile.dart';
import '../klondike_game.dart';
import '../suit.dart';
import '../pile.dart';
import 'game_rules.dart';
import 'package:flame/effects.dart';

/// Region variants (rules differences to be layered in later).
enum CatTeRegion { khmer, laos, vietnamese }

/// A single play within an in‑progress trick.
class _Play {
  _Play({required this.playerIndex, required this.card, required this.folded});
  final int playerIndex;
  final Card card;
  final bool folded;
}

/// CatTeTrickRules is an incremental trick‑taking implementation separate from the
/// earlier simplified CatTe mapping. It treats tableau piles as player hands and
/// positions played cards into a top row (virtual slots) each trick.
///
/// Scope (Phase 1):
/// - 6 tableau = up to 6 players (currently always 6 dealt; later can trim)
/// - 6 tricks total; last trick winner wins entire game
/// - Follow suit requirement for tricks 1–5 if player holds the lead suit
/// - Trick 6: free suit (no follow requirement)
/// - Folding API scaffolded but not yet exposed via UI; folded card simply means
///   the card is placed face-down and cannot win the trick
/// - No eliminations/instant wins yet (Khmer basic flow)
/// - Cards remain displayed where played (no collection piles yet)
class CatTeTrickRules implements GameRules {
  CatTeTrickRules({this.region = CatTeRegion.khmer});

  CatTeRegion region;

  // Cycle to next region (invokable from UI overlay later).
  void nextRegion() {
    final order = CatTeRegion.values;
    region = order[(region.index + 1) % order.length];
    debugPrint('CatTe region switched to $region');
  }

  // Public view / state accessors ------------------------------------------------
  int get trickNumber => _trickNumber; // 1..6
  int get currentPlayerIndex => _currentPlayerIndex; // whose turn
  int? get winnerIndex => _gameWinnerIndex; // null until game over
  int get leaderIndex => _leaderIndex; // player who leads current trick
  List<int> get tricksWonView => List.unmodifiable(_tricksWon);
  List<bool> get eliminatedView => List.unmodifiable(_eliminated);
  Suit? get leadSuit => _leadSuit;
  List<Card> get currentTrickCards => _currentPlays.map((p) => p.card).toList(growable: false);
  Card? get selectedCard => _selectedCard;

  // Internal mutable state -------------------------------------------------------
  int _trickNumber = 1;
  int _leaderIndex = 0;
  int _currentPlayerIndex = 0;
  Suit? _leadSuit; // suit of first non-folded card in trick (ignored trick 6)
  final List<_Play> _currentPlays = [];
  final List<int> _tricksWon = List.filled(6, 0); // One slot per tableau.
  final List<bool> _eliminated = List.filled(6, false);
  int? _gameWinnerIndex;
  bool _instantWinResolved = false;
  Card? _selectedCard; // currently selected (not yet played) card by active player.
  // Diagnostic: toggle for verbose legality tracing.
  final bool _logLegality = true;
  // Must-beat-if-possible rule: when following suit, a player must beat the current
  // highest lead-suit card IF they possess any higher card of that suit. If they
  // hold no card capable of beating the current best, they may underplay. This
  // supersedes the earlier optional strictMustBeat toggle.
  // (Keep a backing flag in case we later wish to expose a UI toggle to relax it.)
  bool strictMustBeat = true;

  // Layout: reuse same play area math as simplified CatTe.
  @override
  Vector2 get playAreaSize => Vector2(
    6 * KlondikeGame.cardSpaceWidth + KlondikeGame.cardGap,
    2 * KlondikeGame.cardSpaceHeight + KlondikeGame.topGap,
  );

  @override
  String get name => 'CatTe (Trick)';

  @override
  bool get usesBaseCard => false;
  @override
  bool get usesWaste => false;
  @override
  bool get usesKlondikeFoundationSequence => false;

  // Pile setup: identical visual lattice to simplified CatTe – we still
  // populate the `foundations` list with placeholder FoundationPiles so the
  // world can add them uniformly. We disable drops onto them. Played cards
  // are simply moved to those positions for visibility.
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
    foundations.clear();
    for (var i = 0; i < 6; i++) {
      foundations.add(
        FoundationPile(i % 4, checkWin, position: Vector2(i * cardSpaceWidth + cardGap, topGap)),
      );
    }
    tableaus.clear();
    for (var i = 0; i < 6; i++) {
      tableaus.add(
        TableauPile(position: Vector2(i * cardSpaceWidth + cardGap, topGap + cardSpaceHeight)),
      );
    }
    stock.position = Vector2(-99999, -99999); // Hide
    waste.position = Vector2(-99999, -99999); // Hide

    _trickNumber = 1;
    _leaderIndex = 0;
    _currentPlayerIndex = 0;
    _leadSuit = null;
    for (var i = 0; i < _tricksWon.length; i++) {
      _tricksWon[i] = 0;
    }
    _currentPlays.clear();
    _gameWinnerIndex = null;
    _selectedCard = null;
    debugPrint('CatTeTrickRules setup complete. Ready for deal.');
  }

  @override
  void deal({
    required List<Card> deck,
    required List<TableauPile> tableaus,
    required StockPile stock,
    required WastePile waste,
    required int seed,
  }) {
    // Animated round‑robin (flying) deal similar to Klondike.
    deck.shuffle(Random(seed));

    // Give every card a base priority so they stay above the table during flight.
    var prio = 1;
    for (final c in deck) {
      c.priority = prio++;
    }

    // We only use the first 36 cards (6 players x 6 cards). Remaining cards are ignored.
    const players = 6;
    const cardsPerPlayer = 6;
    final totalToDeal = players * cardsPerPlayer; // 36

    // Origin point to "fly" from (roughly center top area). Could be refined later.
    final origin = Vector2(
      (playAreaSize.x - KlondikeGame.cardWidth) * 0.5,
      KlondikeGame.topGap * 0.5 + KlondikeGame.cardGap,
    );

    // Place the 36 cards at origin first (face‑down) for a consistent animation start.
    for (var i = 0; i < totalToDeal; i++) {
      final card = deck[i];
      card.position = origin.clone();
      if (!card.isFaceDown) {
        // Keep them face‑down until they land to enhance effect; flip onComplete.
        // (If already face‑up from a prior game, flip them back.)
        card.flip();
      }
    }

    var dealIndex = 0; // overall order for staggered start delays
    var remaining = totalToDeal;

    void afterAllLanded() {
      debugPrint('CatTeTrickRules deal complete (animated 6x6).');
      _detectInstantWin(tableaus);
      if (_gameWinnerIndex == null) {
        _updateLegalHighlights(tableaus); // Initial highlights for leader.
        _updateSelectionHighlight(tableaus);
      }
    }

    for (var round = 0; round < cardsPerPlayer; round++) {
      for (var p = 0; p < players; p++) {
        final card = deck[round * players + p];
        final targetPile = tableaus[p];
        final delay = dealIndex * 0.07; // Slightly slower & more deliberate than Klondike.
        card.doMove(
          targetPile.position,
          speed: 18,
          start: delay,
          startPriority: 200 + dealIndex,
          onComplete: () {
            // Acquire into pile (adds fan layout) then flip face‑up.
            targetPile.acquireCard(card);
            if (card.isFaceDown) {
              card.flip();
            }
            remaining--;
            if (remaining == 0) afterAllLanded();
          },
        );
        dealIndex++;
      }
    }
  }

  // Gameplay API -----------------------------------------------------------------

  bool playCard(Card card) {
    if (_gameWinnerIndex != null) return false; // Game over.
    final pile = card.pile;
    if (pile is! TableauPile) return false;
    final game = pile.game;
    final world = game.world as dynamic;
    final tableaus = world.tableauPiles as List<TableauPile>;
    final foundations = world.foundations as List<FoundationPile>; // Slot positions.
    final playerIndex = tableaus.indexOf(pile);

    // COMPREHENSIVE DEBUG LOG - capture exact state at play attempt
    final handCards = pile.cards.map((c) => c.toString()).join(',');
    final leadStr = _leadSuit == null ? 'NULL' : '${_suitLabel(_leadSuit!)}(${_leadSuit!.value})';
    final cardSuitStr = '${_suitLabel(card.suit)}(${card.suit.value})';
    debugPrint(
      '=== PLAY ATTEMPT === P$playerIndex playing $card [suit=$cardSuitStr] | leadSuit=$leadStr | trick=$_trickNumber | hand=[$handCards]',
    );

    if (_eliminated[playerIndex]) return false; // Can't act if eliminated.
    if (playerIndex != _currentPlayerIndex) {
      debugPrint('Reject play: not player $playerIndex\'s turn (expect $_currentPlayerIndex).');
      return false;
    }
    if (!card.isFaceUp) {
      return false;
    }

    if (!isLegalPlay(card)) {
      debugPrint('*** BLOCKED BY isLegalPlay() ***');
      return false;
    }
    // Extra defensive guard: if rules somehow allowed an off-suit play while player
    // still holds a card of the lead suit (tricks 1-5), block it here and log.
    if (_leadSuit != null && _trickNumber < 6) {
      final leadValue = _leadSuit!.value;
      final stillHasLead = pile.cards.any((c) => c.suit.value == leadValue);
      if (stillHasLead && card.suit.value != leadValue) {
        final handCards = pile.cards.map((c) => c.toString()).join(',');
        debugPrint(
          '[RULE VIOLATION GUARD] Blocking off-suit play: player $playerIndex tried $card while still holding lead suit ${_suitLabel(_leadSuit!)}. Hand: [$handCards]',
        );
        return false;
      }
    }

    // FINAL VALIDATION before proceeding with play
    if (_leadSuit != null && _trickNumber < 6) {
      final cardSuitValue = card.suit.value;
      final leadSuitValue = _leadSuit!.value;
      final hasLeadSuit = pile.cards.any((c) => c.suit.value == leadSuitValue);
      if (hasLeadSuit && cardSuitValue != leadSuitValue) {
        debugPrint('*** CRITICAL ERROR *** Play should have been blocked but passed all checks!');
        debugPrint('    Card: $card (suit value: $cardSuitValue)');
        debugPrint('    Lead suit: ${_suitLabel(_leadSuit!)} (value: $leadSuitValue)');
        debugPrint('    Player has lead suit: $hasLeadSuit');
        debugPrint('    Hand: [${pile.cards.map((c) => c.toString()).join(',')}]');
        return false; // Block it here as last resort
      }
    }
    // Diagnostic snapshot before removal
    if (_logLegality) {
      final cardsNow = pile.cards.map((c) => c.toString()).join(',');
      debugPrint(
        '[PLAY] P$playerIndex attempting $card lead=${_leadSuit == null ? 'none' : _suitLabel(_leadSuit!)} hand=[$cardsNow]',
      );
    }
    if (!pile.cards.contains(card)) {
      debugPrint('Reject play: card already removed from pile.');
      return false;
    }
    pile.removeCard(card, MoveMethod.drag);
    card.pile = null; // detach after moving to table

    // Establish lead suit if first non-fold play of trick (ignore if trick 6 free-suit rule?).
    if (_leadSuit == null && _trickNumber < 6) {
      _leadSuit = card.suit;
      if (_logLegality) {
        debugPrint(
          '[LEAD] Suit=${_suitLabel(_leadSuit!)}(${_leadSuit!.value}) established by P$playerIndex playing $card on trick $_trickNumber.',
        );
      }
    }

    // Move to visual slot (reuse foundation coordinates by player index / seat order).
    final slotPos = foundations[playerIndex].position;
    card.doMove(slotPos, speed: 25.0, onComplete: () {});
    // Ensure later-trick plays appear above earlier ones (simple layering).
    card.priority = 100 + _trickNumber; // base offset so it stays above default dealt cards
    _currentPlays.add(_Play(playerIndex: playerIndex, card: card, folded: false));
    debugPrint('Player $playerIndex played $card on trick $_trickNumber.');

    if (_selectedCard == card) {
      _removeSelectionEffects(_selectedCard!);
      _selectedCard = null; // clear selection once played
    }

    _advanceTurn(tableaus);
    return true;
  }

  bool foldCard(Card card) {
    if (_gameWinnerIndex != null) return false;
    final pile = card.pile;
    if (pile is! TableauPile) return false;
    final game = pile.game;
    final world = game.world as dynamic;
    final tableaus = world.tableauPiles as List<TableauPile>;
    final foundations = world.foundations as List<FoundationPile>;
    final playerIndex = tableaus.indexOf(pile);

    // DEBUG: Log fold attempt
    final handCards = pile.cards.map((c) => c.toString()).join(',');
    final leadStr = _leadSuit == null ? 'NULL' : '${_suitLabel(_leadSuit!)}(${_leadSuit!.value})';
    debugPrint(
      '=== FOLD ATTEMPT === P$playerIndex folding $card | leadSuit=$leadStr | trick=$_trickNumber | hand=[$handCards]',
    );

    if (playerIndex != _currentPlayerIndex) {
      debugPrint('Reject fold: not current player');
      return false;
    }
    if (_eliminated[playerIndex]) {
      debugPrint('Reject fold: player eliminated');
      return false;
    }
    // Leading player may not fold (must lead a card).
    if (playerIndex == _leaderIndex) {
      debugPrint('Reject fold: leader (player $playerIndex) must play a card.');
      return false;
    }

    // Players can choose to fold strategically regardless of their hand contents
    // (except the leader who must play to establish the lead)
    debugPrint('Allow fold: player $playerIndex can fold strategically.');
    if (!card.isFaceUp) {
      card.flip(); // Ensure face-up then we can optionally flip down for folded state.
    }

    if (!pile.cards.contains(card)) {
      debugPrint('Reject fold: card already removed from pile.');
      return false;
    }
    pile.removeCard(card, MoveMethod.drag);
    card.pile = null; // detach
    final slotPos = foundations[playerIndex].position;
    card.doMove(slotPos, speed: 25.0, onComplete: () {});
    card.priority = 100 + _trickNumber; // keep folded card layering consistent
    // Visually turn face-down to represent fold (allowed despite future pickup restriction).
    if (card.isFaceUp) {
      card.flip();
    }
    _currentPlays.add(_Play(playerIndex: playerIndex, card: card, folded: true));
    debugPrint('Player $playerIndex folded a card on trick $_trickNumber.');
    if (_selectedCard == card) {
      _removeSelectionEffects(_selectedCard!);
      _selectedCard = null;
    }
    _advanceTurn(tableaus);
    return true;
  }

  void _advanceTurn(List<TableauPile> tableaus) {
    final activeCount = _activePlayerCount();
    if (_currentPlays.length == activeCount) {
      _resolveTrick(tableaus.length);
    } else {
      if (_selectedCard != null) {
        _removeSelectionEffects(_selectedCard!);
      }
      _currentPlayerIndex = _nextActiveIndex(_currentPlayerIndex + 1);
      _selectedCard = null; // clear selection when turn advances
      _updateLegalHighlights(tableaus);
      _updateSelectionHighlight(tableaus);
    }
  }

  void _resolveTrick(int nPlayers) {
    debugPrint('Resolving trick $_trickNumber ...');
    // Determine winner: highest rank among non-folded cards of lead suit (if any such plays).
    int? winner;
    int bestRank = -1;
    for (final play in _currentPlays) {
      if (play.folded) continue;
      if (_leadSuit != null && play.card.suit.value != _leadSuit!.value) continue;
      final rankVal = _aceHigh(play.card.rank.value);
      if (rankVal > bestRank) {
        bestRank = rankVal;
        winner = play.playerIndex;
      }
    }
    // Edge case: everyone folded or no card matched lead suit -> leader wins by default.
    winner ??= _leaderIndex;
    _tricksWon[winner]++;
    debugPrint('Trick $_trickNumber winner: Player $winner (tricks won=${_tricksWon[winner]}).');

    // Laos & Vietnamese elimination after 4th trick (when moving to trick 5).
    if (_trickNumber == 4 && (region == CatTeRegion.laos || region == CatTeRegion.vietnamese)) {
      for (var i = 0; i < _tricksWon.length; i++) {
        if (_tricksWon[i] == 0) {
          _eliminated[i] = true;
          debugPrint('Player $i eliminated (no trick in first four).');
        }
      }
    }

    // Previously we shifted cards downward each trick for history; removed per UX request.
    // Played cards now remain stacked directly on their foundation slot.

    if (_trickNumber == 6) {
      _gameWinnerIndex = winner;
      debugPrint('Game over. Winner is player $winner (last trick).');
    } else {
      _trickNumber++;
      _leaderIndex = winner;
      _currentPlayerIndex = _nextActiveIndex(
        winner,
      ); // Winner leads next trick (skip eliminated if any).
      _leadSuit = null;
      _currentPlays.clear();
      debugPrint(
        'Starting trick $_trickNumber. Leader: P$_leaderIndex, Current: P$_currentPlayerIndex, Lead suit reset to null.',
      );
      // Highlights refreshed by caller via play path with tableaus context.
    }
  }

  int _activePlayerCount() => _eliminated.where((e) => !e).length;

  int _nextActiveIndex(int start) {
    var idx = start % _eliminated.length;
    for (var i = 0; i < _eliminated.length; i++) {
      if (!_eliminated[idx]) return idx;
      idx = (idx + 1) % _eliminated.length;
    }
    return start % _eliminated.length; // fallback
  }

  void _detectInstantWin(List<TableauPile> tableaus) {
    // Check each player's 6-card hand for special hands.
    // Priority: four-of-kind > flush (6 same suit) > low (all <=5).
    for (var p = 0; p < tableaus.length; p++) {
      final cards = tableaus[p].cards;
      if (cards.length != 6) continue;
      final rankGroups = <int, int>{};
      final suitGroups = <int, int>{};
      var allLow = true;
      for (final c in cards) {
        rankGroups.update(c.rank.value, (v) => v + 1, ifAbsent: () => 1);
        suitGroups.update(c.suit.value, (v) => v + 1, ifAbsent: () => 1);
        if (c.rank.value > 5 && c.rank.value != 1) allLow = false; // Ace treated as 1 already.
      }
      final hasFour = rankGroups.values.any((v) => v >= 4);
      final hasFlush = suitGroups.values.any((v) => v == 6);
      if (hasFour || hasFlush || allLow) {
        _gameWinnerIndex = p;
        _instantWinResolved = true;
        debugPrint(
          'Instant win detected for player $p: '
          '${hasFour
              ? 'Four-of-a-kind'
              : hasFlush
              ? 'Flush'
              : 'Low hand'}',
        );
        return;
      }
    }
  }

  void _updateLegalHighlights(List<TableauPile> tableaus) {
    if (_gameWinnerIndex != null || _instantWinResolved) return;
    // Clear existing highlight components from all cards.
    for (final pile in tableaus) {
      for (final card in pile.cards) {
        final toRemove = card.children.whereType<_LegalHighlight>().toList();
        for (final h in toRemove) {
          h.removeFromParent();
        }
      }
    }
    final active = _currentPlayerIndex;
    if (_eliminated[active]) return;
    final pile = tableaus[active];
    for (final card in pile.cards) {
      if (isLegalPlay(card)) {
        card.add(_LegalHighlight());
      }
    }
  }

  // Map Ace (1) to 14 for trick comparisons; keep others as-is.
  int _aceHigh(int raw) => raw == 1 ? 14 : raw;

  // Pure rules check used by UI (no side effects) to determine if a card may be played.
  bool isLegalPlay(Card card) {
    if (_gameWinnerIndex != null) {
      return false;
    }
    final pile = card.pile;
    if (pile is! TableauPile) {
      return false;
    }
    final game = pile.game;
    final world = game.world as dynamic;
    final tableaus = world.tableauPiles as List<TableauPile>;
    final playerIndex = tableaus.indexOf(pile);
    if (playerIndex != _currentPlayerIndex) {
      return false;
    }
    if (_eliminated[playerIndex]) {
      return false;
    }
    if (!card.isFaceUp) {
      return false;
    }
    if (!pile.cards.contains(card)) {
      return false; // already removed from tableau
    }
    if (_trickNumber == 6) {
      _logLegalityDecision(card, true, 'Final trick: free suit.');
      return true; // final trick: any card
    }
    if (_leadSuit == null) {
      _logLegalityDecision(card, true, 'No lead suit yet (leader).');
      return true; // leader may play anything (will set lead suit)
    }
    final leadValue = _leadSuit!.value;
    final holdsLead = pile.cards.any((c) => c.suit.value == leadValue);
    if (!holdsLead) {
      _logLegalityDecision(
        card,
        false,
        'Void in lead suit ${_suitLabel(_leadSuit!)} - must fold only.',
      );
      return false; // void players must fold, cannot play any card
    }
    // Must follow suit (tricks 1-5).
    if (card.suit.value != leadValue) {
      _logLegalityDecision(card, false, 'Must follow suit ${_suitLabel(_leadSuit!)}.');
      return false;
    }
    // Determine current best rank on table for lead suit (Ace high mapping).
    final currentBest = _currentHighestLeadRank();
    if (currentBest == null) {
      // No lead-suit card yet (shouldn't really happen because _leadSuit set by first such play), allow.
      _logLegalityDecision(card, true, 'First lead-suit card.');
      return true;
    }
    final pileLeadCards = pile.cards.where((c) => c.suit.value == leadValue).toList();
    final hasBeater = pileLeadCards.any((c) => _aceHigh(c.rank.value) > currentBest);
    final mapped = _aceHigh(card.rank.value);
    if (!hasBeater) {
      // Player cannot beat -> disallow any play (must fold instead).
      _logLegalityDecision(
        card,
        false,
        'Cannot beat current best ($currentBest); only fold allowed.',
      );
      return false;
    }
    final ok = mapped > currentBest; // Only higher strictly allowed.
    if (ok) {
      _logLegalityDecision(card, true, 'Beats current best ($currentBest).');
      return true;
    } else {
      _logLegalityDecision(
        card,
        false,
        'Must play a higher card than $currentBest; lower blocked.',
      );
      return false;
    }
  }

  void _logLegalityDecision(Card card, bool allowed, String reason) {
    if (!_logLegality) return;
    try {
      final pile = card.pile;
      if (pile is! TableauPile) return;
      final game = pile.game;
      final world = game.world as dynamic;
      final tableaus = world.tableauPiles as List<TableauPile>;
      final playerIndex = tableaus.indexOf(pile);
      final handCards = pile.cards.map((c) => c.toString()).join(',');
      final leadLbl = _leadSuit == null ? 'none' : _suitLabel(_leadSuit!);
      final holdsLead = _leadSuit != null
          ? pile.cards.any((c) => c.suit.value == _leadSuit!.value)
          : false;
      debugPrint(
        '[LEGality] P$playerIndex card=$card lead=$leadLbl holdsLead=$holdsLead trick=$_trickNumber hand=[$handCards] -> ${allowed ? 'ALLOWED' : 'BLOCKED'} :: $reason',
      );
    } catch (_) {
      // swallow logging failures
    }
  }

  String _suitLabel(Suit s) {
    // Map suit values to readable labels
    switch (s.value) {
      case 0:
        return 'Hearts';
      case 1:
        return 'Diamonds';
      case 2:
        return 'Clubs';
      case 3:
        return 'Spades';
      default:
        return 'Unknown${s.value}';
    }
  }

  // Highest mapped rank (Ace high) currently on table for the lead suit.
  int? _currentHighestLeadRank() {
    if (_leadSuit == null) return null;
    int? best;
    final leadValue = _leadSuit!.value;
    for (final play in _currentPlays) {
      if (play.folded) continue;
      if (play.card.suit.value != leadValue) continue;
      final v = _aceHigh(play.card.rank.value);
      if (best == null || v > best) best = v;
    }
    return best;
  }

  // Selection management -------------------------------------------------------
  bool selectCard(Card card) {
    debugPrint('=== SELECT ATTEMPT === Card: $card');
    if (_gameWinnerIndex != null) {
      debugPrint('Select blocked: game over');
      return false;
    }
    final pile = card.pile;
    if (pile is! TableauPile) {
      debugPrint('Select blocked: not in tableau pile');
      return false;
    }
    final game = pile.game;
    final world = game.world as dynamic;
    final tableaus = world.tableauPiles as List<TableauPile>;
    final playerIndex = tableaus.indexOf(pile);
    debugPrint(
      'Select check: playerIndex=$playerIndex, currentPlayer=$_currentPlayerIndex, eliminated=${_eliminated[playerIndex]}',
    );
    if (playerIndex != _currentPlayerIndex || _eliminated[playerIndex]) {
      debugPrint('Select blocked: not current player or eliminated');
      return false;
    }
    if (!pile.cards.contains(card)) {
      debugPrint('Select blocked: card not in pile');
      return false; // already played/folded this trick
    }
    // Allow selecting any card in player's pile (even if not legal to play, for fold option).
    final wasSelected = card == _selectedCard;
    _selectedCard = card == _selectedCard ? null : card;
    _updateSelectionHighlight(tableaus);
    debugPrint('Select SUCCESS: ${wasSelected ? "deselected" : "selected"} $card');
    return true;
  }

  void _updateSelectionHighlight(List<TableauPile> tableaus) {
    // Remove existing selection highlights.
    for (final pile in tableaus) {
      for (final card in pile.cards) {
        final toRemove = card.children.whereType<_SelectedHighlight>().toList();
        for (final s in toRemove) {
          s.removeFromParent();
        }
        // Also remove any lingering scale effects from prior versions (legacy pulse cleanup).
        for (final eff in card.children.whereType<ScaleEffect>().toList()) {
          eff.removeFromParent();
        }
      }
    }
    if (_selectedCard == null) {
      return; // nothing selected, effects already removed
    }
    // Add highlight to selected.
    _selectedCard!.add(_SelectedHighlight());
  }

  void _removeSelectionEffects(Card card) {
    // Remove highlight & pulse from a previously selected card.
    for (final h in card.children.whereType<_SelectedHighlight>().toList()) {
      h.removeFromParent();
    }
    for (final eff in card.children.whereType<ScaleEffect>().toList()) {
      eff.removeFromParent();
    }
  }

  // GameRules interface: movement & acceptance gates ---------------------------

  @override
  bool canMoveFromTableau(Card card) {
    // In trick mode we disallow drag/tap-based movement; actions must go through
    // Play / Fold buttons so legality (and must-beat rule) cannot be bypassed.
    return false;
  }

  @override
  bool canDropOnTableau({required Card moving, required Card? onTop}) => false;
  @override
  bool canDropOnFoundation({required Card moving, required FoundationPile foundation}) => false;
  @override
  bool canDrawFromStock(StockPile stock) => false;
  @override
  int getStockDrawCount() => 0; // Cat Te doesn't use stock pile drawing
  @override
  bool checkWin({required List<FoundationPile> foundations}) => _gameWinnerIndex != null;
}

// Highlight overlay for legal playable cards.
class _LegalHighlight extends PositionComponent {
  static final _paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 35
    ..color = const Color(0xAA42A5F5);

  @override
  void render(Canvas canvas) {
    final parentComponent = parent as PositionComponent;
    final rect = Rect.fromLTWH(0, 0, parentComponent.size.x, parentComponent.size.y);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(KlondikeGame.cardRadius));
    canvas.drawRRect(rrect, _paint);
  }
}

// Highlight for currently selected card (ready to Play/Fold)
class _SelectedHighlight extends PositionComponent {
  static final _paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 55
    ..color = const Color(0xAA66BB6A); // greenish

  @override
  void render(Canvas canvas) {
    final parentComponent = parent as PositionComponent;
    final rect = Rect.fromLTWH(0, 0, parentComponent.size.x, parentComponent.size.y);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(KlondikeGame.cardRadius));
    canvas.drawRRect(rrect, _paint);
  }
}
