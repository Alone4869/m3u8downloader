import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class PlayerApp {
  const PlayerApp({required this.package, required this.label});

  final String package;
  final String label;
}

class VideoPlayerLauncher {
  const VideoPlayerLauncher({this._isAndroid});

  final bool? _isAndroid;
  static const _channel = MethodChannel('m3u8_downloader/methods');

  bool get _useNative => _isAndroid ?? Platform.isAndroid;

  Future<List<PlayerApp>> queryPlayers(String url) async {
    if (!_useNative) return const [];
    try {
      final result = await _channel.invokeListMethod<Map<dynamic, dynamic>>(
        'queryVideoPlayers',
        {'url': url},
      );
      return [
        for (final entry in result ?? const [])
          PlayerApp(
            package: entry['package'] as String? ?? '',
            label: entry['label'] as String? ?? '',
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<bool> launch(String url, {String? package}) async {
    if (_useNative) {
      try {
        await _channel.invokeMethod<void>('playVideo', {
          'url': url,
          'package': ?package,
        });
        return true;
      } catch (_) {
        return false;
      }
    }
    return launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<bool> launchInApp(String url) async {
    if (!_useNative) return launch(url);
    try {
      await _channel.invokeMethod<void>('playInApp', {'url': url});
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> launchWithPicker(BuildContext context, String url) async {
    final players = await queryPlayers(url);
    if (!_useNative) return launch(url);
    if (!context.mounted) return false;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF16161C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text(
                '选择播放器',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.play_circle_fill_rounded,
                color: Color(0xFF00A4DC),
              ),
              title: const Text(
                '应用内播放',
                style: TextStyle(color: Colors.white, fontSize: 15),
              ),
              onTap: () => Navigator.pop(sheetContext, '_in_app_'),
            ),
            ListTile(
              leading: const Icon(
                Icons.smartphone_rounded,
                color: Colors.white70,
              ),
              title: const Text(
                '系统播放器',
                style: TextStyle(color: Colors.white, fontSize: 15),
              ),
              onTap: () => Navigator.pop(sheetContext, ''),
            ),
            for (final player in players)
              ListTile(
                leading: const Icon(
                  Icons.play_circle_outline_rounded,
                  color: Colors.white70,
                ),
                title: Text(
                  player.label,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
                onTap: () => Navigator.pop(sheetContext, player.package),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (chosen == null) return true;
    if (chosen == '_in_app_') return launchInApp(url);
    return launch(url, package: chosen.isEmpty ? null : chosen);
  }
}
