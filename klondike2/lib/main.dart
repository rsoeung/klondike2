import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'klondike_game.dart';

void main() {
  debugPrint('App started');
  runApp(const KlondikeApp());
}

class KlondikeApp extends StatelessWidget {
  const KlondikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Klondike Card Games',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const GameScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final KlondikeGame game;

  @override
  void initState() {
    super.initState();
    game = KlondikeGame();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: GameWidget.controlled(gameFactory: () => game));
  }
}
