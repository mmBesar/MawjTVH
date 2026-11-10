import 'package:flutter_test/flutter_test.dart';
import 'package:mawjtvh/core/external_player.dart';

void main() {
  test('the settings name the right apps', () {
    expect(ExternalPlayerApp.byId('mpv')?.androidPackage, 'is.xyz.mpv');
    expect(ExternalPlayerApp.byId('vlc')?.androidPackage, 'org.videolan.vlc');
    expect(ExternalPlayerApp.byId('builtin'), isNull);
    expect(ExternalPlayerApp.byId('mx'), isNull);
  });

  test('a reply with a position and duration is read in milliseconds', () {
    final result = parseExternalPlayerResult(
      <String, Object?>{'code': -1, 'position': 90500, 'duration': 3600000},
    );
    expect(result.position, const Duration(milliseconds: 90500));
    expect(result.duration, const Duration(hours: 1));
  });

  test('a reply without them, or none at all, is empty', () {
    expect(parseExternalPlayerResult(<String, Object?>{'code': 0}).position,
        isNull);
    expect(parseExternalPlayerResult(null).duration, isNull);
    expect(
      parseExternalPlayerResult(<String, Object?>{'position': -5}).position,
      isNull,
    );
  });
}
