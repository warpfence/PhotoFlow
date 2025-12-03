# PhotoFlow

NAS 및 로컬 폴더의 사진을 슬라이드쇼로 감상할 수 있는 macOS/Windows 데스크톱 애플리케이션입니다.

## 주요 기능

- **폴더 기반 이미지 스캔**: 선택한 폴더에서 이미지 파일 자동 탐색
- **하위 폴더 포함**: 하위 폴더의 이미지까지 재귀적으로 스캔
- **슬라이드쇼 재생**: 순차/랜덤 재생 모드 지원
- **전환 효과**: 페이드, 슬라이드, 없음 중 선택
- **전체화면 모드**: 몰입감 있는 감상
- **키보드 단축키**: 편리한 조작
- **오버레이 정보**: 시계, 파일명, 촬영 날짜 표시 (선택적)

## 지원 이미지 포맷

- JPEG (.jpg, .jpeg)
- PNG (.png)
- GIF (.gif)
- WebP (.webp)

## 시스템 요구사항

- macOS 10.14 이상 또는 Windows 10 이상
- Flutter SDK 3.16 이상
- Dart SDK 3.2 이상

## 설치 및 실행

### 사전 준비

1. [Flutter SDK](https://docs.flutter.dev/get-started/install) 설치
2. macOS 개발을 위해 Xcode 설치 (macOS만 해당)

### 빌드 및 실행

```bash
# 프로젝트 디렉토리로 이동
cd photo_slideshow

# 의존성 설치
flutter pub get

# macOS 앱 실행 (디버그 모드)
flutter run -d macos

# Windows 앱 실행 (디버그 모드)
flutter run -d windows
```

### 릴리스 빌드

```bash
# macOS 릴리스 빌드
flutter build macos --release

# Windows 릴리스 빌드
flutter build windows --release
```

빌드된 앱 위치:
- macOS: `build/macos/Build/Products/Release/photo_slideshow.app`
- Windows: `build/windows/x64/runner/Release/`

## 사용 방법

### 기본 사용법

1. 앱 실행 후 **폴더 선택** 버튼 클릭
2. 사진이 있는 폴더 선택
3. 이미지 스캔 완료 후 **슬라이드쇼 시작** 클릭

### 키보드 단축키

| 키 | 동작 |
|---|---|
| `Space` | 재생/일시정지 토글 |
| `→` | 다음 이미지 |
| `←` | 이전 이미지 |
| `F` | 전체화면 토글 |
| `ESC` | 슬라이드쇼 종료 |

### 설정 옵션

- **전환 간격**: 3초, 5초, 10초, 15초, 30초, 1분
- **재생 순서**: 순차 재생, 랜덤 재생
- **전환 효과**: 페이드, 슬라이드, 없음
- **시계 표시**: 화면에 현재 시간 표시
- **파일명 표시**: 현재 이미지 파일명 표시
- **촬영 날짜 표시**: EXIF 메타데이터에서 촬영 날짜 추출 및 표시
- **하위 폴더 포함**: 선택한 폴더의 하위 폴더까지 스캔

## 프로젝트 구조

```
lib/
├── main.dart                    # 앱 진입점
├── core/
│   ├── constants/               # 앱 상수 정의
│   ├── theme/                   # 테마 설정
│   └── utils/                   # 유틸리티 (키보드 단축키, 이미지 처리)
└── features/
    ├── home/                    # 홈 화면
    ├── settings/                # 설정 화면 및 저장소
    ├── media_scanner/           # 이미지 스캔 기능
    └── slideshow/               # 슬라이드쇼 재생 기능
```

## 기술 스택

- **프레임워크**: Flutter 3.16+
- **언어**: Dart 3.2+
- **상태 관리**: Riverpod
- **로컬 저장소**: SharedPreferences
- **데스크톱 윈도우**: window_manager
- **파일 선택**: file_picker
- **EXIF 메타데이터**: exif

## 라이선스

이 프로젝트는 개인 사용을 위해 개발되었습니다.
