import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u8downloader/src/app.dart';

void main() {
  testWidgets('tab pages always fill the available screen', (tester) async {
    const pageKey = ValueKey('downloads-page');

    await tester.pumpWidget(
      const MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 360,
            height: 500,
            child: FullScreenPageStack(
              index: 0,
              children: [
                Scaffold(key: pageKey),
                SizedBox.shrink(),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(pageKey)), const Size(360, 500));
  });

  testWidgets('downloads frame keeps header, content and actions visible', (
    tester,
  ) async {
    const headerKey = ValueKey('header');
    const bodyKey = ValueKey('body');
    const actionsKey = ValueKey('actions');

    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          // Simulate Scaffold.extendBody: padding includes the reserved
          // navigation height while viewPadding keeps the physical inset.
          data: MediaQueryData(
            padding: EdgeInsets.only(bottom: 92),
            viewPadding: EdgeInsets.only(bottom: 24),
          ),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 360,
              height: 500,
              child: DownloadsPageFrame(
                header: SizedBox(
                  key: headerKey,
                  height: 110,
                  child: Text('传输中心'),
                ),
                body: SizedBox(
                  key: bodyKey,
                  child: Center(child: Text('没有正在下载的任务')),
                ),
                bottomBar: SizedBox(
                  key: actionsKey,
                  height: 64,
                  child: Text('批量操作'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('传输中心'), findsOneWidget);
    expect(find.text('没有正在下载的任务'), findsOneWidget);
    expect(find.text('批量操作'), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(headerKey)).dy, 0);
    expect(tester.getSize(find.byKey(bodyKey)).height, 390);
    // 24px system inset + 68px floating navigation are kept clear.
    expect(tester.getTopLeft(find.byKey(actionsKey)).dy, 344);
  });
}
