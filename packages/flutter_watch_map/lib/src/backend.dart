// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// The C ABI of `watchos/Classes/flutter_watch_map_ffi.h` (implemented in
// Swift with `@_cdecl`), behind an interface so host tests can substitute a
// fake.

import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// The native half of the map: one call per exported function.
abstract class WatchMapBackend {
  /// Registers the platform view type.
  void registerViews();

  /// Creates a map model and returns its id.
  int create();

  /// Forgets map [map].
  void dispose(int map);

  /// Replaces map [map]'s route with [latLon] (latitude, longitude pairs).
  void setRoute(int map, List<double> latLon, int argb, double width);

  /// Shows or hides the wearer's location.
  void setShowsUser(int map, {required bool shows});

  /// Frames the route with [padding] metres around it.
  void fitRoute(int map, double padding);

  /// Follows the wearer's location.
  void followUser(int map, {required bool followsHeading});

  /// Centres on a coordinate.
  void setCamera(int map, double latitude, double longitude, double distance,
      double heading);
}

/// [WatchMapBackend] over the exported functions.
class FfiWatchMapBackend implements WatchMapBackend {
  /// Resolves the symbols from the process lazily, on first use.
  FfiWatchMapBackend() : _lib = DynamicLibrary.process();

  final DynamicLibrary _lib;

  late final void Function() _registerViews =
      _lib.lookupFunction<Void Function(), void Function()>(
          'flutter_watch_map_register_views');
  late final int Function() _create =
      _lib.lookupFunction<Int64 Function(), int Function()>(
          'flutter_watch_map_create');
  late final void Function(int) _dispose =
      _lib.lookupFunction<Void Function(Int64), void Function(int)>(
          'flutter_watch_map_dispose');
  late final void Function(int, Pointer<Double>, int, int, double) _setRoute =
      _lib.lookupFunction<
          Void Function(Int64, Pointer<Double>, Int32, Uint32, Double),
          void Function(int, Pointer<Double>, int, int,
              double)>('flutter_watch_map_set_route');
  late final void Function(int, int) _setShowsUser =
      _lib.lookupFunction<Void Function(Int64, Int32), void Function(int, int)>(
          'flutter_watch_map_set_shows_user');
  late final void Function(int, double) _fitRoute = _lib.lookupFunction<
      Void Function(Int64, Double),
      void Function(int, double)>('flutter_watch_map_fit_route');
  late final void Function(int, int) _followUser =
      _lib.lookupFunction<Void Function(Int64, Int32), void Function(int, int)>(
          'flutter_watch_map_follow_user');
  late final void Function(int, double, double, double, double) _setCamera =
      _lib.lookupFunction<
          Void Function(Int64, Double, Double, Double, Double),
          void Function(int, double, double, double,
              double)>('flutter_watch_map_set_camera');

  @override
  void registerViews() => _registerViews();
  @override
  int create() => _create();
  @override
  void dispose(int map) => _dispose(map);

  @override
  void setRoute(int map, List<double> latLon, int argb, double width) =>
      using((Arena arena) {
        final Pointer<Double> buffer =
            arena<Double>(latLon.isEmpty ? 1 : latLon.length);
        buffer.asTypedList(latLon.length).setAll(0, latLon);
        _setRoute(map, buffer, latLon.length ~/ 2, argb, width);
      });

  @override
  void setShowsUser(int map, {required bool shows}) =>
      _setShowsUser(map, shows ? 1 : 0);
  @override
  void fitRoute(int map, double padding) => _fitRoute(map, padding);
  @override
  void followUser(int map, {required bool followsHeading}) =>
      _followUser(map, followsHeading ? 1 : 0);
  @override
  void setCamera(int map, double latitude, double longitude, double distance,
          double heading) =>
      _setCamera(map, latitude, longitude, distance, heading);
}
