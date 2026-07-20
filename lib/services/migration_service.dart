/// Legacy Firestore migration service retained as an inert stub.
class MigrationService {
  Future<void> migrateUser(String userId) async {
    return;
  }

  Future<Map<String, int>> migrateAllUsers() async {
    return {'success': 0, 'failed': 0};
  }
}
