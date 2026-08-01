import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u8downloader/src/video_player_launcher.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

const _channel = MethodChannel('m3u8_downloader/methods');

class _FakeLauncher extends UrlLauncherPlatform {
  String? launchedUrl;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrl = url;
    return true;
  }

  @override
  Future<bool> supportsMode(PreferredLaunchMode mode) async => true;
}

final _originalLauncher = UrlLauncherPlatform.instance;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeLauncher fakeLauncher;

  setUp(() {
    fakeLauncher = _FakeLauncher();
    UrlLauncherPlatform.instance = fakeLauncher;
    addTearDown(() => UrlLauncherPlatform.instance = _originalLauncher);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('launches the stream through the native channel on Android', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          return null;
        });

    final launched = await const VideoPlayerLauncher(
      isAndroid: true,
    ).launch('http://192.168.1.10:8096/videos/d1/stream.mp4?api_key=tok');

    expect(launched, isTrue);
    expect(calls.single.method, 'playVideo');
    expect((calls.single.arguments as Map)['url'], contains('stream.mp4'));
    expect((calls.single.arguments as Map).containsKey('package'), isFalse);
    expect(fakeLauncher.launchedUrl, isNull);
  });

  test('launch passes the chosen player package to the channel', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          return null;
        });

    final launched = await const VideoPlayerLauncher(
      isAndroid: true,
    ).launch('http://x/stream.mp4', package: 'org.videolan.vlc');

    expect(launched, isTrue);
    expect((calls.single.arguments as Map)['package'], 'org.videolan.vlc');
  });

  test('returns false when the native channel reports failure', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          _channel,
          (call) async => throw PlatformException(code: 'no_player'),
        );

    final launched = await const VideoPlayerLauncher(
      isAndroid: true,
    ).launch('http://x/stream.mp4');

    expect(launched, isFalse);
    expect(fakeLauncher.launchedUrl, isNull);
  });

  test('falls back to url_launcher on non-Android platforms', () async {
    final launched = await const VideoPlayerLauncher(
      isAndroid: false,
    ).launch('http://x/stream.mp4');

    expect(launched, isTrue);
    expect(fakeLauncher.launchedUrl, 'http://x/stream.mp4');
  });

  test('queryPlayers parses installed players from the channel', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          expect(call.method, 'queryVideoPlayers');
          return [
            {'package': 'org.videolan.vlc', 'label': 'VLC'},
            {'package': 'is.xyz.mpv', 'label': 'MPV'},
          ];
        });

    final players = await const VideoPlayerLauncher(
      isAndroid: true,
    ).queryPlayers('http://x/stream.mp4');

    expect(players, hasLength(2));
    expect(players.first.package, 'org.videolan.vlc');
    expect(players.first.label, 'VLC');
    expect(players.last.label, 'MPV');
  });

  test('launchInApp opens the embedded player through the channel', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          return null;
        });

    final launched = await const VideoPlayerLauncher(
      isAndroid: true,
    ).launchInApp('http://x/stream.mp4');

    expect(launched, isTrue);
    expect(calls.single.method, 'playInApp');
    expect((calls.single.arguments as Map)['url'], 'http://x/stream.mp4');
    expect(fakeLauncher.launchedUrl, isNull);
  });

  testWidgets('picker shows embedded player first and launches it', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          if (call.method == 'queryVideoPlayers') {
            return [
              {'package': 'org.videolan.vlc', 'label': 'VLC'},
            ];
          }
          return null;
        });

    bool? launched;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  launched = await const VideoPlayerLauncher(
                    isAndroid: true,
                  ).launchWithPicker(context, 'http://x/stream.mp4');
                },
                child: const Text('播放'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('播放'));
    await tester.pumpAndSettle();

    expect(find.text('应用内播放'), findsOneWidget);
    expect(find.text('系统播放器'), findsOneWidget);
    expect(find.text('VLC'), findsOneWidget);

    await tester.tap(find.text('应用内播放'));
    await tester.pumpAndSettle();

    expect(launched, isTrue);
    final playCall = calls.singleWhere((call) => call.method == 'playInApp');
    expect((playCall.arguments as Map)['url'], contains('stream.mp4'));
    expect(fakeLauncher.launchedUrl, isNull);
  });

  testWidgets('picker shows installed players and launches the chosen one', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          if (call.method == 'queryVideoPlayers') {
            return [
              {'package': 'org.videolan.vlc', 'label': 'VLC'},
            ];
          }
          return null;
        });

    bool? launched;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  launched = await const VideoPlayerLauncher(
                    isAndroid: true,
                  ).launchWithPicker(context, 'http://x/stream.mp4');
                },
                child: const Text('播放'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('播放'));
    await tester.pumpAndSettle();

    expect(find.text('应用内播放'), findsOneWidget);
    expect(find.text('系统播放器'), findsOneWidget);
    expect(find.text('VLC'), findsOneWidget);

    await tester.tap(find.text('VLC'));
    await tester.pumpAndSettle();

    expect(launched, isTrue);
    final playCall = calls.singleWhere((call) => call.method == 'playVideo');
    expect((playCall.arguments as Map)['package'], 'org.videolan.vlc');
    expect(fakeLauncher.launchedUrl, isNull);
  });

  testWidgets('picker system player option launches without a package', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          if (call.method == 'queryVideoPlayers') {
            return [
              {'package': 'is.xyz.mpv', 'label': 'MPV'},
            ];
          }
          return null;
        });

    bool? launched;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  launched = await const VideoPlayerLauncher(
                    isAndroid: true,
                  ).launchWithPicker(context, 'http://x/stream.mp4');
                },
                child: const Text('播放'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('播放'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('系统播放器'));
    await tester.pumpAndSettle();

    expect(launched, isTrue);
    final playCall = calls.singleWhere((call) => call.method == 'playVideo');
    expect((playCall.arguments as Map).containsKey('package'), isFalse);
    expect(fakeLauncher.launchedUrl, isNull);
  });

  testWidgets('picker without installed players still offers embedded player', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          if (call.method == 'queryVideoPlayers') return [];
          return null;
        });

    bool? launched;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  launched = await const VideoPlayerLauncher(
                    isAndroid: true,
                  ).launchWithPicker(context, 'http://x/stream.mp4');
                },
                child: const Text('播放'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('播放'));
    await tester.pumpAndSettle();

    expect(find.text('应用内播放'), findsOneWidget);
    expect(find.text('系统播放器'), findsOneWidget);

    await tester.tap(find.text('系统播放器'));
    await tester.pumpAndSettle();

    expect(launched, isTrue);
    expect(fakeLauncher.launchedUrl, isNull);
  });
}
