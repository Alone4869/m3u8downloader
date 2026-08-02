import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:m3u8downloader/src/jellyfin_client.dart';
import 'package:m3u8downloader/src/server_home_view.dart';
import 'package:m3u8downloader/src/server_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _jsonHeaders = {'content-type': 'application/json'};

class _MemorySecureStore implements SecureKeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

ServerSettingsStore _store() =>
    ServerSettingsStore(secureStorage: _MemorySecureStore());

JellyfinClient _loginClient() => JellyfinClient(
  httpClient: MockClient((request) async {
    if (request.url.path.endsWith('/Users/AuthenticateByName')) {
      return http.Response(
        jsonEncode({
          'User': {'Id': 'u1'},
          'AccessToken': 'tok',
        }),
        200,
        headers: _jsonHeaders,
      );
    }
    if (request.url.path.endsWith('/Views')) {
      return http.Response('{"Items": []}', 200, headers: _jsonHeaders);
    }
    if (request.url.path.endsWith('/Items/Resume')) {
      return http.Response('{"Items": []}', 200, headers: _jsonHeaders);
    }
    return http.Response('[]', 200, headers: _jsonHeaders);
  }),
);

Future<void> _pumpServerView(
  WidgetTester tester, {
  required ServerSettingsStore store,
  JellyfinClient Function()? clientFactory,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ServerHomeView(store: store, clientFactory: clientFactory),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('empty state shows guide and add sheet with protocol cards', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await _pumpServerView(tester, store: _store());

    expect(find.text('添加你的第一个服务器'), findsOneWidget);

    await tester.tap(find.text('添加服务器'));
    await tester.pumpAndSettle();

    expect(find.text('选择服务器类型'), findsOneWidget);
    expect(find.text('Jellyfin'), findsOneWidget);
    expect(find.text('Emby'), findsOneWidget);
    expect(find.text('SMB'), findsOneWidget);
    expect(find.text('即将支持'), findsNWidgets(2));
  });

  testWidgets('connect flow saves server and enters jellyfin home', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = _store();
    await _pumpServerView(tester, store: store, clientFactory: _loginClient);

    await tester.tap(find.text('添加服务器'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jellyfin'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '家庭影院');
    await tester.enterText(fields.at(1), 'http://192.168.1.10:8096');
    await tester.enterText(fields.at(2), 'alice');
    await tester.enterText(fields.at(3), 'secret');
    await tester.tap(find.text('测试并连接'));
    await tester.pumpAndSettle();

    expect(find.text('已连接 家庭影院'), findsOneWidget);
    final saved = await store.loadAll();
    expect(saved, hasLength(1));
    expect(saved.first.name, '家庭影院');
    expect(saved.first.accessToken, 'tok');
    expect(saved.first.userId, 'u1');
  });

  testWidgets('saved server card opens, delete removes it', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = _store();
    await store.save(
      ServerConfig(
        id: 'srv-1',
        type: ServerType.jellyfin,
        name: '家庭影院',
        url: 'http://192.168.1.10:8096',
        accessToken: 'tok',
        createdAt: DateTime.parse('2026-08-02T10:00:00'),
      ),
    );
    await _pumpServerView(tester, store: store);

    expect(find.text('家庭影院'), findsOneWidget);
    expect(find.text('192.168.1.10:8096'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsNothing);

    await tester.longPress(find.text('家庭影院'));
    await tester.pumpAndSettle();
    expect(find.text('编辑'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除服务器「家庭影院」？'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('添加你的第一个服务器'), findsOneWidget);
    expect(await store.loadAll(), isEmpty);
  });

  testWidgets('long press menu opens edit sheet pre-filled', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = _store();
    await store.save(
      ServerConfig(
        id: 'srv-1',
        type: ServerType.jellyfin,
        name: '家庭影院',
        url: 'http://192.168.1.10:8096',
        accessToken: 'tok',
        createdAt: DateTime.parse('2026-08-02T10:00:00'),
      ),
    );
    await _pumpServerView(tester, store: store);

    await tester.longPress(find.text('家庭影院'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();

    final fieldTexts = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((f) => f.controller!.text)
        .toList();
    expect(fieldTexts, contains('家庭影院'));
    expect(fieldTexts, contains('http://192.168.1.10:8096'));
    expect(await store.loadAll(), hasLength(1));
  });

  testWidgets('server without token shows reconnect badge', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = _store();
    await store.save(
      ServerConfig(
        id: 'srv-2',
        type: ServerType.jellyfin,
        name: '旧服务器',
        url: 'http://192.168.1.10:8096',
        createdAt: DateTime.parse('2026-08-02T10:00:00'),
      ),
    );
    await _pumpServerView(tester, store: store);

    expect(find.text('需重新连接'), findsOneWidget);

    await tester.tap(find.text('旧服务器'));
    await tester.pumpAndSettle();
    expect(find.text('连接 Jellyfin'), findsOneWidget);
    expect(find.text('192.168.1.10:8096'), findsOneWidget);
  });
}
