/// Marker library for the `room_scan` plugin.
///
/// The plugin exposes a `MethodChannel` and `EventChannel` consumed
/// directly by the host app at `lib/services/floorplan/scan/room_scan_channel.dart`.
/// There is no Dart-side facade here on purpose — keeping the public surface
/// at the channel level means the host app owns the controller and state
/// machine, and the plugin stays a thin wrapper around the native engines.
library room_scan;
