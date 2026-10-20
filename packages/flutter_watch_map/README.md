# flutter_watch_map

A MapKit map for Flutter apps on Apple Watch, with a route drawn on it: a
native SwiftUI `Map` embedded as a platform view, driven over dart:ffi. For
apps built with [flutter-watchos](https://github.com/flutterwatch/flutter-watchos).

This is a first-party package, not a port: there is no Google Maps SDK for
watchOS, and a MapKit backend would not honestly implement
`google_maps_flutter`'s interface.

## Installation

```yaml
dependencies:
  flutter_watch_map: ^0.0.1
```

## Usage

```dart
final WatchMapController map = WatchMapController();

// In a build method:
WatchMap(controller: map);

// As the route grows:
map.setRoute(points, color: const Color(0xFFFF9500), width: 4);
map.fitRoute();

// Or follow the wearer:
map.showUserLocation(shows: true);
map.followUser(followsHeading: true);

// When done:
map.dispose();
```

## What it does

| Member | What it does |
|---|---|
| `WatchMap(controller:, interactive:)` | The map. With `interactive` (the default) the map takes the touches over it; without, Flutter does |
| `setRoute(points, {color, width})` | Draws the route as a `MapPolyline`, replacing the one before; a green dot marks its start |
| `fitRoute({padding})` | Frames the whole route |
| `followUser({followsHeading})` | Follows the wearer's location |
| `setCamera(center, {distance, heading})` | Centres on a point |
| `showUserLocation(shows:)` | Shows or hides the wearer's location; the app asks for location access itself (`NSLocationWhenInUseUsageDescription`) |
| `dispose()` | Releases the native map |

Flutter content painted after the map draws over it, so buttons and
readouts can sit on top, as in the example.

## Limits worth knowing

- Map tiles load over the network: the watch needs Wi-Fi, a cellular
  connection or its iPhone nearby.
- Golden tests and scene snapshots do not capture the native map's pixels.
- A route is redrawn whole on each `setRoute`; thousands of points are fine,
  but call it as often as the route changes, not every frame.
- On an app created by an older flutter-watchos, platform views do not
  render (`WatchPlatformView.isSupported`).

## Status

| Aspect | Result |
|---|---|
| Host unit tests (`flutter test`) | ✅ pass (native backend faked) |
| Integration test (`example/integration_test`) | ✅ passes on the watchOS 27.0 Simulator: maps build, take a route and camera changes, and two live side by side |
| Example on the Simulator | ✅ a 41-point route drawn and framed, with a Flutter button over the map |
| Physical watch | not yet checked: the wearer's location, following, and the Digital Crown on the map need a device |

## License

The FlutterWatch Authors under a BSD-3-Clause license. See `LICENSE` for the full text.
