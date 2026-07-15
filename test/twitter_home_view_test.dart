import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u8downloader/src/twitter_home_view.dart';

void main() {
  testWidgets('Twitter home shows URL input and usage guide', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: TwitterHomeView()));

    expect(find.text('X 视频下载'), findsOneWidget);
    expect(find.text('Twitter/X 推文 URL'), findsOneWidget);
    expect(find.text('解析视频'), findsOneWidget);
    expect(find.text('使用方法'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
