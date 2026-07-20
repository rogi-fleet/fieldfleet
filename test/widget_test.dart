// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:taskfleet_ops/main.dart';

GoRouter _buildTestRouter() {
  return GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Directionality(
          textDirection: TextDirection.ltr,
          child: Text('FieldFleet test shell'),
        ),
      ),
    ],
  );
}

void main() {
  setUpAll(() async {
    // Providers built by MyApp subscribe to Supabase auth state, so the
    // singleton must exist before the first pump. Local dummy values only;
    // no request is made during a widget test.
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  testWidgets('MyApp boots with injected router', (WidgetTester tester) async {
    await tester.pumpWidget(MyApp(routerFactory: _buildTestRouter));

    expect(find.text('FieldFleet test shell'), findsOneWidget);
  });
}
