import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

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

/// 이미지 배치 발견 이벤트 (Isolate에서 배치 전송용)
class ImageBatchEvent extends StreamingScanEvent {
  final List<String> paths;
  final int totalFound;

  ImageBatchEvent({required this.paths, required this.totalFound});
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

/// Isolate 스캔 요청 메시지
class _IsolateScanRequest {
  final String folderPath;
  final bool includeSubfolders;
  final SendPort sendPort;

  _IsolateScanRequest({
    required this.folderPath,
    required this.includeSubfolders,
    required this.sendPort,
  });
}

/// Isolate 스캔 응답 타입
enum _IsolateEventType {
  imageBatch,
  progress,
  complete,
  error,
}

/// Isolate에서 메인으로 보내는 메시지
class _IsolateMessage {
  final _IsolateEventType type;
  final dynamic data;

  _IsolateMessage(this.type, this.data);
}

/// Isolate에서 실행되는 스캔 함수 (Top-level 함수)
Future<void> _isolateScanFunction(_IsolateScanRequest request) async {
  final sendPort = request.sendPort;
  final directory = Directory(request.folderPath);

  if (!await directory.exists()) {
    sendPort.send(_IsolateMessage(
      _IsolateEventType.error,
      {'message': '폴더를 찾을 수 없습니다: ${request.folderPath}'},
    ));
    return;
  }

  int imagesFound = 0;
  int foldersScanned = 0;
  List<String> imageBatch = [];
  const batchSize = 100;

  // 배치 전송 함수
  void flushBatch() {
    if (imageBatch.isNotEmpty) {
      sendPort.send(_IsolateMessage(
        _IsolateEventType.imageBatch,
        {'paths': List<String>.from(imageBatch), 'totalFound': imagesFound},
      ));
      imageBatch.clear();
    }
  }

  // 진행 상태 전송 함수 (100폴더마다 또는 중요 시점에)
  void sendProgress(String folder) {
    if (foldersScanned % 100 == 0 || foldersScanned == 1) {
      sendPort.send(_IsolateMessage(
        _IsolateEventType.progress,
        {
          'currentFolder': folder,
          'foldersScanned': foldersScanned,
          'imagesFound': imagesFound,
        },
      ));
    }
  }

  try {
    if (request.includeSubfolders) {
      // 재귀적 스캔
      await _scanRecursiveIsolate(
        directory: directory,
        onImageFound: (path) {
          imagesFound++;
          imageBatch.add(path);
          if (imageBatch.length >= batchSize) {
            flushBatch();
          }
        },
        onFolderScanned: (folder) {
          foldersScanned++;
          sendProgress(folder);
        },
      );
    } else {
      // 단일 폴더 스캔
      await _scanSingleDirectoryIsolate(
        directory: directory,
        onImageFound: (path) {
          imagesFound++;
          imageBatch.add(path);
          if (imageBatch.length >= batchSize) {
            flushBatch();
          }
        },
      );
      foldersScanned = 1;
      sendProgress(directory.path);
    }

    // 남은 배치 전송
    flushBatch();

    // 완료 이벤트
    sendPort.send(_IsolateMessage(
      _IsolateEventType.complete,
      {'totalImages': imagesFound, 'totalFolders': foldersScanned},
    ));
  } catch (e) {
    // 에러 이벤트
    sendPort.send(_IsolateMessage(
      _IsolateEventType.error,
      {'message': '스캔 중 오류 발생: $e'},
    ));
  }
}

/// Isolate용 단일 디렉토리 스캔
Future<void> _scanSingleDirectoryIsolate({
  required Directory directory,
  required void Function(String path) onImageFound,
}) async {
  try {
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File && _isImageFileIsolate(entity.path)) {
        onImageFound(entity.path);
      }
    }
  } on FileSystemException catch (e) {
    // 접근 권한 없는 폴더는 무시
    print('폴더 접근 오류 (무시됨): ${e.path}');
  }
}

/// Isolate용 재귀적 디렉토리 스캔
Future<void> _scanRecursiveIsolate({
  required Directory directory,
  required void Function(String path) onImageFound,
  required void Function(String folder) onFolderScanned,
}) async {
  try {
    // 스트림으로 처리하여 메모리 효율성 향상
    final List<Directory> subdirectories = [];

    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File && _isImageFileIsolate(entity.path)) {
        onImageFound(entity.path);
      } else if (entity is Directory) {
        final folderName = p.basename(entity.path);
        // 숨김 폴더 제외
        if (!folderName.startsWith('.')) {
          subdirectories.add(entity);
        }
      }
    }

    onFolderScanned(directory.path);

    // 하위 디렉토리 재귀 탐색
    for (final subdir in subdirectories) {
      await _scanRecursiveIsolate(
        directory: subdir,
        onImageFound: onImageFound,
        onFolderScanned: onFolderScanned,
      );
    }
  } on FileSystemException catch (e) {
    // 접근 권한 없는 폴더는 무시하고 계속 진행
    print('폴더 접근 오류 (무시됨): ${e.path}');
    onFolderScanned('${directory.path} (접근 불가)');
  }
}

/// Isolate용 이미지 파일 확인
bool _isImageFileIsolate(String filePath) {
  final extension = p.extension(filePath).toLowerCase();
  // supportedImageExtensions를 직접 정의 (Isolate에서는 import된 상수 사용 불가할 수 있음)
  const extensions = {'.jpg', '.jpeg', '.png', '.gif', '.webp'};
  return extensions.contains(extension);
}

/// 스트리밍 미디어 스캐너
///
/// 이미지를 발견하는 즉시 스트림으로 전달하여
/// 슬라이드쇼를 즉시 시작할 수 있게 합니다.
/// Isolate를 사용하여 메인 스레드 블로킹을 방지합니다.
class StreamingMediaScanner {
  StreamingScanState _state = StreamingScanState.idle;
  StreamingScanState get state => _state;

  Isolate? _scanIsolate;
  ReceivePort? _receivePort;

  /// 폴더를 스트리밍 방식으로 스캔합니다.
  ///
  /// Isolate에서 스캔을 수행하여 메인 스레드를 블로킹하지 않습니다.
  /// 이미지가 발견될 때마다 배치로 [ImageBatchEvent]를 yield합니다.
  Stream<StreamingScanEvent> scanFolderStream({
    required String folderPath,
    bool includeSubfolders = true,
  }) async* {
    _state = StreamingScanState.scanning;

    // 이전 Isolate 정리
    _cleanup();

    _receivePort = ReceivePort();

    try {
      // Isolate 생성 및 시작
      _scanIsolate = await Isolate.spawn(
        _isolateScanFunction,
        _IsolateScanRequest(
          folderPath: folderPath,
          includeSubfolders: includeSubfolders,
          sendPort: _receivePort!.sendPort,
        ),
      );

      // Isolate로부터 메시지 수신
      await for (final message in _receivePort!) {
        if (message is _IsolateMessage) {
          final event = _convertToEvent(message);
          if (event != null) {
            yield event;

            // 완료 또는 에러 시 루프 종료
            if (event is ScanCompleteEvent) {
              _state = StreamingScanState.completed;
              break;
            } else if (event is ScanErrorEvent) {
              _state = StreamingScanState.error;
              break;
            }
          }
        }
      }
    } catch (e) {
      _state = StreamingScanState.error;
      yield ScanErrorEvent(message: 'Isolate 스캔 오류: $e', error: e);
    } finally {
      _cleanup();
    }
  }

  /// Isolate 메시지를 이벤트로 변환
  StreamingScanEvent? _convertToEvent(_IsolateMessage message) {
    switch (message.type) {
      case _IsolateEventType.imageBatch:
        final data = message.data as Map<String, dynamic>;
        return ImageBatchEvent(
          paths: List<String>.from(data['paths'] as List),
          totalFound: data['totalFound'] as int,
        );

      case _IsolateEventType.progress:
        final data = message.data as Map<String, dynamic>;
        return ScanProgressEvent(
          currentFolder: data['currentFolder'] as String,
          foldersScanned: data['foldersScanned'] as int,
          imagesFound: data['imagesFound'] as int,
        );

      case _IsolateEventType.complete:
        final data = message.data as Map<String, dynamic>;
        return ScanCompleteEvent(
          totalImages: data['totalImages'] as int,
          totalFolders: data['totalFolders'] as int,
        );

      case _IsolateEventType.error:
        final data = message.data as Map<String, dynamic>;
        return ScanErrorEvent(message: data['message'] as String);
    }
  }

  /// 스캔 중단 및 리소스 정리
  void cancelScan() {
    _cleanup();
    _state = StreamingScanState.idle;
  }

  /// 리소스 정리
  void _cleanup() {
    _scanIsolate?.kill(priority: Isolate.immediate);
    _scanIsolate = null;
    _receivePort?.close();
    _receivePort = null;
  }

}
