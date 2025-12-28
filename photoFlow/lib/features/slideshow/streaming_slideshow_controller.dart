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

  /// 랜덤 재생: 셔플된 인덱스 순서
  final List<int> shuffledIndices;

  /// 랜덤 재생: 현재 셔플 위치
  final int shufflePosition;

  /// 랜덤 재생에서 방문 기록 (뒤로가기 지원, 크기 제한)
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
    this.shuffledIndices = const [],
    this.shufflePosition = 0,
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
    List<int>? shuffledIndices,
    int? shufflePosition,
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
      shuffledIndices: shuffledIndices ?? this.shuffledIndices,
      shufflePosition: shufflePosition ?? this.shufflePosition,
      playHistory: playHistory ?? this.playHistory,
    );
  }
}

/// 스트리밍 슬라이드쇼 컨트롤러
///
/// 백그라운드에서 이미지를 스캔하면서 동시에 슬라이드쇼를 실행합니다.
/// 첫 이미지가 발견되면 즉시 슬라이드쇼가 시작됩니다.
class StreamingSlideshowController
    extends StateNotifier<StreamingSlideshowState> {
  final Ref _ref;
  final StreamingMediaScanner _scanner;
  final Random _random = Random();

  Timer? _slideTimer;
  StreamSubscription<StreamingScanEvent>? _scanSubscription;

  // 배치 처리를 위한 버퍼
  List<String> _pendingImages = [];
  Timer? _batchTimer;
  static const int _batchSize = 100;
  static const Duration _batchDelay = Duration(milliseconds: 50);

  // 히스토리 크기 제한
  static const int _maxHistorySize = 100;

  StreamingSlideshowController(this._ref, this._scanner)
      : super(const StreamingSlideshowState());

  /// 현재 재생 모드가 랜덤인지 확인
  bool get _isRandomMode =>
      _ref.read(settingsProvider).playOrder == PlayOrder.random;

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
    _batchTimer?.cancel();
    _pendingImages = [];

    state = const StreamingSlideshowState();

    // 백그라운드 스캔 시작
    final stream = _scanner.scanFolderStream(
      folderPath: folderPath,
      includeSubfolders: includeSubfolders,
    );

    _scanSubscription = stream.listen(
      _handleScanEvent,
      onError: (error) {
        _flushBatch(); // 남은 배치 처리
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
        _pendingImages.add(event.imagePath);

        // 첫 이미지는 즉시 처리 (사용자 경험)
        if (state.loadedImages.isEmpty && _pendingImages.length == 1) {
          _flushBatch();
          return;
        }

        // 배치 크기 도달 시 즉시 처리
        if (_pendingImages.length >= _batchSize) {
          _flushBatch();
        } else {
          _scheduleBatchFlush();
        }

      case ImageBatchEvent():
        // Isolate에서 배치로 전송된 경우
        _processBatch(event.paths);

      case ScanProgressEvent():
        state = state.copyWith(
          scannedFolders: event.foldersScanned,
          currentScanFolder: event.currentFolder,
        );

      case ScanCompleteEvent():
        // 남은 배치 처리
        _flushBatch();

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

        // 스캔 완료 후 최종 셔플 갱신
        if (!noImagesFound && _isRandomMode) {
          _reshuffleIndices();
        }

      case ScanErrorEvent():
        _flushBatch(); // 남은 배치 처리
        state = state.copyWith(
          isScanning: false,
          errorMessage: event.message,
        );
    }
  }

  /// 배치 플러시 예약
  void _scheduleBatchFlush() {
    _batchTimer?.cancel();
    _batchTimer = Timer(_batchDelay, _flushBatch);
  }

  /// 대기 중인 이미지 배치 처리
  void _flushBatch() {
    if (_pendingImages.isEmpty) return;

    _processBatch(_pendingImages);
    _pendingImages = [];
    _batchTimer?.cancel();
  }

  /// 이미지 배치 처리
  void _processBatch(List<String> paths) {
    if (paths.isEmpty) return;

    final isFirstBatch = state.loadedImages.isEmpty;
    final newImages = [...state.loadedImages, ...paths];

    state = state.copyWith(loadedImages: newImages);

    // 첫 이미지 배치가 추가된 경우
    if (isFirstBatch && state.isPlaying) {
      if (_isRandomMode) {
        // 랜덤 모드: 셔플 초기화
        _initializeShuffle();
      } else {
        // 순차 모드: 첫 이미지부터 시작
        state = state.copyWith(playHistory: [0]);
      }
      _startSlideTimer();
    } else if (_isRandomMode && state.shuffledIndices.isNotEmpty) {
      // 스캔 중 새 이미지 추가 → 증분 셔플
      _extendShuffle(state.shuffledIndices.length, newImages.length);
    }
  }

  /// 셔플 초기화 (첫 배치 시)
  void _initializeShuffle() {
    final totalImages = state.loadedImages.length;
    if (totalImages == 0) return;

    // 첫 이미지를 0번으로 시작
    final indices = List<int>.generate(totalImages, (i) => i);

    // Fisher-Yates 셔플 (0번은 현재 위치이므로 1번부터)
    for (int i = indices.length - 1; i > 1; i--) {
      final j = 1 + _random.nextInt(i);
      final temp = indices[i];
      indices[i] = indices[j];
      indices[j] = temp;
    }

    state = state.copyWith(
      shuffledIndices: indices,
      shufflePosition: 0,
      playHistory: [0],
    );
  }

  /// Fisher-Yates 셔플 (전체 리셔플)
  void _reshuffleIndices() {
    final totalImages = state.loadedImages.length;
    if (totalImages == 0) return;

    final indices = List<int>.generate(totalImages, (i) => i);

    // Fisher-Yates 셔플
    for (int i = indices.length - 1; i > 0; i--) {
      final j = _random.nextInt(i + 1);
      final temp = indices[i];
      indices[i] = indices[j];
      indices[j] = temp;
    }

    state = state.copyWith(
      shuffledIndices: indices,
      shufflePosition: 0,
    );
  }

  /// 새로 추가된 인덱스를 셔플에 포함 (증분 셔플)
  void _extendShuffle(int fromIndex, int toIndex) {
    if (fromIndex >= toIndex) return;

    final newIndices =
        List<int>.generate(toIndex - fromIndex, (i) => fromIndex + i);

    // 새 인덱스를 현재 위치 이후의 랜덤 위치에 삽입
    final currentPos = state.shufflePosition;
    final extendedShuffle = List<int>.from(state.shuffledIndices);

    for (final idx in newIndices) {
      // 현재 위치 이후에만 삽입
      final insertPos =
          currentPos + 1 + _random.nextInt(extendedShuffle.length - currentPos);
      extendedShuffle.insert(insertPos.clamp(0, extendedShuffle.length), idx);
    }

    state = state.copyWith(shuffledIndices: extendedShuffle);
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

  /// 랜덤 재생: 다음 이미지 (O(1) - Fisher-Yates 셔플 기반)
  void _nextRandomImage() {
    final totalImages = state.loadedImages.length;
    if (totalImages <= 1) return;

    // 셔플이 없으면 초기화
    if (state.shuffledIndices.isEmpty) {
      _reshuffleIndices();
    }

    final nextPosition = state.shufflePosition + 1;

    // 셔플 끝에 도달
    if (nextPosition >= state.shuffledIndices.length) {
      if (!state.isScanComplete) {
        // 스캔 중이면 대기 (새 이미지가 추가될 수 있음)
        return;
      }
      // 스캔 완료 → 리셔플 후 처음부터
      _reshuffleIndices();
    }

    final actualPosition = nextPosition >= state.shuffledIndices.length
        ? 0
        : nextPosition;
    final nextIndex = state.shuffledIndices[actualPosition];

    // 히스토리 업데이트 (크기 제한)
    var newHistory = [...state.playHistory, nextIndex];
    if (newHistory.length > _maxHistorySize) {
      newHistory = newHistory.sublist(newHistory.length - _maxHistorySize);
    }

    state = state.copyWith(
      currentIndex: nextIndex,
      shufflePosition: actualPosition,
      playHistory: newHistory,
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
    final newHistory =
        List<int>.from(state.playHistory)..removeLast();
    final prevIndex = newHistory.last;

    // 셔플 위치도 되돌림
    final newPosition =
        state.shufflePosition > 0 ? state.shufflePosition - 1 : 0;

    state = state.copyWith(
      currentIndex: prevIndex,
      shufflePosition: newPosition,
      playHistory: newHistory,
    );
  }

  /// 특정 인덱스로 이동
  void goToIndex(int index) {
    if (index >= 0 && index < state.loadedImages.length) {
      // 히스토리 업데이트 (크기 제한)
      var newHistory = [...state.playHistory, index];
      if (newHistory.length > _maxHistorySize) {
        newHistory = newHistory.sublist(newHistory.length - _maxHistorySize);
      }

      state = state.copyWith(
        currentIndex: index,
        playHistory: newHistory,
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
    _batchTimer?.cancel();
    super.dispose();
  }
}

/// StreamingMediaScanner Provider
final streamingMediaScannerProvider = Provider<StreamingMediaScanner>((ref) {
  return StreamingMediaScanner();
});

/// StreamingSlideshowController Provider
final streamingSlideshowControllerProvider = StateNotifierProvider.autoDispose<
    StreamingSlideshowController, StreamingSlideshowState>(
  (ref) {
    final scanner = ref.watch(streamingMediaScannerProvider);
    return StreamingSlideshowController(ref, scanner);
  },
);
