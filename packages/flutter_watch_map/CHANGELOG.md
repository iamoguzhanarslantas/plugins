## 0.0.1

First version, staged: checked on the watchOS 27.0 Simulator, not yet on a
physical watch.

* `WatchMap`: a SwiftUI MapKit `Map` embedded as a native platform view.
* `WatchMapController`: the route as a `MapPolyline` with a start marker,
  framing the route, following the wearer, a camera on a point, and the
  wearer's location.
* Each map has a model its SwiftUI view observes; the `@_cdecl` functions
  copy what Dart passes and change the model on the main queue.
