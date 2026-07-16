import 'package:flutter_test/flutter_test.dart';
import 'package:m3u8downloader/src/twitter_download_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'download route defaults to direct and persists SnapCDN selection',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = TwitterDownloadSettingsStore.instance;

      expect(await store.load(), TwitterDownloadRoute.direct);

      await store.save(TwitterDownloadRoute.snapCdn);
      expect(await store.load(), TwitterDownloadRoute.snapCdn);
      expect(store.route.value, TwitterDownloadRoute.snapCdn);
    },
  );
}
