import 'package:flutter/foundation.dart';
import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/flame.dart';

import 'components/card.dart';
import 'components/eat_reds_add_to_layout_button.dart';
import 'components/eat_reds_play_button.dart';
import 'components/eat_reds_score_display.dart';
import 'components/flat_button.dart';
import 'components/foundation_pile.dart';
import 'components/stock_pile.dart';
import 'components/tableau_pile.dart';
import 'components/waste_pile.dart';

import 'klondike_game.dart';
import 'rules/game_rules.dart';
import 'rules/klondike_rules.dart';
import 'rules/catte_trick_rules.dart';
import 'rules/eat_reds_rules.dart';
// highlight / overlay helpers
import 'overlays/catte_trick_overlay.dart';
import 'overlays/eat_reds_status_overlay.dart';

class KlondikeWorld extends World with HasGameReference<KlondikeGame> {
  KlondikeWorld({GameRules? rules}) : rules = rules ?? KlondikeRules();

  final GameRules rules;
  final cardGap = KlondikeGame.cardGap;
  final topGap = KlondikeGame.topGap;
  final cardSpaceWidth = KlondikeGame.cardSpaceWidth;
  final cardSpaceHeight = KlondikeGame.cardSpaceHeight;

  final stock = StockPile(position: Vector2(0.0, 0.0));
  final waste = WastePile(position: Vector2(0.0, 0.0));
  final List<FoundationPile> foundations = [];
  final List<TableauPile> tableauPiles = [];
  final List<Card> cards = [];
  late Vector2 playAreaSize;

  // Track last selected card to avoid unnecessary button syncs
  Card? _lastSelectedCard;

  // EatReds UI components
  EatRedsPlayButton? _eatRedsPlayButton;
  EatRedsAddToLayoutButton? _eatRedsAddToLayoutButton;
  final List<EatRedsScoreDisplay> _eatRedsScoreDisplays = [];

  @override
  Future<void> onLoad() async {
    debugPrint('KlondikeWorld onLoad called');
    await Flame.images.load('klondike-sprites.png');
    debugPrint('Asset klondike-sprites.png loaded');
    debugPrint('Setting up piles and cards');

    // For a new random deal, create a new seed. Preserve existing seed only
    // when Action.sameDeal is requested.
    if (game.action != Action.sameDeal) {
      game.newRandomSeed();
    } else {
      debugPrint('Reusing existing seed: ${game.seed}');
    }

    // Let rules decide initial pile positions/layout
    rules.setupPiles(
      cardSize: KlondikeGame.cardSize,
      cardGap: cardGap,
      topGap: topGap,
      cardSpaceWidth: cardSpaceWidth,
      cardSpaceHeight: cardSpaceHeight,
      stock: stock,
      waste: waste,
      foundations: foundations,
      tableaus: tableauPiles,
      checkWin: checkWin,
    );

    Card? baseCard;
    if (rules.usesBaseCard) {
      // Add a Base Card to the Stock Pile, above the pile and below other cards.
      debugPrint('Creating base card for StockPile');
      baseCard = Card(1, 0, isBaseCard: true)
        ..position = stock.position
        ..priority = -1
        ..pile = stock;
      stock.priority = -2;
    } else {
      debugPrint('Rules specify no base card. Skipping base card creation.');
    }

    for (var rank = 1; rank <= 13; rank++) {
      for (var suit = 0; suit < 4; suit++) {
        final card = Card(rank, suit);
        card.position = stock.position;
        cards.add(card);
        debugPrint('Created card: rank $rank, suit $suit');
      }
    }

    debugPrint('Adding piles and cards to world');
    add(stock);
    add(waste);
    addAll(foundations);
    addAll(tableauPiles);
    addAll(cards);
    if (baseCard != null) {
      add(baseCard);
    }

    playAreaSize = rules.playAreaSize;
    debugPrint('Play area size set: $playAreaSize');
    final gameMidX = playAreaSize.x / 2;

    // Add a toggle to switch rules at runtime (left of the first button).
    addRulesToggleButton(gameMidX - cardSpaceWidth);

    addButton('New deal', gameMidX, Action.newDeal);
    addButton('Same deal', gameMidX + cardSpaceWidth, Action.sameDeal);
    // The draw mode toggle is only relevant for classic Klondike rules.
    var nextButtonOffset = 2; // track how many buttons placed to compute later offsets
    if (rules is KlondikeRules) {
      addButton('Draw 1 or 3', gameMidX + 2 * cardSpaceWidth, Action.changeDraw);
      nextButtonOffset = 3;
    }
    addButton('Have fun', gameMidX + nextButtonOffset * cardSpaceWidth, Action.haveFun);

    // EatReds player count button appears right after "Have Fun" when that ruleset is active
    if (rules is EatRedsRules) {
      final playerButtonX = gameMidX + (nextButtonOffset + 1) * cardSpaceWidth;
      addEatRedsPlayerButton(playerButtonX, rules as EatRedsRules);
      // Add Play button and score displays for EatReds
      addEatRedsUIComponents(rules as EatRedsRules);
    }

    // CatTe trick action buttons (Play / Fold) appear when that ruleset active.
    if (rules is CatTeTrickRules) {
      // Place after existing buttons (3 for CatTeTrick, 4 if Klondike draw toggle present when switching variants dynamically).
      final existingCount = _controlButtons.length; // current control buttons before Play/Fold
      final baseX = gameMidX + existingCount * cardSpaceWidth;
      addActionButtons(baseX);
    }

    // Center the whole play area and add responsive margins.
    final camera = game.camera;
    // Responsive margins as a percentage of play area (min 1 card gap vertically and horizontally)
    final marginX = max(cardGap, playAreaSize.x * 0.05);
    final marginY = max(topGap, playAreaSize.y * 0.05);
    final visibleWithMargins = Vector2(playAreaSize.x + marginX * 2, playAreaSize.y + marginY * 2);
    camera.viewfinder.visibleGameSize = visibleWithMargins;
    camera.viewfinder.position = playAreaSize / 2; // center of world
    camera.viewfinder.anchor = Anchor.center;
    debugPrint(
      'Camera configured (centered). margins=($marginX,$marginY), visible=$visibleWithMargins, position=${camera.viewfinder.position}',
    );

    // Dealing via rules
    rules.deal(deck: cards, tableaus: tableauPiles, stock: stock, waste: waste, seed: game.seed);

    // Add overlay components for CatTe trick rules (simple text labels) after deal.
    if (rules is CatTeTrickRules) {
      add(CatTeTrickStatusOverlay(rules as CatTeTrickRules));
    }

    // Add overlay components for Eat Reds rules (player scores and status)
    if (rules is EatRedsRules) {
      add(EatRedsStatusOverlay(rules as EatRedsRules));
    }
  }

  FlatButton? _playBtn;
  FlatButton? _foldBtn;
  final List<FlatButton> _controlButtons = [];

  void addActionButtons(double startX) {
    final r = rules as CatTeTrickRules;
    // Create buttons same size as existing ones; store & relayout all controls on one row.
    final btnSize = Vector2(KlondikeGame.cardWidth, 0.6 * topGap);
    _playBtn = FlatButton(
      'Play',
      size: btnSize,
      position: Vector2.zero(),
      onReleased: () {
        final sel = r.selectedCard;
        if (sel == null) return;
        debugPrint('[PLAY BTN] Attempting to play $sel via Play button');
        r.playCard(sel);
      },
    );
    _foldBtn = FlatButton(
      'Fold',
      size: btnSize,
      position: Vector2.zero(),
      onReleased: () {
        final sel = r.selectedCard;
        if (sel == null) return;
        debugPrint('[FOLD BTN] Attempting to fold $sel via Fold button');
        r.foldCard(sel);
      },
    );
    add(_playBtn!);
    add(_foldBtn!);
    _controlButtons.addAll([_playBtn!, _foldBtn!]);
    // Re-layout all buttons (startX not directly used because we now distribute evenly across play width).
    _layoutControlButtons();
  }

  void _layoutControlButtons() {
    if (_controlButtons.isEmpty) return;
    // Single row layout: all control buttons (including Play/Fold) evenly spaced.
    final leftMargin = cardGap + 0.0; // small inset
    final rightMargin = cardGap + 0.0;
    final usableWidth = playAreaSize.x - leftMargin - rightMargin;
    final totalButtonWidth = _controlButtons.fold<double>(0, (s, b) => s + b.size.x);
    final gaps = _controlButtons.length - 1;
    double gap = 0;
    if (usableWidth > totalButtonWidth && gaps > 0) {
      gap = (usableWidth - totalButtonWidth) / gaps;
    }
    final centerY = topGap / 2; // original row center
    var x = leftMargin + _controlButtons.first.size.x / 2;
    for (final btn in _controlButtons) {
      btn.position = Vector2(x, centerY);
      x += btn.size.x + gap;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    // Dynamic highlight for current player's tableau in CatTeTrickRules.
    if (rules is CatTeTrickRules) {
      final r = rules as CatTeTrickRules;
      for (var i = 0; i < tableauPiles.length; i++) {
        final pile = tableauPiles[i];

        // Current player highlight
        final existing = pile.children.whereType<CatTeHighlightFrame>().firstOrNull;
        final active = r.currentPlayerIndex == i && r.winnerIndex == null;
        if (active && existing == null) {
          pile.add(CatTeHighlightFrame());
        } else if (!active && existing != null) {
          existing.removeFromParent();
        }

        // Leader indicator
        final leaderIndicator = pile.children.whereType<CatTeLeaderIndicator>().firstOrNull;
        final isLeader = r.leaderIndex == i && r.winnerIndex == null;
        if (isLeader && leaderIndicator == null) {
          pile.add(CatTeLeaderIndicator());
        } else if (!isLeader && leaderIndicator != null) {
          leaderIndicator.removeFromParent();
        }
      }
      // Only sync buttons when selection changes to avoid interference
      final currentSelected = r.selectedCard;
      if (currentSelected != _lastSelectedCard) {
        _lastSelectedCard = currentSelected;
        _syncActionButtons(r);
      }
    }
  }

  void _syncActionButtons(CatTeTrickRules r) {
    if (_playBtn == null || _foldBtn == null) return;
    final sel = r.selectedCard;
    var canPlay = false;
    var canFold = false;
    if (sel != null) {
      final pile = sel.pile;
      if (pile is TableauPile) {
        final playerIndex = tableauPiles.indexOf(pile);
        final eliminated = r.eliminatedView[playerIndex];
        if (playerIndex == r.currentPlayerIndex && !eliminated && sel.isFaceUp) {
          // Delegate to rules for authoritative legality (must-follow & must-beat).
          canPlay = r.isLegalPlay(sel);
        }
        if (playerIndex == r.currentPlayerIndex && !eliminated && playerIndex != r.leaderIndex) {
          // Players can always fold (except the leader) - it's a strategic choice
          canFold = true;
          debugPrint('[FOLD BTN] P$playerIndex can fold (not leader), canFold=$canFold');
        }
      }
    }
    _setBtnState(_playBtn!, canPlay, activeColor: const Color(0xFF2E7D32)); // green when enabled
    _setBtnState(
      _foldBtn!,
      canFold,
      activeColor: const Color(0xFF6D4C41),
    ); // brown-ish when enabled
  }

  void _setBtnState(FlatButton btn, bool enabled, {required Color activeColor}) {
    btn.enabled = enabled;
    btn.activeColor = activeColor;
  }

  void addEatRedsPlayerButton(double buttonX, EatRedsRules rules) {
    final label = '${rules.playerCount} Players';
    debugPrint('Adding EatReds player count button: $label at $buttonX');
    final button = FlatButton(
      label,
      size: Vector2(KlondikeGame.cardWidth, 0.6 * topGap),
      position: Vector2(buttonX, topGap / 2),
      onReleased: () {
        // Cycle through player counts 2-4
        final current = rules.playerCount;
        final next = current >= 4 ? 2 : current + 1;
        rules.setPlayerCount(next);
        // Save to game object for persistence
        game.eatRedsPlayerCount = next;
        debugPrint('Changed EatReds players: $current -> $next');
        // Trigger new deal to apply player count change
        game.action = Action.newDeal;
        game.rebuildWorld();
      },
    );
    add(button);
    _controlButtons.add(button);
  }

  void addEatRedsUIComponents(EatRedsRules rules) {
    // Clear existing EatReds UI components
    if (_eatRedsPlayButton != null) {
      remove(_eatRedsPlayButton!);
      _eatRedsPlayButton = null;
    }
    if (_eatRedsAddToLayoutButton != null) {
      remove(_eatRedsAddToLayoutButton!);
      _eatRedsAddToLayoutButton = null;
    }
    for (final scoreDisplay in _eatRedsScoreDisplays) {
      remove(scoreDisplay);
    }
    _eatRedsScoreDisplays.clear();

    // Add Play button to the left of the layout cards
    // Layout cards are centered around waste pile position from EatRedsRules
    final layoutCenterX = 2.5 * cardSpaceWidth + cardGap;
    final layoutCenterY = 1.5 * cardSpaceHeight + topGap;
    final playButtonPos = Vector2(
      layoutCenterX -
          2.0 * cardSpaceWidth -
          cardGap, // Two card spaces to the left for more separation
      layoutCenterY, // Same vertical level as layout center
    );
    _eatRedsPlayButton = EatRedsPlayButton(position: playButtonPos);
    add(_eatRedsPlayButton!);

    // Add Add to Layout button below the Play button
    final buttonHeight = 0.6 * KlondikeGame.topGap;
    final buttonGap = 0.1 * KlondikeGame.topGap; // 10% of topGap for proportional spacing
    final addToLayoutButtonPos = Vector2(
      playButtonPos.x,
      playButtonPos.y + buttonHeight * 2 + buttonGap, // Button height + gap below Play button
    );
    _eatRedsAddToLayoutButton = EatRedsAddToLayoutButton(position: addToLayoutButtonPos);
    add(_eatRedsAddToLayoutButton!);

    // Add score displays above each foundation pile
    for (var i = 0; i < rules.playerCount; i++) {
      if (i < foundations.length) {
        final foundationPos = foundations[i].position;
        final scorePos = Vector2(
          foundationPos.x + KlondikeGame.cardWidth / 2, // Center above foundation
          foundationPos.y - 25, // Above the foundation pile
        );
        final scoreDisplay = EatRedsScoreDisplay(playerIndex: i, position: scorePos);
        _eatRedsScoreDisplays.add(scoreDisplay);
        add(scoreDisplay);
      }
    }

    debugPrint(
      'Added EatReds UI components: Play button at (${playButtonPos.x}, ${playButtonPos.y}) and ${_eatRedsScoreDisplays.length} score displays',
    );
  }

  void addRulesToggleButton(double buttonX) {
    String labelFor(RulesVariant v) {
      switch (v) {
        case RulesVariant.klondike:
          return 'Klondike';
        case RulesVariant.catte:
          return 'CatTe Simple';
        case RulesVariant.catteTrick:
          return 'CatTe Trick';
        case RulesVariant.eatReds:
          return 'Eat Reds';
      }
    }

    final label = labelFor(game.rulesVariant);
    debugPrint('Adding rules toggle button: $label at $buttonX');
    final button = FlatButton(
      label,
      size: Vector2(KlondikeGame.cardWidth, 0.6 * topGap),
      position: Vector2(buttonX, topGap / 2),
      onReleased: () {
        final before = game.rulesVariant;
        // Cycle through 3 variants.
        game.rulesVariant = RulesVariant.values[(before.index + 1) % RulesVariant.values.length];
        final after = game.rulesVariant;
        debugPrint('Toggling rules: $before -> $after');
        game.rebuildWorld();
      },
    );
    add(button);
    _controlButtons.add(button);
  }

  void addButton(String label, double buttonX, Action action) {
    debugPrint('Adding button: $label at $buttonX for $action');
    final button = FlatButton(
      label,
      size: Vector2(KlondikeGame.cardWidth, 0.6 * topGap),
      position: Vector2(buttonX, topGap / 2),
      onReleased: () {
        debugPrint('Button $label pressed, action: $action');
        if (action == Action.haveFun) {
          // Shortcut to the "win" sequence, for Tutorial purposes only.
          letsCelebrate();
        } else {
          // Restart with a new deal or the same deal as before.
          game.action = action;
          // Preserve currently selected rules variant when starting a new or same deal.
          game.world = KlondikeWorld(rules: game.buildRules());
        }
      },
    );
    add(button);
    _controlButtons.add(button);
  }

  void deal() {
    debugPrint('Dealing cards');
    // Keep the original deal for now to preserve behavior when pressing buttons
    // but in onLoad we already deal via rules.
  }

  void checkWin() {
    // Callback from a Foundation Pile when it is full (Ace to King).
    debugPrint('Checking win condition');
    if (rules.checkWin(foundations: foundations)) {
      debugPrint('All foundation piles complete!');
      letsCelebrate();
    }
  }

  void letsCelebrate({int phase = 1}) {
    // Deal won: bring all cards to the middle of the screen (phase 1)
    // then scatter them to points just outside the screen (phase 2).
    //
    // First get the device's screen-size in game co-ordinates, then get the
    // top-left of the off-screen area that will accept the scattered cards.
    // With camera anchored at center, compute screen center and top-left
    final vf = game.camera.viewfinder;
    final cameraZoom = vf.zoom;
    final zoomedScreen = game.size / cameraZoom; // world units
    final worldCenter = vf.position; // center of visible region
    final screenCenter = worldCenter - KlondikeGame.cardSize / 2;
    final topLeft = worldCenter - zoomedScreen / 2 - KlondikeGame.cardSize / 2;
    final nCards = cards.length;
    final offscreenHeight = zoomedScreen.y + KlondikeGame.cardSize.y;
    final offscreenWidth = zoomedScreen.x + KlondikeGame.cardSize.x;
    final spacing = 2.0 * (offscreenHeight + offscreenWidth) / nCards;

    // Starting points, directions and lengths of offscreen rect's sides.
    final corner = [
      Vector2(0.0, 0.0),
      Vector2(0.0, offscreenHeight),
      Vector2(offscreenWidth, offscreenHeight),
      Vector2(offscreenWidth, 0.0),
    ];
    final direction = [
      Vector2(0.0, 1.0),
      Vector2(1.0, 0.0),
      Vector2(0.0, -1.0),
      Vector2(-1.0, 0.0),
    ];
    final length = [offscreenHeight, offscreenWidth, offscreenHeight, offscreenWidth];

    var side = 0;
    var cardsToMove = nCards;
    var offScreenPosition = corner[side] + topLeft;
    var space = length[side];
    var cardNum = 0;

    while (cardNum < nCards) {
      final cardIndex = phase == 1 ? cardNum : nCards - cardNum - 1;
      final card = cards[cardIndex];
      card.priority = cardIndex + 1;
      if (card.isFaceDown) {
        card.flip();
      }
      // Start cards a short time apart to give a riffle effect.
      final delay = phase == 1 ? cardNum * 0.02 : 0.5 + cardNum * 0.04;
      final destination = (phase == 1) ? screenCenter : offScreenPosition;
      card.doMove(
        destination,
        speed: (phase == 1) ? 15.0 : 5.0,
        start: delay,
        onComplete: () {
          cardsToMove--;
          if (cardsToMove == 0) {
            if (phase == 1) {
              letsCelebrate(phase: 2);
            } else {
              // Restart with a new deal after winning or pressing "Have fun".
              game.action = Action.newDeal;
              // Preserve current rules variant after celebration restart.
              game.world = KlondikeWorld(rules: game.buildRules());
            }
          }
        },
      );
      cardNum++;
      if (phase == 1) {
        continue;
      }

      // Phase 2: next card goes to same side with full spacing, if possible.
      offScreenPosition = offScreenPosition + direction[side] * spacing;
      space = space - spacing;
      if ((space < 0.0) && (side < 3)) {
        // Out of space: change to the next side and use excess spacing there.
        side++;
        offScreenPosition = corner[side] + topLeft - direction[side] * space;
        space = length[side] + space;
      }
    }
  }

  @override
  void onRemove() {
    // Clean up EatReds UI components when world is removed
    cleanupEatRedsUIComponents();
    super.onRemove();
  }

  void cleanupEatRedsUIComponents() {
    if (_eatRedsPlayButton != null) {
      remove(_eatRedsPlayButton!);
      _eatRedsPlayButton = null;
    }
    if (_eatRedsAddToLayoutButton != null) {
      remove(_eatRedsAddToLayoutButton!);
      _eatRedsAddToLayoutButton = null;
    }
    for (final scoreDisplay in _eatRedsScoreDisplays) {
      remove(scoreDisplay);
    }
    _eatRedsScoreDisplays.clear();
  }
}

// (Button dim overlay component removed; FlatButton now handles enabled coloring internally.)
