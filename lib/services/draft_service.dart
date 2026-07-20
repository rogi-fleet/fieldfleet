import 'package:shared_preferences/shared_preferences.dart';

/// Persists per-conversation draft messages locally
class DraftService {
  static const String _prefix = 'draft_';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<String?> getDraft(String conversationId) async {
    final prefs = await _prefs;
    return prefs.getString('$_prefix$conversationId');
  }

  Future<void> saveDraft(String conversationId, String content) async {
    final prefs = await _prefs;
    if (content.trim().isEmpty) {
      await prefs.remove('$_prefix$conversationId');
    } else {
      await prefs.setString('$_prefix$conversationId', content);
    }
  }

  Future<void> clearDraft(String conversationId) async {
    final prefs = await _prefs;
    await prefs.remove('$_prefix$conversationId');
  }
}
