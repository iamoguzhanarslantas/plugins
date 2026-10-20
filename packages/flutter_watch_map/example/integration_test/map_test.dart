// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Against the real native map, on a watch Simulator: every `@_cdecl`
// function resolves, the view type is registered, and a map with a route
// builds and takes camera changes without error. What it draws is checked
// by eye on the example.
//
// Run with:
//   flutter-watchos drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/map_test.dart -d <watch-sim>

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_watch_map/flutter_watch_map.dart';
import 'package:flutter_watchos/flutter_watchos.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a map with a route builds and takes camera changes',
      (WidgetTester tester) async {
    expect(WatchPlatformView.isSupported, isTrue);
    final WatchMapController map = WatchMapController();
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: WatchMap(controller: map),
    ));
    map.setRoute(const <WatchMapCoordinate>[
      WatchMapCoordinate(41.0445, 28.9910),
      WatchMapCoordinate(41.0470, 28.9945),
      WatchMapCoordinate(41.0445, 28.9980),
    ]);
    map.fitRoute();
    await tester.pump(const Duration(milliseconds: 500));
    map.setCamera(const WatchMapCoordinate(41.0445, 28.9945),
        distance: 800, heading: 45);
    await tester.pump(const Duration(milliseconds: 500));
    map.followUser();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    map.dispose();
  });

  testWidgets('two maps live side by side', (WidgetTester tester) async {
    final WatchMapController a = WatchMapController();
    final WatchMapController b = WatchMapController();
    expect(a.id, isNot(b.id));
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Column(children: <Widget>[
        Expanded(child: WatchMap(controller: a)),
        Expanded(child: WatchMap(controller: b, interactive: false)),
      ]),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    a.dispose();
    b.dispose();
  });
}
