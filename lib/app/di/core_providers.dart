import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/networking/api_constants.dart';
import '../../core/networking/dio_client.dart';
import '../../core/networking/network_info.dart';
import '../../core/platform/fetchr_api.g.dart' show FetchrHostApi;
import '../../core/services/storage/app_storage.dart';
import '../../core/services/storage/token_store.dart';

final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(),
);

final sharedPreferencesProvider = Provider<SharedPreferencesAsync>(
  (ref) => SharedPreferencesAsync(),
);

final internetConnectionProvider = Provider<InternetConnection>(
  (ref) => InternetConnection.createInstance(
    useDefaultOptions: false,
    // The app has no backend of its own: Google's 204 endpoint stands in for
    // "online", and any HTTP answer counts; the real call reports the real
    // error.
    customCheckOptions: [
      InternetCheckOption(
        uri: Uri.parse('https://connectivitycheck.gstatic.com/generate_204'),
        responseStatusFn: (_) => true,
      ),
    ],
  ),
);

final appStorageProvider = Provider<AppStorage>(
  (ref) => SharedPrefsAppStorage(ref.watch(sharedPreferencesProvider)),
);

final tokenStoreProvider = Provider<TokenStore>(
  (ref) => TokenStore(ref.watch(secureStorageProvider)),
);

final networkInfoProvider = Provider<INetworkInfo>(
  (ref) => NetworkInfoImpl(ref.watch(internetConnectionProvider)),
);

final dioProvider = Provider<Dio>(
  (ref) => buildDio(
    baseUrl: ApiConstants.baseUrl,
    tokenStore: ref.watch(tokenStoreProvider),
  ),
);

final dioClientProvider = Provider<DioClient>(
  (ref) => DioClient(ref.watch(dioProvider)),
);

final fetchrHostApiProvider = Provider<FetchrHostApi>((ref) => FetchrHostApi());
