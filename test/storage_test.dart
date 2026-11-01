import 'package:flutter_test/flutter_test.dart';
import 'package:mawjtvh/core/catppuccin.dart';
import 'package:mawjtvh/data/models.dart';
import 'package:mawjtvh/data/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('settings and sources survive a JSON round trip', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final storage = await StorageService.create();

    final settings = AppSettings.defaults().copyWith(
      themeFamily: ThemeFamily.amoled,
      accent: ThemeAccent.peach,
      language: AppLanguage.arabic,
      use24HourTime: true,
      activeSourceId: 'home',
    );
    await storage.saveSettings(settings);

    final loaded = storage.loadSettings();
    expect(loaded.themeFamily, ThemeFamily.amoled);
    expect(loaded.accent, ThemeAccent.peach);
    expect(loaded.language, AppLanguage.arabic);
    expect(loaded.use24HourTime, isTrue);
    expect(loaded.activeSourceId, 'home');

    const source = SourceConfig(
      id: 'home',
      name: 'تيفي هيد المنزل',
      address: 'https://tv.hs.lan',
      username: 'mm',
      password: 'p@ss:word',
      profile: 'matroska',
      allowInsecureCerts: true,
    );
    await storage.saveSources(<SourceConfig>[source]);

    final sources = storage.loadSources();
    expect(sources, hasLength(1));
    expect(sources.single.name, 'تيفي هيد المنزل');
    expect(sources.single.address, 'https://tv.hs.lan');
    expect(sources.single.username, 'mm');
    expect(sources.single.password, 'p@ss:word');
    expect(sources.single.profile, 'matroska');
    expect(sources.single.allowInsecureCerts, isTrue);
  });

  test('invalid preference JSON falls back to defaults', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'mawjtvh.settings.v1': 'not json',
      'mawjtvh.sources.v1': '{"unexpected": true}',
    });
    final storage = await StorageService.create();

    expect(storage.loadSettings().themeFamily, ThemeFamily.mawj);
    expect(storage.loadSources(), isEmpty);
  });

  test('favourites and recents are kept per source', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final storage = await StorageService.create();

    await storage.saveFavorites('a', <String>['a|one', 'a|two']);
    await storage.saveFavorites('b', <String>['b|x']);
    await storage.saveRecents('a', <String>['a|two']);

    expect(storage.loadFavorites('a'), <String>['a|one', 'a|two']);
    expect(storage.loadFavorites('b'), <String>['b|x']);
    expect(storage.loadRecents('a'), <String>['a|two']);
    expect(storage.loadRecents('b'), isEmpty);
  });
}
