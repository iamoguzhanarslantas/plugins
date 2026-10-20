// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// A MapKit map for Flutter apps on the Apple Watch, with a route drawn on
/// it: a native SwiftUI platform view, driven over dart:ffi.
///
/// Create a [WatchMapController], give it to a [WatchMap], and update the
/// route as it grows.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_watchos/flutter_watchos.dart';

import 'src/backend.dart';

export 'src/backend.dart' show WatchMapBackend;

/// A point on the map.
@immutable
class WatchMapCoordinate {
  /// A point at [latitude] and [longitude], in degrees.
  const WatchMapCoordinate(this.latitude, this.longitude);

  /// Latitude, in degrees.
  final double latitude;

  /// Longitude, in degrees.
  final double longitude;

  @override
  bool operator ==(Object other) =>
      other is WatchMapCoordinate &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

/// Drives one [WatchMap]: its route, the wearer's location, and the camera.
///
/// Every call returns at once; the map redraws on the next frame of the
/// native view.
class WatchMapController {
  /// A controller with a new native map.
  WatchMapController() : id = WatchMapPlugin._b.create();

  /// The native map's id, which [WatchMap] hands to the platform view.
  final int id;

  bool _disposed = false;

  WatchMapBackend get _b => WatchMapPlugin._b;

  void _check() {
    if (_disposed) {
      throw StateError('This WatchMapController has been disposed.');
    }
  }

  /// Draws [points] as the route, in [color] and [width] points wide,
  /// replacing the route drawn before. A green dot marks its start.
  void setRoute(
    List<WatchMapCoordinate> points, {
    Color color = const Color(0xFFFF9500),
    double width = 4,
  }) {
    _check();
    _b.setRoute(
      id,
      <double>[
        for (final WatchMapCoordinate p in points) ...<double>[
          p.latitude,
          p.longitude,
        ],
      ],
      color.toARGB32(),
      width,
    );
  }

  /// Shows or hides the wearer's location. It needs when-in-use location
  /// access, which the app asks for itself.
  void showUserLocation({required bool shows}) {
    _check();
    _b.setShowsUser(id, shows: shows);
  }

  /// Frames the whole route, with [padding] metres around it.
  void fitRoute({double padding = 50}) {
    _check();
    _b.fitRoute(id, padding);
  }

  /// Follows the wearer, turning with their heading when [followsHeading].
  void followUser({bool followsHeading = false}) {
    _check();
    _b.followUser(id, followsHeading: followsHeading);
  }

  /// Centres on [center], seen from [distance] metres up, facing [heading]
  /// degrees from north.
  void setCamera(
    WatchMapCoordinate center, {
    double distance = 1000,
    double heading = 0,
  }) {
    _check();
    _b.setCamera(id, center.latitude, center.longitude, distance, heading);
  }

  /// Releases the native map. The controller cannot be used afterwards.
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _b.dispose(id);
  }
}

/// The map of a [WatchMapController], as a native MapKit view.
class WatchMap extends StatelessWidget {
  /// A map driven by [controller]. With [interactive], the map takes the
  /// touches over it (pan, zoom); without, they stay with Flutter.
  const WatchMap({
    super.key,
    required this.controller,
    this.interactive = true,
  });

  /// What the map shows.
  final WatchMapController controller;

  /// Whether the map, rather than Flutter, handles touches over it.
  final bool interactive;

  @override
  Widget build(BuildContext context) => WatchPlatformView(
        viewType: 'flutter_watch_map',
        creationParams: '${controller.id}',
        layer: interactive
            ? WatchPlatformViewLayer.aboveFlutter
            : WatchPlatformViewLayer.belowFlutter,
      );
}

/// The plugin registration, and the test hook.
abstract final class WatchMapPlugin {
  /// Test hook: set before first use to replace the native backend.
  @visibleForTesting
  static WatchMapBackend? backendOverride;

  static WatchMapBackend? _backend;

  static WatchMapBackend get _b =>
      backendOverride ?? (_backend ??= FfiWatchMapBackend());

  /// Registers the "flutter_watch_map" view type with the host. Called by
  /// the plugin registrant.
  static void registerWith() => _b.registerViews();
}
