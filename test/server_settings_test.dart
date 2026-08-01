import 'package:flutter_test/flutter_test.dart';
import 'package:m3u8downloader/src/server_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemorySecureStore implements SecureKeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _FailingSecureStore implements SecureKeyValueStore {
  @override
  Future<String?> read(String key) async => throw Exception('unavailable');

  @override
  Future<void> write(String key, String value) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('save, load and remove roundtrip', () async {
    SharedPreferences.setMockInitialValues({});
    final secure = _MemorySecureStore();
    final store = ServerSettingsStore(secureStorage: secure);

    expect(await store.loadAll(), isEmpty);

    final config = ServerConfig(
      id: 'srv-1',
      type: ServerType.jellyfin,
      name: '家庭影院',
      url: 'http://192.168.1.10:8096',
      username: 'alice',
      userId: 'u1',
      accessToken: 'token-abc',
      createdAt: DateTime.parse('2026-08-02T10:00:00'),
    );
    await store.save(config);

    final loaded = await store.loadAll();
    expect(loaded, hasLength(1));
    expect(loaded.first.id, 'srv-1');
    expect(loaded.first.type, ServerType.jellyfin);
    expect(loaded.first.name, '家庭影院');
    expect(loaded.first.accessToken, 'token-abc');
    expect(secure.values['server.srv-1.token'], 'token-abc');

    await store.save(config.copyWith(accessToken: ''));
    expect((await store.loadAll()).single.accessToken, '');
    expect(secure.values['server.srv-1.token'], '');

    await store.remove('srv-1');
    expect(await store.loadAll(), isEmpty);
  });

  test('multiple servers sort by createdAt descending', () async {
    SharedPreferences.setMockInitialValues({});
    final store = ServerSettingsStore(secureStorage: _MemorySecureStore());
    await store.save(
      ServerConfig(
        id: 'a',
        type: ServerType.jellyfin,
        createdAt: DateTime.parse('2026-08-01T10:00:00'),
      ),
    );
    await store.save(
      ServerConfig(
        id: 'b',
        type: ServerType.jellyfin,
        createdAt: DateTime.parse('2026-08-02T10:00:00'),
      ),
    );
    final loaded = await store.loadAll();
    expect(loaded.map((c) => c.id).toList(), ['b', 'a']);
  });

  test('secure storage read failure is tolerated', () async {
    SharedPreferences.setMockInitialValues({});
    final store = ServerSettingsStore(secureStorage: _FailingSecureStore());
    await store.save(
      ServerConfig(
        id: 'srv-2',
        type: ServerType.jellyfin,
        accessToken: 'tok',
        createdAt: DateTime.parse('2026-08-02T10:00:00'),
      ),
    );
    final loaded = await store.loadAll();
    expect(loaded.single.id, 'srv-2');
    expect(loaded.single.accessToken, '');
  });
}
