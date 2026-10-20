// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_watch_map/flutter_watch_map.dart';

void main() => runApp(const MapExampleApp());

/// A watch app that draws a route that grows while it runs.
class MapExampleApp extends StatelessWidget {
  /// The example app.
  const MapExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: const MapPage(),
      );
}

/// A loop around a park, drawn a point at a time.
class MapPage extends StatefulWidget {
  /// The one page.
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final WatchMapController _map = WatchMapController();
  final List<WatchMapCoordinate> _route = <WatchMapCoordinate>[];
  Timer? _timer;
  bool _following = false;

  /// A point of a loop about 600 m across, around Maçka Park in Istanbul.
  static WatchMapCoordinate _loop(int i) {
    final double a = i / 40 * 2 * math.pi;
    return WatchMapCoordinate(
        41.0445 + 0.0027 * math.sin(a), 28.9945 + 0.0036 * math.cos(a));
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (Timer t) {
      if (_route.length > 40) {
        t.cancel();
        return;
      }
      _route.add(_loop(_route.length));
      _map.setRoute(_route);
      if (!_following) {
        _map.fitRoute();
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _map.dispose();
    super.dispose();
  }

  void _toggleFollow() {
    setState(() => _following = !_following);
    _map.showUserLocation(shows: _following);
    if (_following) {
      _map.followUser();
    } else {
      _map.fitRoute();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(
          children: <Widget>[
            Positioned.fill(child: WatchMap(controller: _map)),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: FilledButton.tonal(
                onPressed: _toggleFollow,
                child: Text(_following
                    ? 'Fit route'
                    : '${_route.length} points · Follow me'),
              ),
            ),
          ],
        ),
      );
}
