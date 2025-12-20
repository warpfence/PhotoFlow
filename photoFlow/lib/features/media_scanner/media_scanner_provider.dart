import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'media_scanner_service.dart';

/// SharedPreferences Provider
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be overridden in main.dart');
});

/// MediaScannerService Provider
final mediaScannerServiceProvider = Provider<MediaScannerService>((ref) {
  return MediaScannerService();
});

/// 하위 폴더 포함 설정 Provider
final includeSubfoldersProvider = StateNotifierProvider<IncludeSubfoldersNotifier, bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return IncludeSubfoldersNotifier(prefs);
});

class IncludeSubfoldersNotifier extends StateNotifier<bool> {
  final SharedPreferences _prefs;
  static const _key = 'include_subfolders';

  IncludeSubfoldersNotifier(this._prefs) : super(_prefs.getBool(_key) ?? true);

  Future<void> toggle() async {
    state = !state;
    await _prefs.setBool(_key, state);
  }

  Future<void> set(bool value) async {
    state = value;
    await _prefs.setBool(_key, value);
  }
}

/// 선택된 폴더 경로 Provider
final selectedFolderPathProvider = StateNotifierProvider<SelectedFolderPathNotifier, String?>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SelectedFolderPathNotifier(prefs);
});

class SelectedFolderPathNotifier extends StateNotifier<String?> {
  final SharedPreferences _prefs;
  static const _key = 'selected_folder_path';

  SelectedFolderPathNotifier(this._prefs) : super(_prefs.getString(_key));

  Future<void> set(String? path) async {
    state = path;
    if (path != null) {
      await _prefs.setString(_key, path);
    } else {
      await _prefs.remove(_key);
    }
  }
}

/// 스캔 진행 상황 Provider
final scanProgressProvider = StateProvider<ScanProgress?>((ref) => null);

/// 스캔 결과 Provider
final scanResultProvider = StateNotifierProvider<ScanResultNotifier, AsyncValue<ScanResult?>>((ref) {
  final scanner = ref.watch(mediaScannerServiceProvider);
  return ScanResultNotifier(ref, scanner);
});

class ScanResultNotifier extends StateNotifier<AsyncValue<ScanResult?>> {
  final Ref _ref;
  final MediaScannerService _scanner;

  ScanResultNotifier(this._ref, this._scanner) : super(const AsyncValue.data(null));

  /// 폴더 스캔 시작
  Future<void> scanFolder(String folderPath) async {
    state = const AsyncValue.loading();

    try {
      final includeSubfolders = _ref.read(includeSubfoldersProvider);

      final result = await _scanner.scanFolder(
        folderPath: folderPath,
        includeSubfolders: includeSubfolders,
        onProgress: (progress) {
          _ref.read(scanProgressProvider.notifier).state = progress;
        },
      );

      state = AsyncValue.data(result);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 스캔 결과 초기화
  void clear() {
    state = const AsyncValue.data(null);
    _ref.read(scanProgressProvider.notifier).state = null;
  }
}
