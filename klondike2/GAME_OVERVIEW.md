# Klondike Solitaire Flutter/Flame Game Overview

## Project Structure

- **main.dart**: Entry point. Initializes the game and runs the Flame `GameWidget`.
- **klondike_game.dart**: Main game controller. Holds constants, game state, and instantiates the world.
- **klondike_world.dart**: Main game scene. Manages piles, cards, game logic, user actions, and win condition.
- **components/**: Contains game components like piles (`tableau_pile.dart`, `foundation_pile.dart`, etc.), cards, and buttons.
- **assets/images/klondike-sprites.png**: Card sprite image used for rendering cards.
- **pubspec.yaml**: Registers asset paths and dependencies (including Flame).

## How the Game Works

1. **App Startup**
   - `main.dart` creates a `KlondikeGame` instance and runs it inside a `GameWidget`.

2. **Game Initialization**
   - `KlondikeGame` sets up constants and state, then creates a `KlondikeWorld`.
   - `KlondikeWorld` loads the card sprite, sets up piles and cards, and arranges them on the screen.

3. **User Interaction**
   - Buttons allow actions: new deal, same deal, change draw mode, and "have fun" (win instantly).
   - Drag/tap gestures move cards between piles according to Klondike rules.

4. **Game Logic**
   - Cards are dealt and moved according to Klondike Solitaire rules.
   - Piles manage their own cards and logic for accepting/moving cards.
   - The game checks for win condition (all foundation piles complete).

5. **Debugging**
   - `debugPrint` statements are placed throughout the code to trace game flow, user actions, and state changes.

## Key Files Explained

### main.dart
- Entry point for the app.
- Runs the game using Flame's `GameWidget`.

### klondike_game.dart
- Holds game-wide constants (card sizes, gaps, etc.).
- Maintains current draw mode, seed, and action.
- Instantiates the main game world.

### klondike_world.dart
- Loads assets and sets up piles/cards.
- Handles user actions and game logic.
- Deals cards and checks for win condition.
- Uses debug prints for tracing.

### components/
- Defines game components:
  - **Piles**: Manage cards and rules for moving/accepting cards.
  - **Cards**: Know their rank, suit, and face status.
  - **Buttons**: Trigger game actions.
- Uses Flame's `PositionComponent` for layout and rendering.

### Asset Management
- Card images are loaded from `assets/images/klondike-sprites.png`.
- Asset paths are registered in `pubspec.yaml` under `flutter/assets`.

## Components Folder Breakdown

### card.dart
- **Purpose:** Represents a single playing card.
- **Details:**
  - Stores rank, suit, and reference to its pile.
  - Handles whether it is face up/down, and if it is a base card (used for empty pile logic).
  - Uses Flame’s `PositionComponent` and mixins for drag/tap event handling.
  - Manages card animation, flipping, and interaction logic.

### flat_button.dart
- **Purpose:** Custom button component for game actions.
- **Details:**
  - Extends Flame’s `ButtonComponent`.
  - Renders a styled button with text.
  - Handles button press/release events.
  - Uses a custom `ButtonBackground` for visual appearance.

### foundation_pile.dart
- **Purpose:** Represents a foundation pile (where cards are stacked Ace to King by suit).
- **Details:**
  - Stores the suit and a list of cards.
  - Implements logic for accepting/moving cards according to Klondike rules (must be next rank and same suit).
  - Checks for completion (pile is full).
  - Calls a win-check callback when completed.

### stock_pile.dart
- **Purpose:** Represents the stock pile (draw pile).
- **Details:**
  - Stores a list of face-down cards.
  - Cards cannot be moved or accepted from other piles.
  - Handles logic for drawing cards to the waste pile.
  - Uses Flame’s `HasGameReference` for game-wide access.

### tableau_pile.dart
- **Purpose:** Represents a tableau pile (main play area columns).
- **Details:**
  - Stores a list of cards and manages their layout (fanned out).
  - Implements logic for moving/accepting cards (alternating colors, descending rank).
  - Handles flipping the top card when needed.
  - Uses debug prints for tracing actions and state changes.

### waste_pile.dart
- **Purpose:** Represents the waste pile (where drawn cards go).
- **Details:**
  - Stores a list of face-up cards.
  - Only the top card can be moved.
  - Cards cannot be accepted from other piles.
  - Manages layout and card return logic.
  - Uses Flame’s `HasGameReference` for game-wide access.

## Game Flow Summary

1. App starts, `KlondikeGame` and `KlondikeWorld` are initialized.
2. Card sprite is loaded, piles and cards are created and positioned.
3. User interacts via buttons or drag/tap gestures.
4. Game logic updates piles and cards, checks for win condition.
5. Debug prints help trace what’s happening at each step.

---

If you want a deeper explanation of any specific file, class, or function, just ask!

## Create Your Own Rules

You can swap out Klondike for your own card game rules. The codebase exposes a `GameRules` interface and two implementations:

- `KlondikeRules` (current game)
- `CustomRules` (template to start from)

### Where to look

- Interface: `lib/rules/game_rules.dart`
- Klondike implementation: `lib/rules/klondike_rules.dart`
- Template: `lib/rules/custom_rules_template.dart`
- Wiring: `lib/klondike_game.dart` (buildRules/RulesVariant) and `lib/klondike_world.dart` (uses rules for layout/deal/win)

### Quick start

1) Duplicate the template

- Copy `lib/rules/custom_rules_template.dart` to a new file (e.g., `lib/rules/my_rules.dart`).
- Rename the class (e.g., `class MyRules implements GameRules`).

2) Implement your rules

- Layout: Implement `setupPiles()` to position piles and register a `checkWin` callback.
- Deal: Implement `deal()` to move cards from `deck` to piles (animations optional).
- Play area: Set `playAreaSize` to fit your layout.
- Moves: Override `canDropOnTableau`, `canDropOnFoundation`, `canDrawFromStock` (and others if you add them) to enforce your game’s rules.
- Win condition: Implement `checkWin()` to return true when the game is won.
- Base card: Set `usesBaseCard` true/false depending on whether you need a placeholder card.

3) Wire it up

- Add a new case to `RulesVariant` and `buildRules()` in `lib/klondike_game.dart` if you want a distinct option beyond the provided `custom`.
- Or, for quick iteration, replace the existing `CustomRules` in `buildRules()` with your rules class.

4) Switch rules at runtime

- A "Rules" button appears to the left of the top action buttons.
- Tapping it toggles between Klondike and Custom. The world rebuilds automatically via `game.rebuildWorld()`.

### Tips

- Keep your `setupPiles()` consistent with your `playAreaSize` so the camera centers correctly.
- Use `debugPrint` generously while developing rules to trace behavior.
- If a pile also has built-in validation, your `canDrop...` hooks run first. You can allow or deny early, and the pile’s default logic will still apply if you return `null` or keep permissive behavior.
- For alternative draw counts (e.g., draw 1 vs. 3), see `klondikeDraw` in `KlondikeGame` and adjust your rules/piles accordingly.

