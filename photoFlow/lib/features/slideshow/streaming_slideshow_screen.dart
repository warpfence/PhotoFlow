import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

import '../settings/settings_provider.dart';
import 'streaming_slideshow_controller.dart';

/// 스트리밍 슬라이드쇼 화면
///
/// 폴더 선택 후 즉시 슬라이드쇼를 시작합니다.
/// 백그라운드에서 이미지를 스캔하면서 동시에 슬라이드쇼를 진행합니다.
class StreamingSlideshowScreen extends ConsumerStatefulWidget {
  final String folderPath;
  final bool includeSubfolders;

  const StreamingSlideshowScreen({
    super.key,
    required this.folderPath,
    this.includeSubfolders = true,
  });

  @override
  ConsumerState<StreamingSlideshowScreen> createState() =>
      _StreamingSlideshowScreenState();
}

class _StreamingSlideshowScreenState
    extends ConsumerState<StreamingSlideshowScreen> {
  bool _showControls = true;
  bool _isFullScreen = false;
  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();

    // 절전 모드 방지 활성화
    WakelockPlus.enable();

    // 스트리밍 슬라이드쇼 시작
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(streamingSlideshowControllerProvider.notifier).startStreaming(
            folderPath: widget.folderPath,
            includeSubfolders: widget.includeSubfolders,
          );
      _checkFullScreenState();
    });

    _startHideControlsTimer();
  }

  Future<void> _checkFullScreenState() async {
    _isFullScreen = await windowManager.isFullScreen();
    if (mounted) setState(() {});
  }

  Future<void> _toggleFullScreen() async {
    _isFullScreen = !_isFullScreen;
    await windowManager.setFullScreen(_isFullScreen);
    setState(() {});
    _showControlsTemporarily();
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() => _showControls = false);
      }
    });
  }

  void _showControlsTemporarily() {
    setState(() => _showControls = true);
    _startHideControlsTimer();
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    // 절전 모드 방지 해제
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slideshowState = ref.watch(streamingSlideshowControllerProvider);
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: KeyboardListener(
        focusNode: FocusNode()..requestFocus(),
        onKeyEvent: _handleKeyEvent,
        child: MouseRegion(
          onHover: (_) => _showControlsTemporarily(),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _showControlsTemporarily,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 이미지 또는 로딩/에러 상태
                _buildMainContent(slideshowState, settings),

                // 스캔 진행 상태 표시 (상단)
                if (slideshowState.isScanning)
                  _buildScanningIndicator(slideshowState),

                // 시계 오버레이
                if (settings.showClock && slideshowState.hasImages)
                  _buildClockOverlay(settings),

                // 사진 정보 오버레이
                if ((settings.showFileName || settings.showDate) &&
                    slideshowState.hasImages)
                  _buildInfoOverlay(slideshowState, settings),

                // 컨트롤 오버레이 (이미지가 있을 때만 표시)
                if (_showControls && slideshowState.hasImages)
                  _buildControlsOverlay(slideshowState),

                // 에러/로딩 상태에서 닫기 버튼만 표시
                if (!slideshowState.hasImages) _buildCloseButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent(
      StreamingSlideshowState slideshowState, SettingsState settings) {
    // 에러 상태
    if (slideshowState.errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            Text(
              slideshowState.errorMessage!,
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _exitSlideshow,
              child: const Text('돌아가기'),
            ),
          ],
        ),
      );
    }

    // 아직 이미지가 없는 경우 (스캔 중)
    if (!slideshowState.hasImages) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 24),
            Text(
              slideshowState.isScanning ? '이미지 스캔 중...' : '이미지를 찾는 중...',
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 8),
            // 스캔 진행 상태 표시
            if (slideshowState.scannedFolders > 0)
              Text(
                '${slideshowState.scannedFolders}개 폴더 스캔됨',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            if (slideshowState.currentScanFolder != null) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  p.basename(slideshowState.currentScanFolder!),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
      );
    }

    // 이미지 표시
    return _buildImage(slideshowState.currentImagePath!, settings);
  }

  Widget _buildImage(String path, SettingsState settings) {
    Widget imageWidget = Image.file(
      File(path),
      fit: BoxFit.contain,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (context, error, stackTrace) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.broken_image, color: Colors.white54, size: 64),
              const SizedBox(height: 16),
              const Text(
                '이미지를 불러올 수 없습니다',
                style: TextStyle(color: Colors.white54),
              ),
            ],
          ),
        );
      },
    );

    // 트랜지션 효과 적용
    switch (settings.transitionEffect) {
      case TransitionEffect.fade:
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          child: Container(
            key: ValueKey(path),
            child: imageWidget,
          ),
        );
      case TransitionEffect.slide:
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          transitionBuilder: (child, animation) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            );
          },
          child: Container(
            key: ValueKey(path),
            child: imageWidget,
          ),
        );
      case TransitionEffect.none:
        return imageWidget;
    }
  }

  Widget _buildScanningIndicator(StreamingSlideshowState slideshowState) {
    return Positioned(
      top: 16,
      left: 16,
      child: AnimatedOpacity(
        opacity: _showControls ? 1.0 : 0.5,
        duration: const Duration(milliseconds: 300),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '스캔 중: ${slideshowState.totalImages}장',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClockOverlay(SettingsState settings) {
    return Positioned(
      left: _getClockLeft(settings.clockPosition),
      right: _getClockRight(settings.clockPosition),
      top: _getClockTop(settings.clockPosition),
      bottom: _getClockBottom(settings.clockPosition),
      child: _ClockWidget(position: settings.clockPosition),
    );
  }

  double? _getClockLeft(ClockPosition position) {
    switch (position) {
      case ClockPosition.topLeft:
      case ClockPosition.bottomLeft:
        return 24;
      case ClockPosition.bottomCenter:
        return null;
      default:
        return null;
    }
  }

  double? _getClockRight(ClockPosition position) {
    switch (position) {
      case ClockPosition.topRight:
      case ClockPosition.bottomRight:
        return 24;
      default:
        return null;
    }
  }

  double? _getClockTop(ClockPosition position) {
    switch (position) {
      case ClockPosition.topLeft:
      case ClockPosition.topRight:
        return 24;
      default:
        return null;
    }
  }

  double? _getClockBottom(ClockPosition position) {
    switch (position) {
      case ClockPosition.bottomLeft:
      case ClockPosition.bottomRight:
      case ClockPosition.bottomCenter:
        return 24;
      default:
        return null;
    }
  }

  Widget _buildInfoOverlay(
      StreamingSlideshowState slideshowState, SettingsState settings) {
    final currentPath = slideshowState.currentImagePath;
    if (currentPath == null) return const SizedBox.shrink();

    final fileName = p.basename(currentPath);

    return Positioned(
      left: 24,
      right: 24,
      bottom: settings.showClock &&
              (settings.clockPosition == ClockPosition.bottomLeft ||
                  settings.clockPosition == ClockPosition.bottomRight ||
                  settings.clockPosition == ClockPosition.bottomCenter)
          ? 80
          : 24,
      child: AnimatedOpacity(
        opacity: _showControls ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (settings.showFileName)
                Text(
                  fileName,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              if (settings.showDate)
                Text(
                  slideshowState.isScanComplete
                      ? '${slideshowState.currentIndex + 1} / ${slideshowState.totalImages}'
                      : '${slideshowState.currentIndex + 1} / ${slideshowState.totalImages}+',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlsOverlay(StreamingSlideshowState slideshowState) {
    final controller = ref.read(streamingSlideshowControllerProvider.notifier);

    return AnimatedOpacity(
      opacity: _showControls ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black54,
              Colors.transparent,
              Colors.transparent,
              Colors.black54,
            ],
            stops: const [0.0, 0.15, 0.85, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // 상단 우측 버튼들
            Positioned(
              top: 16,
              right: 16,
              child: Row(
                children: [
                  // 전체 화면 버튼
                  IconButton(
                    icon: Icon(
                      _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                      color: Colors.white,
                      size: 28,
                    ),
                    tooltip: _isFullScreen ? '전체 화면 종료 (F)' : '전체 화면 (F)',
                    onPressed: _toggleFullScreen,
                  ),
                  const SizedBox(width: 8),
                  // 닫기 버튼
                  IconButton(
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 32),
                    tooltip: '닫기 (ESC)',
                    onPressed: _exitSlideshow,
                  ),
                ],
              ),
            ),

            // 중앙 컨트롤
            if (slideshowState.hasImages)
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.skip_previous,
                          color: Colors.white, size: 48),
                      onPressed: () {
                        controller.previousImage();
                        _showControlsTemporarily();
                      },
                    ),
                    const SizedBox(width: 24),
                    IconButton(
                      icon: Icon(
                        slideshowState.isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                        color: Colors.white,
                        size: 64,
                      ),
                      onPressed: () {
                        controller.togglePlayPause();
                        _showControlsTemporarily();
                      },
                    ),
                    const SizedBox(width: 24),
                    IconButton(
                      icon: const Icon(Icons.skip_next,
                          color: Colors.white, size: 48),
                      onPressed: () {
                        controller.nextImage();
                        _showControlsTemporarily();
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 에러/로딩 상태에서 표시되는 닫기 버튼
  Widget _buildCloseButton() {
    return Positioned(
      top: 16,
      right: 16,
      child: IconButton(
        icon: const Icon(Icons.close, color: Colors.white, size: 32),
        tooltip: '닫기 (ESC)',
        onPressed: _exitSlideshow,
      ),
    );
  }

  /// 슬라이드쇼 종료 (전체화면 해제 후 돌아가기)
  Future<void> _exitSlideshow() async {
    if (_isFullScreen) {
      await windowManager.setFullScreen(false);
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      final controller =
          ref.read(streamingSlideshowControllerProvider.notifier);

      switch (event.logicalKey) {
        case LogicalKeyboardKey.space:
          controller.togglePlayPause();
          _showControlsTemporarily();
          break;
        case LogicalKeyboardKey.arrowLeft:
          controller.previousImage();
          _showControlsTemporarily();
          break;
        case LogicalKeyboardKey.arrowRight:
          controller.nextImage();
          _showControlsTemporarily();
          break;
        case LogicalKeyboardKey.keyF:
          _toggleFullScreen();
          break;
        case LogicalKeyboardKey.escape:
          _exitSlideshow();
          break;
      }
    }
  }
}

class _ClockWidget extends StatefulWidget {
  final ClockPosition position;

  const _ClockWidget({required this.position});

  @override
  State<_ClockWidget> createState() => _ClockWidgetState();
}

class _ClockWidgetState extends State<_ClockWidget> {
  late Timer _timer;
  late String _time;

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
  }

  void _updateTime() {
    setState(() {
      _time = DateFormat('HH:mm:ss').format(DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _time,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w300,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}
