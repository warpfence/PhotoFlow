import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// 지원하는 이미지 확장자 목록
const supportedImageExtensions = {
  '.jpg',
  '.jpeg',
  '.png',
  '.gif',
  '.webp',
};

/// 스캔 진행 상황을 나타내는 클래스
class ScanProgress {
  final int foundImages;
  final int scannedFolders;
  final bool isComplete;
  final String? currentPath;

  const ScanProgress({
    required this.foundImages,
    required this.scannedFolders,
    this.isComplete = false,
    this.currentPath,
  });

  ScanProgress copyWith({
    int? foundImages,
    int? scannedFolders,
    bool? isComplete,
    String? currentPath,
  }) {
    return ScanProgress(
      foundImages: foundImages ?? this.foundImages,
      scannedFolders: scannedFolders ?? this.scannedFolders,
      isComplete: isComplete ?? this.isComplete,
      currentPath: currentPath ?? this.currentPath,
    );
  }
}

/// 스캔 결과를 나타내는 클래스
class ScanResult {
  final List<String> imagePaths;
  final int folderCount;
  final String rootPath;

  const ScanResult({
    required this.imagePaths,
    required this.folderCount,
    required this.rootPath,
  });

  int get imageCount => imagePaths.length;

  bool get isEmpty => imagePaths.isEmpty;
}

/// 이미지 스캐너 서비스
///
/// 지정된 폴더에서 이미지 파일을 검색합니다.
/// [includeSubfolders]가 true이면 하위 폴더를 재귀적으로 탐색합니다.
class MediaScannerService {
  /// 폴더에서 이미지를 스캔합니다.
  ///
  /// [folderPath]: 스캔할 폴더 경로
  /// [includeSubfolders]: 하위 폴더 포함 여부 (기본값: true)
  /// [onProgress]: 스캔 진행 상황 콜백
  Future<ScanResult> scanFolder({
    required String folderPath,
    bool includeSubfolders = true,
    void Function(ScanProgress)? onProgress,
  }) async {
    final directory = Directory(folderPath);

    if (!await directory.exists()) {
      throw ScanException('폴더를 찾을 수 없습니다: $folderPath');
    }

    final imagePaths = <String>[];
    var scannedFolders = 0;

    if (includeSubfolders) {
      // 재귀적으로 하위 폴더 탐색
      await _scanDirectoryRecursive(
        directory: directory,
        imagePaths: imagePaths,
        onFolderScanned: () {
          scannedFolders++;
          onProgress?.call(ScanProgress(
            foundImages: imagePaths.length,
            scannedFolders: scannedFolders,
            currentPath: directory.path,
          ));
        },
        onProgress: onProgress,
      );
    } else {
      // 현재 폴더만 스캔
      await _scanSingleDirectory(
        directory: directory,
        imagePaths: imagePaths,
      );
      scannedFolders = 1;
    }

    // 완료 알림
    onProgress?.call(ScanProgress(
      foundImages: imagePaths.length,
      scannedFolders: scannedFolders,
      isComplete: true,
    ));

    return ScanResult(
      imagePaths: imagePaths,
      folderCount: scannedFolders,
      rootPath: folderPath,
    );
  }

  /// 단일 디렉토리에서 이미지 파일만 검색
  Future<void> _scanSingleDirectory({
    required Directory directory,
    required List<String> imagePaths,
  }) async {
    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is File && _isImageFile(entity.path)) {
          imagePaths.add(entity.path);
        }
      }
    } on FileSystemException catch (e) {
      // 접근 권한이 없는 폴더는 무시
      print('폴더 접근 오류 (무시됨): ${e.path} - ${e.message}');
    }
  }

  /// 디렉토리를 재귀적으로 탐색하여 이미지 파일 검색
  Future<void> _scanDirectoryRecursive({
    required Directory directory,
    required List<String> imagePaths,
    required void Function() onFolderScanned,
    void Function(ScanProgress)? onProgress,
  }) async {
    try {
      final entities = await directory.list(followLinks: false).toList();

      // 먼저 현재 디렉토리의 파일 처리
      for (final entity in entities) {
        if (entity is File && _isImageFile(entity.path)) {
          imagePaths.add(entity.path);
        }
      }

      onFolderScanned();

      // 진행 상황 업데이트
      onProgress?.call(ScanProgress(
        foundImages: imagePaths.length,
        scannedFolders: 0,
        currentPath: directory.path,
      ));

      // 하위 디렉토리 재귀 탐색
      for (final entity in entities) {
        if (entity is Directory) {
          // 숨김 폴더 제외 (. 으로 시작하는 폴더)
          final folderName = p.basename(entity.path);
          if (!folderName.startsWith('.')) {
            await _scanDirectoryRecursive(
              directory: entity,
              imagePaths: imagePaths,
              onFolderScanned: onFolderScanned,
              onProgress: onProgress,
            );
          }
        }
      }
    } on FileSystemException catch (e) {
      // 접근 권한이 없는 폴더는 무시하고 계속 진행
      print('폴더 접근 오류 (무시됨): ${e.path} - ${e.message}');
    }
  }

  /// 파일이 지원하는 이미지 형식인지 확인
  bool _isImageFile(String filePath) {
    final extension = p.extension(filePath).toLowerCase();
    return supportedImageExtensions.contains(extension);
  }

  /// 폴더가 존재하고 접근 가능한지 확인
  Future<bool> isFolderAccessible(String folderPath) async {
    try {
      final directory = Directory(folderPath);
      if (!await directory.exists()) {
        return false;
      }
      // 폴더 내용을 읽을 수 있는지 테스트
      await directory.list().first.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('폴더 접근 시간 초과'),
      );
      return true;
    } catch (e) {
      return false;
    }
  }
}

/// 스캔 예외 클래스
class ScanException implements Exception {
  final String message;

  ScanException(this.message);

  @override
  String toString() => 'ScanException: $message';
}
