// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// The plugin's native platform view: a SwiftUI MapKit `Map` with a route
// polyline, placed where the Dart side puts its `WatchPlatformView`. The
// flutter-watchos CLI compiles this file into the app. Every function here
// with `@_cdecl` is called from Dart over dart:ffi (see
// Classes/flutter_watch_map_ffi.h); FFI calls arrive on the Flutter UI thread,
// so each one copies what it was given and changes the model on the main
// queue, which also keeps create, update and dispose in order.

import CoreLocation
import MapKit
import SwiftUI

/// What one map shows. Main thread only.
final class FlutterWatchMapModel: ObservableObject {
    @Published var route: [CLLocationCoordinate2D] = []
    @Published var routeColor = Color.orange
    @Published var routeWidth: CGFloat = 4
    @Published var showsUser = false
    @Published var position: MapCameraPosition = .automatic
}

/// Map models by id. Main thread only.
private var models: [Int64: FlutterWatchMapModel] = [:]

private let idLock = NSLock()
private var nextId: Int64 = 1

private struct FlutterWatchMapView: View {
    @ObservedObject var model: FlutterWatchMapModel

    var body: some View {
        Map(position: $model.position) {
            if model.route.count > 1 {
                MapPolyline(coordinates: model.route)
                    .stroke(model.routeColor, lineWidth: model.routeWidth)
            }
            if let start = model.route.first {
                Annotation("", coordinate: start) {
                    Circle().fill(.green).frame(width: 8, height: 8)
                }
            }
            if model.showsUser {
                UserAnnotation()
            }
        }
    }
}

private func onMain(_ block: @escaping () -> Void) {
    DispatchQueue.main.async(execute: block)
}

private func color(_ argb: UInt32) -> Color {
    Color(
        .sRGB,
        red: Double((argb >> 16) & 0xFF) / 255,
        green: Double((argb >> 8) & 0xFF) / 255,
        blue: Double(argb & 0xFF) / 255,
        opacity: Double((argb >> 24) & 0xFF) / 255
    )
}

/// The smallest map rect holding every point of `route`, grown by `padding`
/// metres on each side.
private func rect(around route: [CLLocationCoordinate2D], padding: Double) -> MKMapRect {
    var rect = MKMapRect.null
    for coordinate in route {
        let point = MKMapPoint(coordinate)
        rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
    }
    let grow = padding * MKMapPointsPerMeterAtLatitude(route.first?.latitude ?? 0)
    return rect.insetBy(dx: -grow, dy: -grow)
}

@_cdecl("flutter_watch_map_register_views")
public func flutterWatchMapRegisterViews() {
    FlutterWatchOSPluginViews.register("flutter_watch_map") { params in
        // creationParams is the map id in decimal.
        guard let id = Int64(params), let model = models[id] else {
            return AnyView(EmptyView())
        }
        return AnyView(FlutterWatchMapView(model: model))
    }
}

@_cdecl("flutter_watch_map_create")
public func flutterWatchMapCreate() -> Int64 {
    idLock.lock()
    let id = nextId
    nextId += 1
    idLock.unlock()
    // Queued before the widget that shows it can be built.
    onMain { models[id] = FlutterWatchMapModel() }
    return id
}

@_cdecl("flutter_watch_map_dispose")
public func flutterWatchMapDispose(_ map: Int64) {
    onMain { models[map] = nil }
}

@_cdecl("flutter_watch_map_set_route")
public func flutterWatchMapSetRoute(
    _ map: Int64,
    _ coordinates: UnsafePointer<Double>?,
    _ count: Int32,
    _ argb: UInt32,
    _ width: Double
) {
    // Copied now: Dart releases the buffer as soon as this returns.
    var route: [CLLocationCoordinate2D] = []
    if let coordinates, count > 0 {
        route.reserveCapacity(Int(count))
        for i in 0..<Int(count) {
            route.append(CLLocationCoordinate2D(
                latitude: coordinates[2 * i], longitude: coordinates[2 * i + 1]))
        }
    }
    onMain {
        guard let model = models[map] else { return }
        model.route = route
        model.routeColor = color(argb)
        model.routeWidth = CGFloat(width)
    }
}

@_cdecl("flutter_watch_map_set_shows_user")
public func flutterWatchMapSetShowsUser(_ map: Int64, _ shows: Int32) {
    onMain { models[map]?.showsUser = shows != 0 }
}

@_cdecl("flutter_watch_map_fit_route")
public func flutterWatchMapFitRoute(_ map: Int64, _ padding: Double) {
    onMain {
        guard let model = models[map], !model.route.isEmpty else { return }
        model.position = .rect(rect(around: model.route, padding: padding))
    }
}

@_cdecl("flutter_watch_map_follow_user")
public func flutterWatchMapFollowUser(_ map: Int64, _ followsHeading: Int32) {
    onMain {
        models[map]?.position = .userLocation(
            followsHeading: followsHeading != 0, fallback: .automatic)
    }
}

@_cdecl("flutter_watch_map_set_camera")
public func flutterWatchMapSetCamera(
    _ map: Int64,
    _ latitude: Double,
    _ longitude: Double,
    _ distance: Double,
    _ heading: Double
) {
    onMain {
        models[map]?.position = .camera(MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            distance: distance,
            heading: heading,
            pitch: 0))
    }
}
