import 'package:cluisterizer_test/game.dart';
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
      home: GameWidget.controlled(
          gameFactory: SpatialGridExample.new,
          overlayBuilderMap: {
            'loading': (BuildContext ctx, SpatialGridExample game) {
              return const Material(
                  type: MaterialType.transparency,
                  child: Center(
                      child: Text(
                    'Loading...',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 24),
                  )));
            }
          }),
    );
  }
}
