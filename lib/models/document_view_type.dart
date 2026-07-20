import 'package:shared_preferences/shared_preferences.dart';

enum DocumentViewType { card, table }

const _kPrefKey = 'documents_view_type';

Future<DocumentViewType> loadDocumentViewPreference() async {
  final prefs = await SharedPreferences.getInstance();
  final value = prefs.getString(_kPrefKey);
  if (value == 'table') return DocumentViewType.table;
  return DocumentViewType.card;
}

Future<void> saveDocumentViewPreference(DocumentViewType type) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kPrefKey, type.name);
}
