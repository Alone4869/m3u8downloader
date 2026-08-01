import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ServerType { jellyfin, emby, smb }

class ServerConfig {
  const ServerConfig({
    required this.id,
    required this.type,
    this.name = '',
    this.url = '',
    this.username = '',
    this.userId = '',
    this.accessToken = '',
    required this.createdAt,
  });

  final String id;
  final ServerType type;
  final String name;
  final String url;
  final String username;
  final String userId;
  final String accessToken;
  final DateTime createdAt;

  bool get hasToken => accessToken.isNotEmpty;

  ServerConfig copyWith({
    String? name,
    String? url,
    String? username,
    String? userId,
    String? accessToken,
  }) => ServerConfig(
    id: id,
    type: type,
    name: name ?? this.name,
    url: url ?? this.url,
    username: username ?? this.username,
    userId: userId ?? this.userId,
    accessToken: accessToken ?? this.accessToken,
    createdAt: createdAt,
  );
}

abstract class SecureKeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);
}

class FlutterSecureStorageAdapter implements SecureKeyValueStore {
  FlutterSecureStorageAdapter(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

class ServerSettingsStore {
  ServerSettingsStore({SecureKeyValueStore? secureStorage})
    : _secureStorage =
          secureStorage ??
          FlutterSecureStorageAdapter(const FlutterSecureStorage());

  static final ServerSettingsStore instance = ServerSettingsStore();

  final SecureKeyValueStore _secureStorage;
  static const _idsKey = 'server.ids';

  String _typeKey(String id) => 'server.$id.type';
  String _nameKey(String id) => 'server.$id.name';
  String _urlKey(String id) => 'server.$id.url';
  String _usernameKey(String id) => 'server.$id.username';
  String _userIdKey(String id) => 'server.$id.userId';
  String _createdAtKey(String id) => 'server.$id.createdAt';
  String _tokenKey(String id) => 'server.$id.token';

  Future<List<ServerConfig>> loadAll() async {
    final preferences = await SharedPreferences.getInstance();
    final ids = preferences.getStringList(_idsKey) ?? const [];
    final configs = <ServerConfig>[];
    for (final id in ids) {
      final type = preferences.getString(_typeKey(id));
      if (type == null) continue;
      String? token;
      try {
        token = await _secureStorage.read(_tokenKey(id));
      } catch (_) {
        token = null;
      }
      configs.add(
        ServerConfig(
          id: id,
          type: ServerType.values.firstWhere(
            (t) => t.name == type,
            orElse: () => ServerType.jellyfin,
          ),
          name: preferences.getString(_nameKey(id)) ?? '',
          url: preferences.getString(_urlKey(id)) ?? '',
          username: preferences.getString(_usernameKey(id)) ?? '',
          userId: preferences.getString(_userIdKey(id)) ?? '',
          accessToken: token ?? '',
          createdAt:
              DateTime.tryParse(
                preferences.getString(_createdAtKey(id)) ?? '',
              ) ??
              DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );
    }
    configs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return configs;
  }

  Future<void> save(ServerConfig config) async {
    final preferences = await SharedPreferences.getInstance();
    final ids = preferences.getStringList(_idsKey) ?? <String>[];
    if (!ids.contains(config.id)) ids.add(config.id);
    await Future.wait([
      preferences.setStringList(_idsKey, ids),
      preferences.setString(_typeKey(config.id), config.type.name),
      preferences.setString(_nameKey(config.id), config.name),
      preferences.setString(_urlKey(config.id), config.url),
      preferences.setString(_usernameKey(config.id), config.username),
      preferences.setString(_userIdKey(config.id), config.userId),
      preferences.setString(
        _createdAtKey(config.id),
        config.createdAt.toIso8601String(),
      ),
      _secureStorage.write(_tokenKey(config.id), config.accessToken),
    ]);
  }

  Future<void> remove(String id) async {
    final preferences = await SharedPreferences.getInstance();
    final ids = preferences.getStringList(_idsKey) ?? <String>[];
    ids.remove(id);
    await Future.wait([
      preferences.setStringList(_idsKey, ids),
      preferences.remove(_typeKey(id)),
      preferences.remove(_nameKey(id)),
      preferences.remove(_urlKey(id)),
      preferences.remove(_usernameKey(id)),
      preferences.remove(_userIdKey(id)),
      preferences.remove(_createdAtKey(id)),
      _secureStorage.write(_tokenKey(id), ''),
    ]);
  }
}
