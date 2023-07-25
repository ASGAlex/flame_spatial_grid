import 'dart:ui';

import 'package:flame/game.dart';
import 'package:flame_spatial_grid/flame_spatial_grid.dart';
import 'package:flame_spatial_grid_example/game.dart';
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
            return Material(
              type: MaterialType.transparency,
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: 5.0,
                  sigmaY: 5.0,
                ),
                child: StreamBuilder<LoadingProgressMessage<String>>(
                  stream: game.loadingStream,
                  builder: (context, snapshot) {
                    final progress = snapshot.data?.progress ?? 0;
                    return Center(
                      child: Text(
                        'Loading: $progress% ',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 24,
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          }
        },
      ),
    );
  }
}
