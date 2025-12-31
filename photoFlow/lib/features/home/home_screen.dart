import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../media_scanner/media_scanner_provider.dart';
import '../settings/settings_provider.dart';
import '../settings/settings_screen.dart';
import '../slideshow/streaming_slideshow_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isFullScreen = false;

  @override
  void initState() {
    super.initState();
    _checkFullScreenState();
    // 저장된 폴더 경로 접근 가능 여부 확인
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _validateSavedFolderPath();
    });
  }

  /// 저장된 폴더 경로가 접근 가능한지 확인
  Future<void> _validateSavedFolderPath() async {
    final savedPath = ref.read(selectedFolderPathProvider);
    if (savedPath == null) return;

    final directory = Directory(savedPath);

    try {
      // 폴더 존재 여부 및 접근 가능 여부 확인
      if (!await directory.exists()) {
        await _clearInvalidPath('폴더가 존재하지 않습니다');
        return;
      }

      // 폴더 내용 읽기 시도 (접근 권한 확인)
      await directory.list().first.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw Exception('접근 시간 초과'),
      );
    } on FileSystemException {
      // 접근 권한 없음
      await _clearInvalidPath('폴더 접근 권한이 없습니다');
    } catch (e) {
      // 기타 오류 (빈 폴더 등은 무시)
      if (e.toString().contains('No element')) {
        // 빈 폴더 - 정상
        return;
      }
      await _clearInvalidPath('폴더에 접근할 수 없습니다');
    }
  }

  /// 유효하지 않은 경로 초기화 및 사용자 알림
  Future<void> _clearInvalidPath(String reason) async {
    await ref.read(selectedFolderPathProvider.notifier).set(null);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('저장된 폴더 경로가 초기화되었습니다.\n$reason\n폴더를 다시 선택해 주세요.'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _checkFullScreenState() async {
    _isFullScreen = await windowManager.isFullScreen();
    if (mounted) setState(() {});
  }

  Future<void> _toggleFullScreen() async {
    _isFullScreen = !_isFullScreen;
    await windowManager.setFullScreen(_isFullScreen);
    setState(() {});
  }

  /// 키보드 단축키 안내 팝업창 표시
  void _showKeyboardShortcutsDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 헤더
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.keyboard,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '키보드 단축키',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                      tooltip: '닫기',
                    ),
                  ],
                ),
              ),
              // 단축키 목록
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 공통 단축키
                    Text(
                      '공통',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    _buildShortcutRow(context, 'F', '전체 화면 전환'),
                    const SizedBox(height: 20),
                    // 슬라이드쇼 단축키
                    Text(
                      '슬라이드쇼 재생 중',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    _buildShortcutRow(context, 'Space', '재생 / 일시정지'),
                    _buildShortcutRow(context, '←', '이전 이미지'),
                    _buildShortcutRow(context, '→', '다음 이미지'),
                    _buildShortcutRow(context, 'ESC', '슬라이드쇼 종료'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 단축키 행 위젯 생성
  Widget _buildShortcutRow(BuildContext context, String key, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              key,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            description,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  /// 키보드 이벤트 처리
  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.keyF:
          _toggleFullScreen();
          break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedPath = ref.watch(selectedFolderPathProvider);
    final settings = ref.watch(settingsProvider);

    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/app_icon.png',
              width: 28,
              height: 28,
            ),
            const SizedBox(width: 10),
            const Text('PhotoFlow'),
          ],
        ),
        actions: [
          // 전체 화면 버튼
          IconButton(
            icon: Icon(_isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen),
            tooltip: _isFullScreen ? '전체 화면 종료' : '전체 화면',
            onPressed: _toggleFullScreen,
          ),
          // 정보 버튼 (키보드 단축키 안내)
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: '키보드 단축키',
            onPressed: () => _showKeyboardShortcutsDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '설정',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 폴더 경로 표시
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.folder_open,
                      size: 48,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      selectedPath ?? '폴더를 선택하세요',
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    if (settings.includeSubfolders)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '(하위 폴더 포함)',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // 버튼들
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () => _selectFolder(context, ref),
                    icon: const Icon(Icons.folder_open),
                    label: const Text('폴더 선택'),
                  ),
                  const SizedBox(width: 16),
                  FilledButton.icon(
                    onPressed: selectedPath != null
                        ? () => _startSlideshow(context, ref)
                        : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('슬라이드쇼 시작'),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // 재생 모드 표시
              if (selectedPath != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        settings.playOrder == PlayOrder.random
                            ? Icons.shuffle
                            : Icons.format_list_numbered,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSecondaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        settings.playOrder == PlayOrder.random ? '랜덤 재생' : '순서대로 재생',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSecondaryContainer,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Future<void> _selectFolder(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.getDirectoryPath();

    if (result != null) {
      // 폴더 경로만 저장 (스캔은 슬라이드쇼 시작 시 진행)
      await ref.read(selectedFolderPathProvider.notifier).set(result);
    }
  }

  /// 슬라이드쇼 시작 (스트리밍 방식 - 즉시 시작)
  Future<void> _startSlideshow(BuildContext context, WidgetRef ref) async {
    final selectedPath = ref.read(selectedFolderPathProvider);
    if (selectedPath == null) return;

    // 폴더 존재 여부 확인
    final directory = Directory(selectedPath);
    if (!await directory.exists()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('폴더를 찾을 수 없습니다: $selectedPath'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: '폴더 다시 선택',
              textColor: Colors.white,
              onPressed: () => _selectFolder(context, ref),
            ),
          ),
        );
      }
      return;
    }

    final settings = ref.read(settingsProvider);

    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StreamingSlideshowScreen(
            folderPath: selectedPath,
            includeSubfolders: settings.includeSubfolders,
          ),
        ),
      );
    }
  }
}
