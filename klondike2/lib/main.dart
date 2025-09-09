
import 'package:flutter/foundation.dart';
import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';

import 'klondike_game.dart';

void main() {
  debugPrint('App started');
  final game = KlondikeGame();
  runApp(GameWidget(game: game));
}