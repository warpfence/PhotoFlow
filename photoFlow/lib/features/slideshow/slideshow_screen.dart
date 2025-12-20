import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../settings/settings_provider.dart';

class SlideshowScreen extends ConsumerStatefulWidget {
  final List<String> imagePaths;

  const SlideshowScreen({super.key, required this.imagePaths});

  @override
  ConsumerState<SlideshowScreen> createState() => _SlideshowScreenState();
}

class _SlideshowScreenState extends ConsumerState<SlideshowScreen> {
  late List<String> _orderedPaths;
  int _currentIndex = 0;
  bool _isPlaying = true;
  bool _showControls = true;
  Timer? _slideTimer;
  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();
    _initializeSlideshow();
  }

  void _initializeSlideshow() {
    final settings = ref.read(settingsProvider);

    // 재생 순서에 따라 이미지 목록 정렬
    _orderedPaths = List.from(widget.imagePaths);
    if (settings.playOrder == PlayOrder.random) {
      _orderedPaths.shuffle(Random());
    }

    _startSlideTimer();
    _startHideControlsTimer();
  }

  void _startSlideTimer() {
    _slideTimer?.cancel();
    if (_isPlaying) {
      final settings = ref.read(settingsProvider);
      _slideTimer = Timer.periodic(
        Duration(seconds: settings.slideInterval.seconds),
        (_) => _nextImage(),
      );
    }
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _showControls = false);
      }
    });
  }

  void _showControlsTemporarily() {
    setState(() => _showControls = true);
    _startHideControlsTimer();
  }

  void _nextImage() {
    setState(() {
      _currentIndex = (_currentIndex + 1) % _orderedPaths.length;
    });
  }

  void _previousImage() {
    setState(() {
      _currentIndex = (_currentIndex - 1 + _orderedPaths.length) % _orderedPaths.length;
    });
  }

  void _togglePlayPause() {
    setState(() {
      _isPlaying = !_isPlaying;
      if (_isPlaying) {
        _startSlideTimer();
      } else {
        _slideTimer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _slideTimer?.cancel();
    _hideControlsTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final currentPath = _orderedPaths[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      body: KeyboardListener(
        focusNode: FocusNode()..requestFocus(),
        onKeyEvent: _handleKeyEvent,
        child: MouseRegion(
          onHover: (_) => _showControlsTemporarily(),
          child: GestureDetector(
            onTap: _showControlsTemporarily,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 이미지
                _buildImage(currentPath, settings),

                // 시계 오버레이
                if (settings.showClock) _buildClockOverlay(settings),

                // 사진 정보 오버레이
                if (settings.showFileName || settings.showDate)
                  _buildInfoOverlay(currentPath, settings),

                // 컨트롤 오버레이
                if (_showControls) _buildControlsOverlay(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImage(String path, SettingsState settings) {
    Widget imageWidget = Image.file(
      File(path),
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.broken_image, color: Colors.white54, size: 64),
              const SizedBox(height: 16),
              Text(
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

  Widget _buildInfoOverlay(String path, SettingsState settings) {
    final fileName = p.basename(path);

    return Positioned(
      left: 24,
      right: 24,
      bottom: settings.showClock &&
              (settings.clockPosition == ClockPosition.bottomLeft ||
                  settings.clockPosition == ClockPosition.bottomRight ||
                  settings.clockPosition == ClockPosition.bottomCenter)
          ? 80
          : 24,
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
                '${_currentIndex + 1} / ${_orderedPaths.length}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsOverlay() {
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
            // 닫기 버튼
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => Navigator.pop(context),
              ),
            ),

            // 중앙 컨트롤
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.skip_previous, color: Colors.white, size: 48),
                    onPressed: _previousImage,
                  ),
                  const SizedBox(width: 24),
                  IconButton(
                    icon: Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 64,
                    ),
                    onPressed: _togglePlayPause,
                  ),
                  const SizedBox(width: 24),
                  IconButton(
                    icon: const Icon(Icons.skip_next, color: Colors.white, size: 48),
                    onPressed: _nextImage,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.space:
          _togglePlayPause();
          _showControlsTemporarily();
          break;
        case LogicalKeyboardKey.arrowLeft:
          _previousImage();
          _showControlsTemporarily();
          break;
        case LogicalKeyboardKey.arrowRight:
          _nextImage();
          _showControlsTemporarily();
          break;
        case LogicalKeyboardKey.escape:
          Navigator.pop(context);
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
