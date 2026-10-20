// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// A MapKit map on the Apple Watch, embedded in Flutter as a native SwiftUI
// platform view, with a route drawn on it.
//
// The functions below are implemented in Swift (`Views/flutter_watch_map_views.swift`,
// each `@_cdecl`), called from Dart over dart:ffi. Each map has a model the
// SwiftUI view observes; the calls change the model on the main thread, and
// the view redraws. This header only documents the C ABI.

#ifndef FLUTTER_WATCH_MAP_FFI_H
#define FLUTTER_WATCH_MAP_FFI_H

#include <stdint.h>

// Registers the "flutter_watch_map" view type with the flutter-watchos host.
void flutter_watch_map_register_views(void);

// Creates a map model and returns its id, which the Dart widget passes as the
// platform view's creation parameters.
int64_t flutter_watch_map_create(void);

// Forgets map `map`.
void flutter_watch_map_dispose(int64_t map);

// Replaces the route: `count` coordinates as latitude, longitude pairs in
// `coordinates` (2 × count doubles), drawn in `argb` at `width` points.
void flutter_watch_map_set_route(int64_t map, const double* coordinates,
                                 int32_t count, uint32_t argb, double width);

// Shows or hides the wearer's location.
void flutter_watch_map_set_shows_user(int64_t map, int32_t shows);

// Frames the whole route, with `padding` metres around it.
void flutter_watch_map_fit_route(int64_t map, double padding);

// Follows the wearer's location, turning with their heading when
// `follows_heading` is nonzero.
void flutter_watch_map_follow_user(int64_t map, int32_t follows_heading);

// Centres on a coordinate, from `distance` metres up, facing `heading`
// degrees.
void flutter_watch_map_set_camera(int64_t map, double latitude, double longitude,
                                  double distance, double heading);

#endif  // FLUTTER_WATCH_MAP_FFI_H
