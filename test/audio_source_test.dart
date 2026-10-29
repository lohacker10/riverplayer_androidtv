import 'package:flutter_test/flutter_test.dart';
import 'package:river_player/river_player.dart';
import 'package:river_player/src/dash/better_player_dash_utils.dart';
import 'package:xml/xml.dart';
import 'mock_video_player_controller.dart';

class AudioRecorder extends MockVideoPlayerController {
  String? name;
  int? index;
  @override
  void setAudioTrack(String? name, int? index) {
    this.name = name;
    this.index = index;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('DASH Label matches the native track name and preserves language', () {
    final node = XmlDocument.parse(
            '<AdaptationSet lang="ita" mimeType="audio/mp4"><Label>Italian</Label></AdaptationSet>')
        .rootElement;
    final track = BetterPlayerDashUtils.parseAudio(node, 1);
    expect(track.label, 'Italian');
    expect(track.language, 'ita');
    expect(track.id, 1);
    final nested = XmlDocument.parse(
            '<AdaptationSet lang="ita"><Representation><Label>Italian</Label></Representation></AdaptationSet>')
        .rootElement;
    expect(BetterPlayerDashUtils.parseAudio(nested, 1).label, 'Italian');
    final legacy =
        XmlDocument.parse('<AdaptationSet label="English" lang="eng"/>')
            .rootElement;
    expect(BetterPlayerDashUtils.parseAudio(legacy, 0).label, 'English');
  });
  test('a named track without language still reaches the native player', () {
    final controller =
        BetterPlayerController(const BetterPlayerConfiguration());
    final video = AudioRecorder();
    controller.videoPlayerController = video;
    controller
        .setAudioTrack(BetterPlayerAsmsAudioTrack(id: 1, label: 'Italian'));
    expect(video.name, 'Italian');
    expect(video.index, 1);
    controller
        .setAudioTrack(BetterPlayerAsmsAudioTrack(id: 0, language: 'eng'));
    expect(video.name, 'eng');
    expect(video.index, 0);
    controller.dispose(forceDispose: true);
  });
}
