import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:m3u8downloader/src/jellyfin_client.dart';
import 'package:m3u8downloader/src/jellyfin_library_view.dart';

const _jsonHeaders = {'content-type': 'application/json'};

http.Response _ok(Object body) =>
    http.Response(jsonEncode(body), 200, headers: _jsonHeaders);

JellyfinClient _client(MockClient mock) => JellyfinClient(
  httpClient: mock,
  baseUrl: 'http://192.168.1.10:8096',
  accessToken: 'tok',
  userId: 'u1',
);

JellyfinView _view() => JellyfinView(
  id: 'v1',
  name: '电影',
  collectionType: 'movies',
  primaryImageTag: 'vt1',
);

Future<void> _pumpLibrary(WidgetTester tester, JellyfinClient client) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: JellyfinLibraryView(view: _view(), client: client),
    ),
  );
  await tester.pumpAndSettle();
}

MockClient _pagedMock({int total = 96}) {
  return MockClient((request) async {
    final startIndex = int.parse(
      request.url.queryParameters['StartIndex'] ?? '0',
    );
    final items = [
      for (var i = 0; i < 48 && startIndex + i < total; i++)
        {
          'Id': 'i${startIndex + i}',
          'Type': 'Movie',
          'Name': '第${startIndex + i + 1}部',
          'ImageTags': {'Primary': 'p${startIndex + i}'},
        },
    ];
    return _ok({'Items': items, 'TotalRecordCount': total});
  });
}

void main() {
  testWidgets('renders library name and paged items in a grid', (tester) async {
    await _pumpLibrary(tester, _client(_pagedMock()));

    expect(find.text('电影'), findsOneWidget);
    expect(find.text('第1部'), findsOneWidget);
    expect(find.text('第48部'), findsNothing);
  });

  testWidgets('scrolls near the end to load the next page', (tester) async {
    await _pumpLibrary(tester, _client(_pagedMock()));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -12000));
    await tester.pumpAndSettle();

    expect(find.text('第49部'), findsOneWidget);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -12000));
    await tester.pumpAndSettle();

    expect(find.text('第96部'), findsOneWidget);
  });

  testWidgets('shows empty message for an empty library', (tester) async {
    final client = _client(
      MockClient(
        (request) async => _ok({'Items': <Object>[], 'TotalRecordCount': 0}),
      ),
    );
    await _pumpLibrary(tester, client);

    expect(find.text('这个媒体库是空的'), findsOneWidget);
  });

  testWidgets('load failure shows retry and retry succeeds', (tester) async {
    var failing = true;
    final client = _client(
      MockClient((request) async {
        if (failing) throw Exception('boom');
        return _ok({
          'Items': [
            {'Id': 'i1', 'Type': 'Movie', 'Name': '重试成功'},
          ],
          'TotalRecordCount': 1,
        });
      }),
    );
    await _pumpLibrary(tester, client);

    expect(find.text('无法连接服务器，请检查网络'), findsOneWidget);

    failing = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('重试成功'), findsOneWidget);
  });

  testWidgets('401 pops with expired result', (tester) async {
    final client = _client(
      MockClient((request) async => http.Response('', 401)),
    );
    String? result;
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  result = await Navigator.push<String>(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          JellyfinLibraryView(view: _view(), client: client),
                    ),
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.byType(JellyfinLibraryView), findsNothing);
    expect(result, 'expired');
  });
}
