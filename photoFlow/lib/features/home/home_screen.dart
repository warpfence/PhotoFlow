import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
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

  @override
  Widget build(BuildContext context) {
    final selectedPath = ref.watch(selectedFolderPathProvider);
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('PhotoFlow'),
        actions: [
          // 전체 화면 버튼
          IconButton(
            icon: Icon(_isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen),
            tooltip: _isFullScreen ? '전체 화면 종료' : '전체 화면',
            onPressed: _toggleFullScreen,
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
