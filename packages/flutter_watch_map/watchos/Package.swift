// swift-tools-version:5.9
// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// FFI plugin manifest. The flutter-watchos CLI discovers the plugin through
// this file, compiles `Views/*.swift` (the SwiftUI platform view and its
// `@_cdecl` functions) into the watch binary, and links the frameworks
// declared below.
import PackageDescription

let package = Package(
    name: "flutter_watch_map",
    platforms: [
        .watchOS("10.0"),
    ],
    products: [
        .library(name: "flutter-watch-map", targets: ["flutter_watch_map"]),
    ],
    targets: [
        .target(
            name: "flutter_watch_map",
            path: "Classes",
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath("."),
            ],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("MapKit"),
                .linkedFramework("CoreLocation"),
            ]
        ),
    ]
)
