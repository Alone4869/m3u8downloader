import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u8downloader/src/glass_surface.dart';

void main() {
  testWidgets('glass surface renders its child over a blurred backdrop', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: GlassBackdrop(
          child: Center(
            child: GlassSurface(
              padding: EdgeInsets.all(16),
              child: Text('glass content'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('glass content'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
