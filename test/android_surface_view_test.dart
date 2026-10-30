import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:river_player/river_player.dart';
import 'package:river_player/src/video_player/method_channel_video_player.dart';
import 'package:river_player/src/video_player/video_player.dart' as video;
import 'package:river_player/src/video_player/video_player_platform_interface.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('better_player_channel');
  const viewsChannel = MethodChannel('flutter/platform_views');
  final calls = <MethodCall>[];
  final viewCalls = <MethodCall>[];
  final eventChannels = <MethodChannel>[];
  late MethodChannelVideoPlayer platform;
  bool acknowledgeNativeView = true;
  Completer<void>? createGate;

  setUp(() {
    platform = MethodChannelVideoPlayer();
    calls.clear();
    viewCalls.clear();
    eventChannels.clear();
    acknowledgeNativeView = true;
    createGate = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      if (call.method == 'create') {
        await createGate?.future;
        final args = call.arguments as Map<dynamic, dynamic>?;
        final native =
            acknowledgeNativeView && args?['useAndroidSurfaceView'] == true;
        final id = native ? -2 : 7;
        final eventChannel =
            MethodChannel('better_player_channel/videoEvents$id');
        eventChannels.add(eventChannel);
        binding.defaultBinaryMessenger
            .setMockMethodCallHandler(eventChannel, (_) async => null);
        return <String, dynamic>{
          'textureId': id,
          'useAndroidSurfaceView': native
        };
      }
      return null;
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(viewsChannel,
        (call) async {
      viewCalls.add(call);
      return null;
    });
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(viewsChannel, null);
    for (final eventChannel in eventChannels) {
      binding.defaultBinaryMessenger
          .setMockMethodCallHandler(eventChannel, null);
    }
  });

  test('native view is opt-in and survives configuration copies', () {
    const defaults = BetterPlayerConfiguration();
    expect(defaults.useAndroidSurfaceView, isFalse);
    final native = defaults.copyWith(useAndroidSurfaceView: true);
    expect(native.copyWith(autoPlay: true).useAndroidSurfaceView, isTrue);
    expect(native.copyWith(useAndroidSurfaceView: false).useAndroidSurfaceView,
        isFalse);
  });

  test('previews keep textures and older backends can fall back to textures',
      () async {
    final previewId = await platform.create();
    expect(platform.buildView(previewId), isA<Texture>());
    expect(calls.last.arguments, isNull);
    acknowledgeNativeView = false;
    final id = await platform.create(useAndroidSurfaceView: true);
    expect(calls.last.arguments['useAndroidSurfaceView'], isTrue);
    expect(platform.buildView(id), isA<Texture>());
  });

  test('keeps audio, quality, seek and source formats on the same player',
      () async {
    final id = await platform.create(useAndroidSurfaceView: true);
    await platform.setAudioTrack(id, 'Italiano', 1);
    await platform.setTrackParameters(id, 1920, 1080, 5000000);
    await platform.seekTo(id, const Duration(seconds: 15));
    for (final format in [
      VideoFormat.hls,
      VideoFormat.dash,
      VideoFormat.other
    ]) {
      await platform.setDataSource(
          id,
          DataSource(
            sourceType: DataSourceType.network,
            uri: 'https://example.test/video',
            formatHint: format,
          ));
    }
    final commands = calls.where((call) => call.method != 'create');
    expect(commands.every((call) => call.arguments['textureId'] == id), isTrue);
    expect(
        commands.map((call) => call.method),
        containsAll([
          'setAudioTrack',
          'setTrackParameters',
          'seekTo',
        ]));
    expect(
        commands.where((call) => call.method == 'setDataSource').map(
              (call) => call.arguments['dataSource']['formatHint'],
            ),
        ['hls', 'dash', 'other']);
  });

  testWidgets(
      'uses native composition while overlay buttons and video taps work',
      (tester) async {
    final id = await platform.create(useAndroidSurfaceView: true);
    int audioTaps = 0;
    int videoTaps = 0;
    const stackKey = ValueKey('video-stack');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            height: 180,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => videoTaps++,
              child: Stack(
                key: stackKey,
                children: [
                  Positioned.fill(child: platform.buildView(id)),
                  Center(
                      child: TextButton(
                          onPressed: () => audioTaps++,
                          child: const Text('Audio'))),
                ],
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final create = viewCalls.singleWhere((call) => call.method == 'create');
    expect(create.arguments['hybrid'], isTrue);
    expect(create.arguments['viewType'], 'river_player/surface_view');
    final parameters = const StandardMessageCodec().decodeMessage(
        ByteData.sublistView(create.arguments['params'] as Uint8List));
    expect((parameters! as Map)['textureId'], id);
    expect(find.byType(PlatformViewLink), findsOneWidget);
    expect(
        Focus.of(tester.element(find.byType(AndroidViewSurface)))
            .canRequestFocus,
        isFalse);
    expect(
        Focus.of(tester.element(find.text('Audio'))).canRequestFocus, isTrue);
    await tester.tap(find.text('Audio'));
    expect(audioTaps, 1);
    expect(videoTaps, 0);
    await tester
        .tapAt(tester.getTopLeft(find.byKey(stackKey)) + const Offset(10, 10));
    expect(videoTaps, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await platform.dispose(id);
    expect(platform.buildView(id), isA<Texture>());
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('mounts the native view before media initialization',
      (tester) async {
    VideoPlayerPlatform.instance = platform;
    createGate = Completer<void>();
    final controller = video.VideoPlayerController(useAndroidSurfaceView: true);
    await tester.pumpWidget(MaterialApp(home: video.VideoPlayer(controller)));
    expect(find.byType(PlatformViewLink), findsNothing);
    createGate!.complete();
    await tester.pumpAndSettle();
    expect(controller.value.initialized, isFalse);
    expect(find.byType(PlatformViewLink), findsOneWidget);
    expect(
        calls
            .firstWhere((call) => call.method == 'create')
            .arguments['useAndroidSurfaceView'],
        isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.runAsync(controller.dispose);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
