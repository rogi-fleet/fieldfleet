import '../../../models/floorplan/item.dart';
import '../../../models/floorplan/scene.dart';
import '../../../utils/floorplan/id_broker.dart';
import '../catalog.dart';

/// Static operations on [Item]s — placeable point elements with rotation.
/// Sizing comes from the [Catalog] entry for the prototype.
class ItemOps {
  const ItemOps._();

  static ({Scene scene, String itemId})? place({
    required Scene scene,
    required IdBroker ids,
    required Catalog catalog,
    required String prototype,
    required double x,
    required double y,
    double rotation = 0,
  }) {
    final spec = catalog.get(prototype);
    if (spec == null) return null;
    final id = ids.item();
    final item = Item(
      id: id,
      prototype: prototype,
      x: x,
      y: y,
      rotation: rotation,
      width: spec.defaultWidth,
      height: spec.defaultHeight,
    );
    final layer = scene.selectedLayer;
    final items = Map<String, Item>.from(layer.items);
    items[id] = item;
    return (
      scene: scene.withSelectedLayer(layer.copyWith(items: items)),
      itemId: id,
    );
  }

  static Scene moveTo({
    required Scene scene,
    required String itemId,
    required double x,
    required double y,
  }) {
    final layer = scene.selectedLayer;
    final item = layer.items[itemId];
    if (item == null) return scene;
    final items = Map<String, Item>.from(layer.items);
    items[itemId] = item.copyWith(x: x, y: y);
    return scene.withSelectedLayer(layer.copyWith(items: items));
  }

  static Scene resize({
    required Scene scene,
    required String itemId,
    double? width,
    double? height,
  }) {
    final layer = scene.selectedLayer;
    final item = layer.items[itemId];
    if (item == null) return scene;
    final items = Map<String, Item>.from(layer.items);
    items[itemId] = item.copyWith(width: width, height: height);
    return scene.withSelectedLayer(layer.copyWith(items: items));
  }

  static Scene rotateTo({
    required Scene scene,
    required String itemId,
    required double rotation,
  }) {
    final layer = scene.selectedLayer;
    final item = layer.items[itemId];
    if (item == null) return scene;
    final items = Map<String, Item>.from(layer.items);
    items[itemId] = item.copyWith(rotation: rotation);
    return scene.withSelectedLayer(layer.copyWith(items: items));
  }

  static Scene delete({required Scene scene, required String itemId}) {
    final layer = scene.selectedLayer;
    if (!layer.items.containsKey(itemId)) return scene;
    final items = Map<String, Item>.from(layer.items)..remove(itemId);
    return scene.withSelectedLayer(layer.copyWith(items: items));
  }
}
