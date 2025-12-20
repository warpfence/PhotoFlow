import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../media_scanner/streaming_media_scanner.dart';
import '../settings/settings_provider.dart';

/// 스트리밍 슬라이드쇼 상태
class StreamingSlideshowState {
  final List<String> loadedImages;
  final int currentIndex;
  final bool isPlaying;
  final bool isScanning;
  final bool isScanComplete;
  final int scannedFolders;
  final String? currentScanFolder;
  final String? errorMessage;

  /// 랜덤 재생에서 이미 본 이미지 인덱스들
  final Set<int> viewedIndices;

  /// 랜덤 재생에서 방문 기록 (뒤로가기 지원)
  final List<int> playHistory;

  const StreamingSlideshowState({
    this.loadedImages = const [],
    this.currentIndex = 0,
    this.isPlaying = true,
    this.isScanning = true,
    this.isScanComplete = false,
    this.scannedFolders = 0,
    this.currentScanFolder,
    this.errorMessage,
    this.viewedIndices = const {},
    this.playHistory = const [],
  });

  /// 현재 표시할 이미지 경로
  String? get currentImagePath =>
      loadedImages.isNotEmpty ? loadedImages[currentIndex] : null;

  /// 이미지가 있는지 여부
  bool get hasImages => loadedImages.isNotEmpty;

  /// 전체 이미지 수
  int get totalImages => loadedImages.length;

  StreamingSlideshowState copyWith({
    List<String>? loadedImages,
    int? currentIndex,
    bool? isPlaying,
    bool? isScanning,
    bool? isScanComplete,
    int? scannedFolders,
    String? currentScanFolder,
    String? errorMessage,
    Set<int>? viewedIndices,
    List<int>? playHistory,
  }) {
    return StreamingSlideshowState(
      loadedImages: loadedImages ?? this.loadedImages,
      currentIndex: currentIndex ?? this.currentIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      isScanning: isScanning ?? this.isScanning,
      isScanComplete: isScanComplete ?? this.isScanComplete,
      scannedFolders: scannedFolders ?? this.scannedFolders,
      currentScanFolder: currentScanFolder ?? this.currentScanFolder,
      errorMessage: errorMessage,
      viewedIndices: viewedIndices ?? this.viewedIndices,
      playHistory: playHistory ?? this.playHistory,
    );
  }
}

/// 스트리밍 슬라이드쇼 컨트롤러
///
/// 백그라운드에서 이미지를 스캔하면서 동시에 슬라이드쇼를 실행합니다.
/// 첫 이미지가 발견되면 즉시 슬라이드쇼가 시작됩니다.
class StreamingSlideshowController extends StateNotifier<StreamingSlideshowState> {
  final Ref _ref;
  final StreamingMediaScanner _scanner;
  final Random _random = Random();

  Timer? _slideTimer;
  StreamSubscription<StreamingScanEvent>? _scanSubscription;

  StreamingSlideshowController(this._ref, this._scanner)
      : super(const StreamingSlideshowState());

  /// 현재 재생 모드가 랜덤인지 확인
  bool get _isRandomMode => _ref.read(settingsProvider).playOrder == PlayOrder.random;

  /// 스트리밍 슬라이드쇼 시작
  ///
  /// [folderPath]: 스캔할 폴더 경로
  /// [includeSubfolders]: 하위 폴더 포함 여부
  void startStreaming({
    required String folderPath,
    bool includeSubfolders = true,
  }) {
    // 기존 상태 초기화
    _stopSlideTimer();
    _scanSubscription?.cancel();

    state = const StreamingSlideshowState();

    // 백그라운드 스캔 시작
    final stream = _scanner.scanFolderStream(
      folderPath: folderPath,
      includeSubfolders: includeSubfolders,
    );

    _scanSubscription = stream.listen(
      _handleScanEvent,
      onError: (error) {
        state = state.copyWith(
          isScanning: false,
          errorMessage: error.toString(),
        );
      },
    );
  }

  /// 스캔 이벤트 처리
  void _handleScanEvent(StreamingScanEvent event) {
    switch (event) {
      case ImageFoundEvent():
        final newImages = [...state.loadedImages, event.imagePath];
        state = state.copyWith(loadedImages: newImages);

        // 첫 이미지가 발견되면 슬라이드 타이머 시작
        if (newImages.length == 1 && state.isPlaying) {
          // 첫 이미지를 본 것으로 기록
          state = state.copyWith(
            viewedIndices: {0},
            playHistory: [0],
          );
          _startSlideTimer();
        }

      case ScanProgressEvent():
        state = state.copyWith(
          scannedFolders: event.foldersScanned,
          currentScanFolder: event.currentFolder,
        );

      case ScanCompleteEvent():
        // 스캔 완료 시 이미지가 없으면 에러 메시지 설정
        final noImagesFound = state.loadedImages.isEmpty;
        state = state.copyWith(
          isScanning: false,
          isScanComplete: true,
          scannedFolders: event.totalFolders,
          currentScanFolder: null,
          errorMessage: noImagesFound
              ? '선택한 폴더에서 이미지를 찾을 수 없습니다.\n\n총 ${event.totalFolders}개 폴더를 스캔했습니다.'
              : null,
        );

      case ScanErrorEvent():
        state = state.copyWith(
          isScanning: false,
          errorMessage: event.message,
        );
    }
  }

  /// 슬라이드 타이머 시작
  void _startSlideTimer() {
    _stopSlideTimer();

    if (!state.isPlaying) return;

    final settings = _ref.read(settingsProvider);
    _slideTimer = Timer.periodic(
      Duration(seconds: settings.slideInterval.seconds),
      (_) => nextImage(),
    );
  }

  /// 슬라이드 타이머 중지
  void _stopSlideTimer() {
    _slideTimer?.cancel();
    _slideTimer = null;
  }

  /// 다음 이미지로 이동
  void nextImage() {
    if (state.loadedImages.isEmpty) return;

    if (_isRandomMode) {
      _nextRandomImage();
    } else {
      _nextSequentialImage();
    }
  }

  /// 순차 재생: 다음 이미지
  void _nextSequentialImage() {
    int nextIndex = state.currentIndex + 1;

    // 스캔 완료 전: 다음 이미지가 없으면 대기
    if (!state.isScanComplete && nextIndex >= state.loadedImages.length) {
      return;
    }

    // 스캔 완료 후: 순환
    if (nextIndex >= state.loadedImages.length) {
      nextIndex = 0;
    }

    state = state.copyWith(currentIndex: nextIndex);
  }

  /// 랜덤 재생: 다음 이미지
  void _nextRandomImage() {
    final totalImages = state.loadedImages.length;
    if (totalImages <= 1) return;

    // 아직 보지 않은 이미지들 찾기
    final unviewedIndices = <int>[];
    for (int i = 0; i < totalImages; i++) {
      if (!state.viewedIndices.contains(i)) {
        unviewedIndices.add(i);
      }
    }

    int nextIndex;
    Set<int> newViewedIndices;
    List<int> newPlayHistory;

    if (unviewedIndices.isEmpty) {
      // 모든 이미지를 봤음
      if (!state.isScanComplete) {
        // 스캔 중이면 대기 (새 이미지가 추가될 수 있음)
        return;
      }
      // 스캔 완료 → 처음부터 다시 랜덤 재생
      nextIndex = _random.nextInt(totalImages);
      newViewedIndices = {nextIndex};
      newPlayHistory = [nextIndex];
    } else {
      // 보지 않은 이미지 중에서 랜덤 선택
      nextIndex = unviewedIndices[_random.nextInt(unviewedIndices.length)];
      newViewedIndices = {...state.viewedIndices, nextIndex};
      newPlayHistory = [...state.playHistory, nextIndex];
    }

    state = state.copyWith(
      currentIndex: nextIndex,
      viewedIndices: newViewedIndices,
      playHistory: newPlayHistory,
    );
  }

  /// 이전 이미지로 이동
  void previousImage() {
    if (state.loadedImages.isEmpty) return;

    if (_isRandomMode) {
      _previousRandomImage();
    } else {
      _previousSequentialImage();
    }
  }

  /// 순차 재생: 이전 이미지
  void _previousSequentialImage() {
    int prevIndex = state.currentIndex - 1;
    if (prevIndex < 0) {
      prevIndex = state.loadedImages.length - 1;
    }
    state = state.copyWith(currentIndex: prevIndex);
  }

  /// 랜덤 재생: 이전 이미지 (히스토리 기반)
  void _previousRandomImage() {
    if (state.playHistory.length <= 1) {
      // 히스토리가 없으면 이동 불가
      return;
    }

    // 현재 이미지를 히스토리에서 제거하고 이전 이미지로
    final newHistory = List<int>.from(state.playHistory)..removeLast();
    final prevIndex = newHistory.last;

    // viewedIndices에서도 현재 이미지 제거 (다시 랜덤 풀에 포함)
    final newViewedIndices = Set<int>.from(state.viewedIndices)
      ..remove(state.currentIndex);

    state = state.copyWith(
      currentIndex: prevIndex,
      playHistory: newHistory,
      viewedIndices: newViewedIndices,
    );
  }

  /// 특정 인덱스로 이동
  void goToIndex(int index) {
    if (index >= 0 && index < state.loadedImages.length) {
      final newViewedIndices = {...state.viewedIndices, index};
      final newPlayHistory = [...state.playHistory, index];

      state = state.copyWith(
        currentIndex: index,
        viewedIndices: newViewedIndices,
        playHistory: newPlayHistory,
      );
    }
  }

  /// 재생/일시정지 토글
  void togglePlayPause() {
    final newIsPlaying = !state.isPlaying;
    state = state.copyWith(isPlaying: newIsPlaying);

    if (newIsPlaying) {
      _startSlideTimer();
    } else {
      _stopSlideTimer();
    }
  }

  /// 재생 상태 설정
  void setPlaying(bool playing) {
    if (state.isPlaying == playing) return;

    state = state.copyWith(isPlaying: playing);

    if (playing) {
      _startSlideTimer();
    } else {
      _stopSlideTimer();
    }
  }

  /// 리소스 정리
  @override
  void dispose() {
    _stopSlideTimer();
    _scanSubscription?.cancel();
    super.dispose();
  }
}

/// StreamingMediaScanner Provider
final streamingMediaScannerProvider = Provider<StreamingMediaScanner>((ref) {
  return StreamingMediaScanner();
});

/// StreamingSlideshowController Provider
final streamingSlideshowControllerProvider =
    StateNotifierProvider.autoDispose<StreamingSlideshowController, StreamingSlideshowState>(
  (ref) {
    final scanner = ref.watch(streamingMediaScannerProvider);
    return StreamingSlideshowController(ref, scanner);
  },
);
