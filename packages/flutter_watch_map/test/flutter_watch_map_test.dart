// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Host-side unit tests. The native map is replaced with a fake that records
// each call, so the controller and the widget are checked off-device; the
// MapKit view itself is exercised by the example on a watch Simulator.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_watch_map/flutter_watch_map.dart';
import 'package:flutter_watchos/flutter_watchos.dart';

class _FakeBackend implements WatchMapBackend {
  final List<String> calls = <String>[];
  List<double>? route;
  int? argb;
  int _next = 41;

  @override
  void registerViews() => calls.add('registerViews');
  @override
  int create() => _next++;
  @override
  void dispose(int map) => calls.add('dispose $map');
  @override
  void setRoute(int map, List<double> latLon, int argb, double width) {
    calls.add('setRoute $map ${latLon.length ~/ 2} $width');
    route = latLon;
    this.argb = argb;
  }

  @override
  void setShowsUser(int map, {required bool shows}) =>
      calls.add('showsUser $map $shows');
  @override
  void fitRoute(int map, double padding) => calls.add('fit $map $padding');
  @override
  void followUser(int map, {required bool followsHeading}) =>
      calls.add('follow $map $followsHeading');
  @override
  void setCamera(int map, double latitude, double longitude, double distance,
          double heading) =>
      calls.add('camera $map $latitude $longitude $distance $heading');
}

void main() {
  late _FakeBackend fake;

  setUp(() {
    fake = _FakeBackend();
    WatchMapPlugin.backendOverride = fake;
  });

  tearDown(() => WatchMapPlugin.backendOverride = null);

  test('registerWith registers the view type', () {
    WatchMapPlugin.registerWith();
    expect(fake.calls, <String>['registerViews']);
  });

  test('each controller gets its own native map', () {
    expect(WatchMapController().id, 41);
    expect(WatchMapController().id, 42);
  });

  test('the route crosses as latitude, longitude pairs with its style', () {
    WatchMapController().setRoute(
      const <WatchMapCoordinate>[
        WatchMapCoordinate(41.0, 29.0),
        WatchMapCoordinate(41.1, 29.1),
      ],
      color: const Color(0x80112233),
      width: 6,
    );
    expect(fake.calls.single, 'setRoute 41 2 6.0');
    expect(fake.route, <double>[41.0, 29.0, 41.1, 29.1]);
    expect(fake.argb, 0x80112233);
  });

  test('camera calls reach native', () {
    WatchMapController()
      ..showUserLocation(shows: true)
      ..fitRoute(padding: 20)
      ..followUser(followsHeading: true)
      ..setCamera(const WatchMapCoordinate(1, 2), distance: 300, heading: 90);
    expect(fake.calls, <String>[
      'showsUser 41 true',
      'fit 41 20.0',
      'follow 41 true',
      'camera 41 1.0 2.0 300.0 90.0',
    ]);
  });

  test('a disposed controller releases its map once and refuses calls', () {
    final WatchMapController c = WatchMapController()
      ..dispose()
      ..dispose();
    expect(fake.calls, <String>['dispose 41']);
    expect(() => c.fitRoute(), throwsStateError);
  });

  test('coordinates compare by value', () {
    expect(const WatchMapCoordinate(1, 2), const WatchMapCoordinate(1, 2));
    expect(const WatchMapCoordinate(1, 2).hashCode,
        const WatchMapCoordinate(1, 2).hashCode);
  });

  testWidgets('WatchMap is the platform view of its controller',
      (WidgetTester tester) async {
    final WatchMapController c = WatchMapController();
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: WatchMap(controller: c, interactive: false),
    ));
    final WatchPlatformView view =
        tester.widget<WatchPlatformView>(find.byType(WatchPlatformView));
    expect(view.viewType, 'flutter_watch_map');
    expect(view.creationParams, '41');
    expect(view.layer, WatchPlatformViewLayer.belowFlutter);
  });
}
