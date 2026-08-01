import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u8downloader/src/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('home screen shows servers tab', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('首页'), findsOneWidget);
    expect(find.text('服务器'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);

    await tester.tap(find.text('服务器'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('添加你的第一个服务器'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
