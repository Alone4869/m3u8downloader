import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u8downloader/src/glass_surface.dart';

void main() {
  testWidgets('app surface renders its child over the shared backdrop', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppBackdrop(
          child: Center(
            child: AppSurface(
              padding: EdgeInsets.all(16),
              child: Text('surface content'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('surface content'), findsOneWidget);
    expect(find.byType(Material), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
