# PhotoFlow

NAS/로컬 폴더의 사진을 슬라이드쇼로 감상할 수 있는 macOS/Windows 데스크톱 앱입니다.

## 주요 기능

- **스트리밍 슬라이드쇼**: 폴더 스캔과 동시에 슬라이드쇼 시작 (첫 이미지 발견 즉시 재생)
- **하위 폴더 포함**: 선택한 폴더의 모든 하위 폴더 이미지 자동 스캔
- **재생 모드**: 순차 재생 / 랜덤 재생 지원
- **전체 화면**: F 키 또는 버튼으로 전체 화면 전환
- **시계 오버레이**: 슬라이드쇼 중 시계 표시 (위치 설정 가능)
- **트랜지션 효과**: 페이드, 슬라이드, 없음 중 선택
- **슬라이드 간격**: 1초 ~ 60초 설정 가능

## 지원 이미지 형식

JPG, JPEG, PNG, GIF, BMP, WEBP, HEIC, HEIF

## 설치 및 실행

### 요구 사항

- Flutter 3.16 이상
- Dart 3.2 이상
- macOS 10.14 이상 / Windows 10 이상

### 빌드

```bash
cd photoFlow
flutter pub get
flutter build macos  # macOS
flutter build windows  # Windows
```

### 실행

```bash
flutter run -d macos  # macOS
flutter run -d windows  # Windows
```

## 키보드 단축키

| 키 | 동작 |
|---|------|
| `Space` | 재생/일시정지 |
| `←` | 이전 이미지 |
| `→` | 다음 이미지 |
| `F` | 전체 화면 전환 |
| `ESC` | 슬라이드쇼 종료 |

## 기술 스택

- **Framework**: Flutter
- **State Management**: Riverpod
- **Storage**: SharedPreferences
- **Window Management**: window_manager
