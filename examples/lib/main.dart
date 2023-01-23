import 'package:cluisterizer_test/game.dart';
import 'package:cluisterizer_test/minimal_game.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';


void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.purple,
      ),
      home: const GameWidget.controlled(gameFactory: SpatialGridExample.new),
    );
  }
}
