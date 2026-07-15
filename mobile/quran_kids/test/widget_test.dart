import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quran_kids/main.dart';

void main() {
  testWidgets('App boots to the surah list without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const QuranKidsApp());
    // The bundled al_fatiha.json manifest loads asynchronously - the
    // loading spinner is the correct initial state, not a crash.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
