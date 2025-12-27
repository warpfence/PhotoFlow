// PhotoFlow widget test.
//
// Basic smoke test to verify the app builds correctly.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:photoflow/main.dart';
import 'package:photoflow/features/media_scanner/media_scanner_provider.dart';

void main() {
  testWidgets('App builds and shows home screen', (WidgetTester tester) async {
    // SharedPreferences mock 설정
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    // Build our app and trigger a frame.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const PhotoFlowApp(),
      ),
    );

    // 앱이 빌드되고 홈 화면이 표시되는지 확인
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
