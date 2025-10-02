import 'package:flutter/foundation.dart';
import 'dart:ui';
import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flame/game.dart';

import 'klondike_world.dart';
import 'rules/game_rules.dart';
import 'rules/klondike_rules.dart';
import 'rules/catte_rules.dart';
import 'rules/catte_trick_rules.dart';
import 'rules/eat_reds_rules.dart';
import 'rules/eat_pairs_rules.dart';

enum Action { newDeal, sameDeal, changeDraw, haveFun }

class KlondikeGame extends FlameGame<KlondikeWorld> {
  static const double cardGap = 175.0;
  static const double topGap = 500.0;
  static const double cardWidth = 1000.0;
  static const double cardHeight = 1400.0;
  static const double cardRadius = 100.0;
  static const double cardSpaceWidth = cardWidth + cardGap;
  static const double cardSpaceHeight = cardHeight + cardGap;
  static final Vector2 cardSize = Vector2(cardWidth, cardHeight);
  static final cardRRect = RRect.fromRectAndRadius(
    const Rect.fromLTWH(0, 0, cardWidth, cardHeight),
    const Radius.circular(cardRadius),
  );

  /// Constant used to decide when a short drag is treated as a TapUp event.
  static const double dragTolerance = cardWidth / 5;

  /// Constant used when creating Random seed.
  static const int maxInt = 0xFFFFFFFE; // = (2 to the power 32) - 1

  // Choose which rules to use for the game.
  RulesVariant rulesVariant = RulesVariant.klondike;
  // Persist selected CatTe trick-taking region between deals.
  CatTeRegion catTeRegion = CatTeRegion.khmer;
  // Persist selected EatReds player count between deals.
  int eatRedsPlayerCount = 2;
  // Persist selected EatPairs player count between deals.
  int eatPairsPlayerCount = 2;

  GameRules buildRules() {
    switch (rulesVariant) {
      case RulesVariant.catte:
        return CatTeRules();
      case RulesVariant.catteTrick:
        return CatTeTrickRules(region: catTeRegion);
      case RulesVariant.eatReds:
        return EatRedsRules(playerCount: eatRedsPlayerCount);
      case RulesVariant.eatPairs:
        return EatPairsRules(playerCount: eatPairsPlayerCount);
      case RulesVariant.klondike:
        return KlondikeRules();
    }
  }

  // Expose current rules from the active world for components.
  GameRules get rules => (world as dynamic).rules as GameRules;

  // This KlondikeGame constructor also initiates the first KlondikeWorld.
  KlondikeGame() : super(world: KlondikeWorld(rules: KlondikeRules())) {
    debugPrint('KlondikeGame initialized');
  }

  void rebuildWorld() {
    // Recreate world with selected rules
    world = KlondikeWorld(rules: buildRules());
  }

  // These three values persist between games and are starting conditions
  // for the next game to be played in KlondikeWorld. The actual seed is
  // computed in KlondikeWorld but is held here in case the player chooses
  // to replay a game by selecting Action.sameDeal.
  int klondikeDraw = 3;
  int seed = 1; // Last used seed (for Same deal). Updated on each new random deal.
  Action action = Action.newDeal;

  // Provide a method to advance to a fresh random seed for non-deterministic
  // games (e.g., CatTe) while retaining ability to replay via Same deal.
  void newRandomSeed() {
    seed = Random().nextInt(maxInt);
    debugPrint('Generated new random seed: $seed');
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);

    // Update camera viewport when window is resized
    world.updateCameraForResize(size);
  }
}

enum RulesVariant { klondike, catte, catteTrick, eatReds, eatPairs }

Sprite klondikeSprite(double x, double y, double width, double height) {
  debugPrint('klondikeSprite called with x: $x, y: $y, width: $width, height: $height');
  return Sprite(
    Flame.images.fromCache('klondike-sprites.png'),
    srcPosition: Vector2(x, y),
    srcSize: Vector2(width, height),
  );
}
