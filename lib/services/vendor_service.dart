import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/vendor.dart';

class VendorService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'vendors';

  // Get all vendors for a workspace
  Stream<List<Vendor>> getVendors(String workspaceId) {
    return _firestore
        .collection(_collection)
        .where('workspaceId', isEqualTo: workspaceId)
        .where('isActive', isEqualTo: true)
        .orderBy('companyName')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Vendor.fromJson(doc.data(), doc.id))
              .toList(),
        );
  }

  // Get single vendor
  Future<Vendor?> getVendor(String vendorId) async {
    final doc = await _firestore.collection(_collection).doc(vendorId).get();
    if (!doc.exists) return null;
    return Vendor.fromJson(doc.data()!, doc.id);
  }

  // Create vendor
  Future<String> createVendor(Vendor vendor) async {
    if (!vendor.validate()) {
      throw Exception('Invalid vendor data');
    }

    final docRef = await _firestore
        .collection(_collection)
        .add(vendor.toJson());
    return docRef.id;
  }

  // Update vendor
  Future<void> updateVendor(Vendor vendor) async {
    if (!vendor.validate()) {
      throw Exception('Invalid vendor data');
    }

    await _firestore
        .collection(_collection)
        .doc(vendor.id)
        .update(vendor.toJson());
  }

  // Delete vendor
  Future<void> deleteVendor(String vendorId) async {
    // TODO: Check for project associations before deleting
    await _firestore.collection(_collection).doc(vendorId).delete();
  }

  // Archive vendor (soft delete)
  Future<void> archiveVendor(String vendorId) async {
    await _firestore.collection(_collection).doc(vendorId).update({
      'isActive': false,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  // Restore vendor
  Future<void> restoreVendor(String vendorId) async {
    await _firestore.collection(_collection).doc(vendorId).update({
      'isActive': true,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  // Filter by category
  Stream<List<Vendor>> getVendorsByCategory(
    String workspaceId,
    String category,
  ) {
    return _firestore
        .collection(_collection)
        .where('workspaceId', isEqualTo: workspaceId)
        .where('isActive', isEqualTo: true)
        .where('category', isEqualTo: category)
        .orderBy('companyName')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Vendor.fromJson(doc.data(), doc.id))
              .toList(),
        );
  }

  // Filter by type
  Stream<List<Vendor>> getVendorsByType(String workspaceId, String type) {
    return _firestore
        .collection(_collection)
        .where('workspaceId', isEqualTo: workspaceId)
        .where('isActive', isEqualTo: true)
        .where('vendorType', isEqualTo: type)
        .orderBy('companyName')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Vendor.fromJson(doc.data(), doc.id))
              .toList(),
        );
  }

  // Get preferred vendors
  Stream<List<Vendor>> getPreferredVendors(String workspaceId) {
    return _firestore
        .collection(_collection)
        .where('workspaceId', isEqualTo: workspaceId)
        .where('isActive', isEqualTo: true)
        .where('isPreferred', isEqualTo: true)
        .orderBy('companyName')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Vendor.fromJson(doc.data(), doc.id))
              .toList(),
        );
  }

  // Get archived vendors
  Stream<List<Vendor>> getArchivedVendors(String workspaceId) {
    return _firestore
        .collection(_collection)
        .where('workspaceId', isEqualTo: workspaceId)
        .where('isActive', isEqualTo: false)
        .orderBy('companyName')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Vendor.fromJson(doc.data(), doc.id))
              .toList(),
        );
  }
}
