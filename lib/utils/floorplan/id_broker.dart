import 'package:uuid/uuid.dart';

/// Issues unique IDs for floorplan scene entities.
///
/// IDs are short prefixed UUIDs (`v4`) — short enough to keep scene_json
/// compact, prefixed so a vertex/line/hole/area/item/annotation can be told
/// apart at a glance when debugging the JSON.
class IdBroker {
  IdBroker({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  String _next(String prefix) {
    final raw = _uuid.v4().replaceAll('-', '');
    return '${prefix}_${raw.substring(0, 16)}';
  }

  String layer() => _next('lyr');
  String vertex() => _next('vtx');
  String line() => _next('ln');
  String hole() => _next('hl');
  String area() => _next('ar');
  String item() => _next('it');
  String annotation() => _next('an');
  String scene() => _next('sc');
}
