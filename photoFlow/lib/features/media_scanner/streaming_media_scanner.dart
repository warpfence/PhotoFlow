import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'media_scanner_service.dart';

/// 스트리밍 스캔 상태
enum StreamingScanState {
  idle,
  scanning,
  completed,
  error,
}

/// 스트리밍 스캔 이벤트
sealed class StreamingScanEvent {}

/// 이미지 발견 이벤트
class ImageFoundEvent extends StreamingScanEvent {
  final String imagePath;
  final int totalFound;

  ImageFoundEvent({required this.imagePath, required this.totalFound});
}

/// 스캔 진행 이벤트
class ScanProgressEvent extends StreamingScanEvent {
  final String currentFolder;
  final int foldersScanned;
  final int imagesFound;

  ScanProgressEvent({
    required this.currentFolder,
    required this.foldersScanned,
    required this.imagesFound,
  });
}

/// 스캔 완료 이벤트
class ScanCompleteEvent extends StreamingScanEvent {
  final int totalImages;
  final int totalFolders;

  ScanCompleteEvent({required this.totalImages, required this.totalFolders});
}

/// 스캔 에러 이벤트
class ScanErrorEvent extends StreamingScanEvent {
  final String message;
  final Object? error;

  ScanErrorEvent({required this.message, this.error});
}

/// 스트리밍 미디어 스캐너
///
/// 이미지를 발견하는 즉시 스트림으로 전달하여
/// 슬라이드쇼를 즉시 시작할 수 있게 합니다.
class StreamingMediaScanner {
  StreamingScanState _state = StreamingScanState.idle;
  StreamingScanState get state => _state;

  /// 폴더를 스트리밍 방식으로 스캔합니다.
  ///
  /// 이미지가 발견될 때마다 [ImageFoundEvent]를 yield합니다.
  /// 첫 이미지가 발견되면 즉시 슬라이드쇼를 시작할 수 있습니다.
  Stream<StreamingScanEvent> scanFolderStream({
    required String folderPath,
    bool includeSubfolders = true,
  }) async* {
    _state = StreamingScanState.scanning;

    final directory = Directory(folderPath);

    if (!await directory.exists()) {
      _state = StreamingScanState.error;
      yield ScanErrorEvent(message: '폴더를 찾을 수 없습니다: $folderPath');
      return;
    }

    int imagesFound = 0;
    int foldersScanned = 0;

    try {
      if (includeSubfolders) {
        // 재귀적 스캔
        await for (final event in _scanRecursive(
          directory: directory,
          imagesFound: imagesFound,
          foldersScanned: foldersScanned,
        )) {
          yield event;

          // 카운트 업데이트
          if (event is ImageFoundEvent) {
            imagesFound = event.totalFound;
          } else if (event is ScanProgressEvent) {
            foldersScanned = event.foldersScanned;
            imagesFound = event.imagesFound;
          }
        }
      } else {
        // 단일 폴더 스캔
        await for (final event in _scanSingleDirectory(
          directory: directory,
          imagesFound: imagesFound,
        )) {
          yield event;
          if (event is ImageFoundEvent) {
            imagesFound = event.totalFound;
          }
        }
        foldersScanned = 1;
      }

      _state = StreamingScanState.completed;
      yield ScanCompleteEvent(
        totalImages: imagesFound,
        totalFolders: foldersScanned,
      );
    } catch (e) {
      _state = StreamingScanState.error;
      yield ScanErrorEvent(message: '스캔 중 오류 발생', error: e);
    }
  }

  /// 단일 디렉토리 스캔
  Stream<StreamingScanEvent> _scanSingleDirectory({
    required Directory directory,
    required int imagesFound,
  }) async* {
    // 스캔 시작 진행 상태 이벤트
    yield ScanProgressEvent(
      currentFolder: directory.path,
      foldersScanned: 1,
      imagesFound: imagesFound,
    );

    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is File && _isImageFile(entity.path)) {
          imagesFound++;
          yield ImageFoundEvent(
            imagePath: entity.path,
            totalFound: imagesFound,
          );
        }
      }
    } on FileSystemException catch (e) {
      // 접근 권한 없는 폴더 - 사용자에게 에러 알림
      print('폴더 접근 오류: ${e.path} - ${e.message}');
      yield ScanErrorEvent(
        message: '폴더에 접근할 수 없습니다.\n권한을 확인해 주세요.\n\n경로: ${e.path}',
        error: e,
      );
    }
  }

  /// 재귀적 디렉토리 스캔
  Stream<StreamingScanEvent> _scanRecursive({
    required Directory directory,
    required int imagesFound,
    required int foldersScanned,
  }) async* {
    try {
      final entities = await directory.list(followLinks: false).toList();

      // 현재 폴더의 이미지 먼저 처리
      for (final entity in entities) {
        if (entity is File && _isImageFile(entity.path)) {
          imagesFound++;
          yield ImageFoundEvent(
            imagePath: entity.path,
            totalFound: imagesFound,
          );
        }
      }

      foldersScanned++;
      yield ScanProgressEvent(
        currentFolder: directory.path,
        foldersScanned: foldersScanned,
        imagesFound: imagesFound,
      );

      // 하위 디렉토리 재귀 탐색
      for (final entity in entities) {
        if (entity is Directory) {
          final folderName = p.basename(entity.path);
          // 숨김 폴더 제외
          if (!folderName.startsWith('.')) {
            await for (final event in _scanRecursive(
              directory: entity,
              imagesFound: imagesFound,
              foldersScanned: foldersScanned,
            )) {
              yield event;

              // 카운트 업데이트
              if (event is ImageFoundEvent) {
                imagesFound = event.totalFound;
              } else if (event is ScanProgressEvent) {
                foldersScanned = event.foldersScanned;
                imagesFound = event.imagesFound;
              }
            }
          }
        }
      }
    } on FileSystemException catch (e) {
      // 폴더 접근 에러 - 해당 폴더는 건너뛰지만 진행 상태는 업데이트
      print('폴더 접근 오류: ${e.path} - ${e.message}');
      foldersScanned++;
      yield ScanProgressEvent(
        currentFolder: '${directory.path} (접근 불가)',
        foldersScanned: foldersScanned,
        imagesFound: imagesFound,
      );
    }
  }

  /// 파일이 지원하는 이미지 형식인지 확인
  bool _isImageFile(String filePath) {
    final extension = p.extension(filePath).toLowerCase();
    return supportedImageExtensions.contains(extension);
  }
}
