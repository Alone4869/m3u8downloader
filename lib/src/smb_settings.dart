import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SmbConfig {
  const SmbConfig({
    this.host = '',
    this.port = 445,
    this.share = '',
    this.username = '',
    this.password = '',
    this.domain = '',
  });

  final String host;
  final int port;
  final String share;
  final String username;
  final String password;
  final String domain;

  bool get isConfigured =>
      host.trim().isNotEmpty &&
      share.trim().isNotEmpty &&
      username.trim().isNotEmpty;

  Map<String, Object> toMap() => {
    'host': host.trim(),
    'port': port,
    'share': share.trim(),
    'username': username.trim(),
    'password': password,
    'domain': domain.trim(),
  };
}

class SmbSettingsStore {
  SmbSettingsStore._();

  static final SmbSettingsStore instance = SmbSettingsStore._();
  static const _secureStorage = FlutterSecureStorage();

  Future<SmbConfig> load() async {
    final preferences = await SharedPreferences.getInstance();
    return SmbConfig(
      host: preferences.getString('smb.host') ?? '',
      port: preferences.getInt('smb.port') ?? 445,
      share: preferences.getString('smb.share') ?? '',
      username: preferences.getString('smb.username') ?? '',
      password: await _secureStorage.read(key: 'smb.password') ?? '',
      domain: preferences.getString('smb.domain') ?? '',
    );
  }

  Future<void> save(SmbConfig config) async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.setString('smb.host', config.host.trim()),
      preferences.setInt('smb.port', config.port),
      preferences.setString('smb.share', config.share.trim()),
      preferences.setString('smb.username', config.username.trim()),
      preferences.setString('smb.domain', config.domain.trim()),
      _secureStorage.write(key: 'smb.password', value: config.password),
    ]);
  }
}
