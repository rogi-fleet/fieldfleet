import 'package:flutter/material.dart';
import 'models_and_math.dart';

class CostEstimator {
  static void showEstimateDialog(BuildContext context, List<RoomPoint> points) {
    double floorArea = GeometryEngine.calculateArea(points);
    double perimeter = GeometryEngine.calculatePerimeter(points);
    const double wallHeight = 2.4; 
    double wallArea = perimeter * wallHeight; 
    
    final paintPriceCtrl = TextEditingController(text: "50"); 
    final floorPriceCtrl = TextEditingController(text: "30"); 

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            double paintCost = (double.tryParse(paintPriceCtrl.text) ?? 0) * (wallArea / 35); 
            double floorCost = (double.tryParse(floorPriceCtrl.text) ?? 0) * floorArea;
            double total = paintCost + floorCost;

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom, 
                left: 20, right: 20, top: 20
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Project Estimator", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  _row("Floor Area", "${floorArea.toStringAsFixed(2)} m²"),
                  _row("Wall Surface", "${wallArea.toStringAsFixed(2)} m²"),
                  const Divider(),
                  const Text("Paint Cost (per 10L)", style: TextStyle(fontWeight: FontWeight.bold)),
                  TextField(
                    controller: paintPriceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(prefixText: "\$"),
                    onChanged: (_) => setState((){}),
                  ),
                  Text("Est: \$${paintCost.toStringAsFixed(2)}", style: const TextStyle(color: Colors.green, fontSize: 16)),
                  const SizedBox(height: 10),
                  const Text("Flooring Cost (per m²)", style: TextStyle(fontWeight: FontWeight.bold)),
                  TextField(
                    controller: floorPriceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(prefixText: "\$"),
                    onChanged: (_) => setState((){}),
                  ),
                  Text("Est: \$${floorCost.toStringAsFixed(2)}", style: const TextStyle(color: Colors.green, fontSize: 16)),
                  const Divider(thickness: 2),
                  Center(
                    child: Text("TOTAL: \$${total.toStringAsFixed(2)}", 
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.blue)),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            );
          },
        );
      }
    );
  }

  static Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label), Text(value, style: const TextStyle(fontWeight: FontWeight.bold))],
      ),
    );
  }
}
