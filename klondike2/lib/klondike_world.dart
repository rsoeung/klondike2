import 'package:flutter/foundation.dart';
import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/flame.dart';

import 'components/card.dart';
import 'components/flat_button.dart';
import 'components/foundation_pile.dart';
import 'components/stock_pile.dart';
import 'components/tableau_pile.dart';
import 'components/waste_pile.dart';

import 'klondike_game.dart';
import 'rules/game_rules.dart';
import 'rules/klondike_rules.dart';

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

  @override
  Future<void> onLoad() async {
    debugPrint('KlondikeWorld onLoad called');
    await Flame.images.load('klondike-sprites.png');
    debugPrint('Asset klondike-sprites.png loaded');
    debugPrint('Setting up piles and cards');

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
    addButton('Draw 1 or 3', gameMidX + 2 * cardSpaceWidth, Action.changeDraw);
    addButton('Have fun', gameMidX + 3 * cardSpaceWidth, Action.haveFun);

    // Center the whole play area and add responsive margins.
    final camera = game.camera;
    // Responsive margins as a percentage of play area (min 1 card gap vertically and horizontally)
    final marginX = max(cardGap, playAreaSize.x * 0.05);
    final marginY = max(topGap, playAreaSize.y * 0.05);
    final visibleWithMargins = Vector2(
      playAreaSize.x + marginX * 2,
      playAreaSize.y + marginY * 2,
    );
    camera.viewfinder.visibleGameSize = visibleWithMargins;
    camera.viewfinder.position = playAreaSize / 2; // center of world
    camera.viewfinder.anchor = Anchor.center;
    debugPrint(
      'Camera configured (centered). margins=($marginX,$marginY), visible=$visibleWithMargins, position=${camera.viewfinder.position}',
    );

    // Dealing via rules
    rules.deal(
      deck: cards,
      tableaus: tableauPiles,
      stock: stock,
      waste: waste,
      seed: game.seed,
    );
  }

  void addRulesToggleButton(double buttonX) {
    final current = game.rulesVariant == RulesVariant.klondike
        ? 'Klondike'
        : 'CatTe';
    final label = 'Rules: $current';
    debugPrint('Adding rules toggle button: $label at $buttonX');
    final button = FlatButton(
      label,
      size: Vector2(KlondikeGame.cardWidth, 0.6 * topGap),
      position: Vector2(buttonX, topGap / 2),
      onReleased: () {
        final before = game.rulesVariant;
        game.rulesVariant = before == RulesVariant.klondike
            ? RulesVariant.catte
            : RulesVariant.klondike;
        final after = game.rulesVariant;
        debugPrint('Toggling rules: $before -> $after');
        game.rebuildWorld();
      },
    );
    add(button);
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
          game.world = KlondikeWorld();
        }
      },
    );
    add(button);
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
    final length = [
      offscreenHeight,
      offscreenWidth,
      offscreenHeight,
      offscreenWidth,
    ];

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
              game.world = KlondikeWorld();
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
}
