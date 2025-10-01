import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

import '../klondike_game.dart';
import '../klondike_world.dart';
import '../pile.dart';
import '../rank.dart';
import '../suit.dart';
import 'foundation_pile.dart';
import 'stock_pile.dart';
import 'tableau_pile.dart';
import '../rules/klondike_rules.dart';
import '../rules/catte_rules.dart';
import '../rules/catte_trick_rules.dart';
import '../rules/eat_reds_rules.dart';

class Card extends PositionComponent
    with DragCallbacks, TapCallbacks, HasWorldReference<KlondikeWorld> {
  Card(int intRank, int intSuit, {this.isBaseCard = false})
    : rank = Rank.fromInt(intRank),
      suit = Suit.fromInt(intSuit),
      super(size: KlondikeGame.cardSize);

  final Rank rank;
  final Suit suit;
  Pile? pile;

  // A Base Card is rendered in outline only and is NOT playable. It can be
  // added to the base of a Pile (e.g. the Stock Pile) to allow it to handle
  // taps and short drags (on an empty Pile) with the same behavior and
  // tolerances as for regular cards (see KlondikeGame.dragTolerance) and using
  // the same event-handling code, but with different handleTapUp() methods.
  final bool isBaseCard;

  // Selection state for EatReds card pairing
  bool _isSelected = false;
  bool get isSelected => _isSelected;

  bool _faceUp = false;
  bool _isAnimatedFlip = false;
  bool _isFaceUpView = false;
  bool _isDragging = false;
  Vector2 _whereCardStarted = Vector2(0, 0);

  final List<Card> attachedCards = [];

  bool get isFaceUp => _faceUp;
  bool get isFaceDown => !_faceUp;
  void flip() {
    if (_isAnimatedFlip) {
      // Let the animation determine the FaceUp/FaceDown state.
      _faceUp = _isFaceUpView;
    } else {
      // No animation: flip and render the card immediately.
      _faceUp = !_faceUp;
      _isFaceUpView = _faceUp;
    }
  }

  @override
  String toString() => rank.label + suit.label; // e.g. "Q♠" or "10♦"

  //#region Rendering

  @override
  void render(Canvas canvas) {
    if (isBaseCard) {
      _renderBaseCard(canvas);
      return;
    }
    if (_isFaceUpView) {
      _renderFront(canvas);
    } else {
      _renderBack(canvas);
    }

    // Add selection highlighting for EatReds
    if (_isSelected && world.game.rules is EatRedsRules) {
      // debugPrint('Rendering selection highlight for ${rank} of ${suit}');
      _renderSelectionHighlight(canvas);
    }
  }

  static final Paint backBackgroundPaint = Paint()..color = const Color(0xff380c02);
  static final Paint selectionPaint = Paint()
    ..color =
        const Color(0xFF00FF00) // Bright green for better visibility
    ..style = PaintingStyle.stroke
    ..strokeWidth = 6.0; // Thicker border for better visibility
  static final Paint selectionBackgroundPaint = Paint()
    ..color =
        const Color(0x4400FF00) // Semi-transparent green background
    ..style = PaintingStyle.fill;
  static final Paint backBorderPaint1 = Paint()
    ..color = const Color(0xffdbaf58)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 10;
  static final Paint backBorderPaint2 = Paint()
    ..color = const Color(0x5CEF971B)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 35;
  static final RRect cardRRect = RRect.fromRectAndRadius(
    KlondikeGame.cardSize.toRect(),
    const Radius.circular(KlondikeGame.cardRadius),
  );
  static final RRect backRRectInner = cardRRect.deflate(40);
  static final Sprite flameSprite = klondikeSprite(1367, 6, 357, 501);

  void _renderBack(Canvas canvas) {
    canvas.drawRRect(cardRRect, backBackgroundPaint);
    canvas.drawRRect(cardRRect, backBorderPaint1);
    canvas.drawRRect(backRRectInner, backBorderPaint2);
    flameSprite.render(canvas, position: size / 2, anchor: Anchor.center);
  }

  void _renderBaseCard(Canvas canvas) {
    canvas.drawRRect(cardRRect, backBorderPaint1);
  }

  void _renderSelectionHighlight(Canvas canvas) {
    // Draw green background and border for selected cards
    canvas.drawRRect(cardRRect, selectionBackgroundPaint); // Background first
    canvas.drawRRect(cardRRect, selectionPaint); // Border on top
    // debugPrint('Selection highlight rendered with background and border');
  }

  // Front face styling: white background, red suits red, black suits black.
  static final Paint frontBackgroundPaint = Paint()..color = const Color(0xffffffff); // pure white
  static final Paint redBorderPaint = Paint()
    ..color =
        const Color(0xffcc0000) // strong red border
    ..style = PaintingStyle.stroke
    ..strokeWidth = 10;
  static final Paint blackBorderPaint = Paint()
    ..color =
        const Color(0xff000000) // pure black border
    ..style = PaintingStyle.stroke
    ..strokeWidth = 10;
  static final Sprite redJack = klondikeSprite(81, 565, 562, 488);
  static final Sprite redQueen = klondikeSprite(717, 541, 486, 515);
  static final Sprite redKing = klondikeSprite(1305, 532, 407, 549);
  // Use the same sprites for black suits; assume artwork neutral enough. If a
  // different visual is desired, separate asset regions can be defined.
  static final Sprite blackJack = klondikeSprite(81, 565, 562, 488);
  static final Sprite blackQueen = klondikeSprite(717, 541, 486, 515);
  static final Sprite blackKing = klondikeSprite(1305, 532, 407, 549);

  void _renderFront(Canvas canvas) {
    canvas.drawRRect(cardRRect, frontBackgroundPaint);
    canvas.drawRRect(cardRRect, suit.isRed ? redBorderPaint : blackBorderPaint);

    final rankSprite = suit.isBlack ? rank.blackSprite : rank.redSprite;
    final suitSprite = suit.sprite;
    // Enforce pure red / pure black coloring for ranks & suits independent of
    // original sprite sheet hues (which appeared yellow / blue).
    final Paint glyphPaint = Paint()
      ..colorFilter = ColorFilter.mode(
        suit.isRed ? const Color(0xffd00000) : const Color(0xff000000),
        BlendMode.srcATop,
      );
    // Corner glyphs:
    // Keep rank size, slightly enlarge bottom (rotated) suit for better legibility.
    const double topSuitScale = 0.5; // unchanged for consistency
    const double bottomSuitScale = 0.5; // enlarged from 0.5
    const double rankX = 0.1;
    const double rankY = 0.08;
    const double suitY = 0.18; // baseline suit Y (relative)
    _drawSprite(canvas, rankSprite, rankX, rankY, override: glyphPaint);
    _drawSprite(canvas, suitSprite, rankX, suitY, scale: topSuitScale, override: glyphPaint);
    // Rotated (bottom) rank
    _drawSprite(canvas, rankSprite, rankX, rankY, rotate: true, override: glyphPaint);
    // Rotated (bottom) suit enlarged
    _drawSprite(
      canvas,
      suitSprite,
      rankX,
      suitY + 0.004, // slight downward nudge to visually center bigger suit
      scale: bottomSuitScale,
      rotate: true,
      override: glyphPaint,
    );
    // Apply a consistent paint for all interior pips (rank patterns).
    final Paint pipPaint = Paint()
      ..colorFilter = ColorFilter.mode(
        suit.isRed ? const Color(0xffd00000) : const Color(0xff000000),
        BlendMode.srcATop,
      );
    switch (rank.value) {
      case 1:
        _drawSprite(canvas, suitSprite, 0.5, 0.5, scale: 2.5, override: pipPaint);
      case 2:
        _drawSprite(canvas, suitSprite, 0.5, 0.25, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.5, 0.25, rotate: true, override: pipPaint);
      case 3:
        _drawSprite(canvas, suitSprite, 0.5, 0.2, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.5, 0.5, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.5, 0.2, rotate: true, override: pipPaint);
      case 4:
        _drawSprite(canvas, suitSprite, 0.3, 0.25, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.7, 0.25, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.3, 0.25, rotate: true, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.7, 0.25, rotate: true, override: pipPaint);
      case 5:
        _drawSprite(canvas, suitSprite, 0.3, 0.25, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.7, 0.25, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.3, 0.25, rotate: true, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.7, 0.25, rotate: true, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.5, 0.5, override: pipPaint);
      case 6:
        _drawSprite(canvas, suitSprite, 0.3, 0.25, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.7, 0.25, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.3, 0.5, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.7, 0.5, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.3, 0.25, rotate: true, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.7, 0.25, rotate: true, override: pipPaint);
      case 7:
        _drawSprite(canvas, suitSprite, 0.3, 0.2, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.7, 0.2, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.5, 0.35, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.3, 0.5, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.7, 0.5, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.3, 0.2, rotate: true, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.7, 0.2, rotate: true, override: pipPaint);
      case 8:
        _drawSprite(canvas, suitSprite, 0.3, 0.2, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.7, 0.2, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.5, 0.35, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.3, 0.5, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.7, 0.5, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.3, 0.2, rotate: true, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.7, 0.2, rotate: true, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.5, 0.35, rotate: true, override: pipPaint);
      case 9:
        _drawSprite(canvas, suitSprite, 0.3, 0.2, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.7, 0.2, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.5, 0.3, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.3, 0.4, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.7, 0.4, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.3, 0.2, rotate: true, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.7, 0.2, rotate: true, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.3, 0.4, rotate: true, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.7, 0.4, rotate: true, override: pipPaint);
      case 10:
        _drawSprite(canvas, suitSprite, 0.3, 0.2, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.7, 0.2, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.5, 0.3, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.3, 0.4, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.7, 0.4, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.3, 0.2, rotate: true, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.7, 0.2, rotate: true, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.5, 0.3, rotate: true, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.3, 0.4, rotate: true, override: pipPaint);
        _drawSprite(canvas, suitSprite, 0.7, 0.4, rotate: true, override: pipPaint);
      case 11:
        _drawSprite(canvas, suit.isRed ? redJack : blackJack, 0.5, 0.5, override: pipPaint);
      case 12:
        _drawSprite(canvas, suit.isRed ? redQueen : blackQueen, 0.5, 0.5, override: pipPaint);
      case 13:
        _drawSprite(canvas, suit.isRed ? redKing : blackKing, 0.5, 0.5, override: pipPaint);
    }
  }

  void _drawSprite(
    Canvas canvas,
    Sprite sprite,
    double relativeX,
    double relativeY, {
    double scale = 1,
    bool rotate = false,
    Paint? override,
  }) {
    if (rotate) {
      canvas.save();
      canvas.translate(size.x / 2, size.y / 2);
      canvas.rotate(pi);
      canvas.translate(-size.x / 2, -size.y / 2);
    }
    sprite.render(
      canvas,
      position: Vector2(relativeX * size.x, relativeY * size.y),
      anchor: Anchor.center,
      size: sprite.srcSize.scaled(scale),
      overridePaint: override,
    );
    if (rotate) {
      canvas.restore();
    }
  }

  //#endregion

  //#region Card-Dragging

  @override
  void onTapCancel(TapCancelEvent event) {
    if (pile is StockPile) {
      _isDragging = false;
      handleTapUp();
    }
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (pile is StockPile) {
      _isDragging = false;
      return;
    }
    // In CatTeTrickRules allow dragging any face-up card, but restrict playing via playCard method
    if (world.game.rules is CatTeTrickRules) {
      // Allow dragging any face-up card in a tableau pile
      if (pile is TableauPile && isFaceUp) {
        _isDragging = true;
        _whereCardStarted = position.clone();
        attachedCards.clear();
        priority = 150; // elevate above others while dragging
        debugPrint('[DRAG-START] Drag allowed for $this');
      } else {
        _isDragging = false;
        debugPrint('[DRAG-START] Drag blocked - not face-up tableau card: $this');
      }
      return; // No multi-card drags in trick mode.
    }
    // Clone the position, else _whereCardStarted changes as the position does.
    _whereCardStarted = position.clone();
    attachedCards.clear();
    if (pile?.canMoveCard(this, MoveMethod.drag) ?? false) {
      _isDragging = true;
      priority = 100;
      if (pile is TableauPile) {
        if (world.game.rules is CatTeRules || world.game.rules is EatRedsRules) {
          // In CatTe and EatReds we always drag a single card (no building sequences).
          attachedCards.clear();
        } else {
          final extraCards = (pile! as TableauPile).cardsOnTop(this);
          for (final card in extraCards) {
            card.priority = attachedCards.length + 101;
            attachedCards.add(card);
          }
        }
      }
    }
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (!_isDragging) {
      return;
    }
    final delta = event.localDelta;
    position.add(delta);
    for (var card in attachedCards) {
      card.position.add(delta);
    }
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (!_isDragging) {
      return; // Nothing to finalize.
    }
    _isDragging = false;

    // Trick mode drag -> only play if dropped on a foundation pile, otherwise return to tableau
    if (world.game.rules is CatTeTrickRules) {
      final rules = world.game.rules as CatTeTrickRules;

      // Check what's under the center-point of this card when dropped
      final dropPiles = parent!.componentsAtPoint(position + size / 2).whereType<Pile>().toList();

      if (dropPiles.isNotEmpty && dropPiles.first is FoundationPile) {
        // Dropped on a foundation pile - attempt to play the card
        final success = rules.playCard(this);
        if (!success) {
          // Play rejected - return to original position
          doMove(_whereCardStarted, onComplete: () => pile?.returnCard(this));
        }
      } else {
        // Not dropped on a foundation pile - just return to tableau
        doMove(_whereCardStarted, onComplete: () => pile?.returnCard(this));
      }
      return;
    }

    // If short drag, return card to Pile and treat it as having been tapped.
    final shortDrag = (position - _whereCardStarted).length < KlondikeGame.dragTolerance;
    if (shortDrag && attachedCards.isEmpty) {
      doMove(
        _whereCardStarted,
        onComplete: () {
          pile!.returnCard(this);
          // Card moves to its Foundation Pile next, if valid, or it stays put.
          handleTapUp();
        },
      );
      return;
    }

    // Find out what is under the center-point of this card when it is dropped.
    final dropPiles = parent!.componentsAtPoint(position + size / 2).whereType<Pile>().toList();
    if (dropPiles.isNotEmpty) {
      if (dropPiles.first.canAcceptCard(this)) {
        // Found a Pile: move card(s) the rest of the way onto it.
        pile!.removeCard(this, MoveMethod.drag);
        if (dropPiles.first is TableauPile) {
          // Get TableauPile to handle positions, priorities and moves of cards.
          (dropPiles.first as TableauPile).dropCards(this, attachedCards);
          attachedCards.clear();
        } else {
          // Drop a single card onto a FoundationPile.
          final dropPosition = (dropPiles.first as FoundationPile).position;
          doMove(
            dropPosition,
            onComplete: () {
              dropPiles.first.acquireCard(this);
            },
          );
        }
        return;
      }
    }

    // Invalid drop (middle of nowhere, invalid pile or invalid card for pile).
    doMove(
      _whereCardStarted,
      onComplete: () {
        pile!.returnCard(this);
      },
    );
    if (attachedCards.isNotEmpty) {
      for (var card in attachedCards) {
        final offset = card.position - position;
        card.doMove(
          _whereCardStarted + offset,
          onComplete: () {
            pile!.returnCard(card);
          },
        );
      }
      attachedCards.clear();
    }
  }

  //#endregion

  //#region Card-Tapping

  // Tap a face-up card to make it auto-move and go out (if acceptable), but
  // if it is face-down and on the Stock Pile, pass the event to that pile.

  @override
  void onTapUp(TapUpEvent event) {
    // For trick CatTe, tapping attempts to play (if legal). Long term could differentiate fold.
    final r = world.game.rules;
    if (r is CatTeTrickRules) {
      // Tap toggles selection; no immediate play.
      r.selectCard(this);
      return;
    }
    if (r is EatRedsRules) {
      // Tap selects cards for manual pairing - don't fall through to handleTapUp
      // This prevents unwanted card movement during selection
      r.handleCardTap(this);
      return; // Always return here to prevent card movement
    }
    handleTapUp();
  }

  void handleTapUp() {
    // Can be called by onTapUp or after a very short (failed) drag-and-drop.
    // We need to be more user-friendly towards taps that include a short drag.
    if (pile?.canMoveCard(this, MoveMethod.tap) ?? false) {
      // Only Klondike auto-taps by suit index. Other rulesets may define different logic.
      if (world.game.rules is KlondikeRules) {
        final suitIndex = suit.value;
        if (world.foundations[suitIndex].canAcceptCard(this)) {
          pile!.removeCard(this, MoveMethod.tap);
          doMove(
            world.foundations[suitIndex].position,
            onComplete: () {
              world.foundations[suitIndex].acquireCard(this);
            },
          );
        }
      }
    } else if (pile is StockPile) {
      world.stock.handleTapUp(this);
    }
  }

  //#endRegion

  //#region Effects

  void doMove(
    Vector2 to, {
    double speed = 10.0,
    double start = 0.0,
    int startPriority = 100,
    Curve curve = Curves.easeOutQuad,
    VoidCallback? onComplete,
  }) {
    assert(speed > 0.0, 'Speed must be > 0 widths per second');
    final distance = (to - position).length;
    if (distance == 0) {
      // Nothing to animate; ensure final state & invoke callback immediately.
      onComplete?.call();
      return;
    }
    final dt = distance / (speed * size.x);
    // Guard against pathological extremely small distances that would create a 0 duration.
    if (dt <= 0) {
      onComplete?.call();
      return;
    }
    add(
      CardMoveEffect(
        to,
        EffectController(duration: dt, startDelay: start, curve: curve),
        transitPriority: startPriority,
        onComplete: () {
          onComplete?.call();
        },
      ),
    );
  }

  void doMoveAndFlip(
    Vector2 to, {
    double speed = 10.0,
    double start = 0.0,
    Curve curve = Curves.easeOutQuad,
    VoidCallback? whenDone,
  }) {
    assert(speed > 0.0, 'Speed must be > 0 widths per second');
    final distance = (to - position).length;
    if (distance == 0) {
      // Flip in place if already at destination.
      turnFaceUp(onComplete: whenDone);
      return;
    }
    final dt = distance / (speed * size.x);
    if (dt <= 0) {
      turnFaceUp(onComplete: whenDone);
      return;
    }
    priority = 100;
    add(
      MoveToEffect(
        to,
        EffectController(duration: dt, startDelay: start, curve: curve),
        onComplete: () {
          turnFaceUp(onComplete: whenDone);
        },
      ),
    );
  }

  void turnFaceUp({double time = 0.3, double start = 0.0, VoidCallback? onComplete}) {
    assert(!_isFaceUpView, 'Card must be face-down before turning face-up.');
    assert(time > 0.0, 'Time to turn card over must be > 0');
    assert(start >= 0.0, 'Start tim must be >= 0');
    _isAnimatedFlip = true;
    anchor = Anchor.topCenter;
    position += Vector2(width / 2, 0);
    priority = 100;
    add(
      /// ### Card Flip Animation
      ///
      /// The card flipping effect is implemented using [ScaleEffect.to], which scales the card's x-axis to create a smooth flip animation.
      /// The animation leverages an [EffectController] with a configurable start delay, ease-out curve, and split duration for both forward and reverse directions.
      /// - When the animation reaches its maximum scale, the card switches to its face-up view.
      /// - Upon reaching the minimum scale, animation flags are reset, the card state is updated to face-up, the card is repositioned, and its anchor is set.
      /// - The [onComplete] callback is invoked when the animation finishes.
      /// This effect provides a visually appealing card flip transition, enhancing the overall user experience in the game.
      /// Animates the card flipping effect using [ScaleEffect.to], scaling the card's x-axis to create a flip animation.
      /// The animation uses an [EffectController] with a start delay, ease-out curve, and split duration for forward and reverse.
      /// - On reaching the maximum scale, sets the card to face-up view.
      /// - On reaching the minimum scale, resets animation flags, updates card state to face-up, repositions the card, and sets the anchor.
      /// - Calls [onComplete] callback when the animation is finished.
      /// This effect is used to visually flip a card in the game, enhancing the user experience with smooth transitions.
      ScaleEffect.to(
        Vector2(scale.x / 100, scale.y),
        EffectController(
          startDelay: start,
          curve: Curves.easeOutSine,
          duration: time / 2,
          onMax: () {
            _isFaceUpView = true;
          },
          reverseDuration: time / 2,
          onMin: () {
            _isAnimatedFlip = false;
            _faceUp = true;
            anchor = Anchor.topLeft;
            position -= Vector2(width / 2, 0);
          },
        ),
        onComplete: () {
          onComplete?.call();
        },
      ),
    );
  }

  /// Set the selection state for EatReds card pairing
  void setSelected(bool selected) {
    if (_isSelected != selected) {
      _isSelected = selected;
      debugPrint('Card selection state changed to: $selected for ${rank.label} of ${suit.label}');
    }
  }

  /// Update visual highlighting based on selection and game rules
  void updateHighlighting() {
    // This method can be expanded to handle visual highlighting
    // For now, selection highlighting is handled in the render method
  }

  //#endregion
}

class CardMoveEffect extends MoveToEffect {
  CardMoveEffect(
    super.destination,
    super.controller, {
    super.onComplete,
    this.transitPriority = 100,
  });

  final int transitPriority;

  @override
  void onStart() {
    super.onStart(); // Flame connects MoveToEffect to EffectController.
    parent?.priority = transitPriority;
  }
}
