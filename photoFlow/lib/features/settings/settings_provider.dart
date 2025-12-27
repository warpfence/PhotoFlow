import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../media_scanner/media_scanner_provider.dart';

/// 슬라이드쇼 전환 간격 (초)
enum SlideInterval {
  sec3(3, '3초'),
  sec5(5, '5초'),
  sec10(10, '10초'),
  sec15(15, '15초'),
  sec30(30, '30초'),
  min1(60, '1분');

  final int seconds;
  final String label;

  const SlideInterval(this.seconds, this.label);
}

/// 재생 순서
enum PlayOrder {
  sequential('순차 재생'),
  random('랜덤 재생');

  final String label;

  const PlayOrder(this.label);
}

/// 트랜지션 효과
enum TransitionEffect {
  fade('페이드'),
  slide('슬라이드'),
  none('없음');

  final String label;

  const TransitionEffect(this.label);
}

/// 시계 표시 위치
enum ClockPosition {
  topLeft('좌상단'),
  topRight('우상단'),
  bottomLeft('좌하단'),
  bottomRight('우하단'),
  bottomCenter('중앙 하단');

  final String label;

  const ClockPosition(this.label);
}

/// 설정 상태 클래스
class SettingsState {
  final SlideInterval slideInterval;
  final PlayOrder playOrder;
  final TransitionEffect transitionEffect;
  final bool showClock;
  final ClockPosition clockPosition;
  final bool showFileName;
  final bool includeSubfolders;

  const SettingsState({
    this.slideInterval = SlideInterval.sec5,
    this.playOrder = PlayOrder.sequential,
    this.transitionEffect = TransitionEffect.fade,
    this.showClock = false,
    this.clockPosition = ClockPosition.bottomRight,
    this.showFileName = false,
    this.includeSubfolders = true,
  });

  SettingsState copyWith({
    SlideInterval? slideInterval,
    PlayOrder? playOrder,
    TransitionEffect? transitionEffect,
    bool? showClock,
    ClockPosition? clockPosition,
    bool? showFileName,
    bool? includeSubfolders,
  }) {
    return SettingsState(
      slideInterval: slideInterval ?? this.slideInterval,
      playOrder: playOrder ?? this.playOrder,
      transitionEffect: transitionEffect ?? this.transitionEffect,
      showClock: showClock ?? this.showClock,
      clockPosition: clockPosition ?? this.clockPosition,
      showFileName: showFileName ?? this.showFileName,
      includeSubfolders: includeSubfolders ?? this.includeSubfolders,
    );
  }
}

/// 설정 Provider
final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SettingsNotifier(prefs);
});

class SettingsNotifier extends StateNotifier<SettingsState> {
  final SharedPreferences _prefs;

  SettingsNotifier(this._prefs) : super(_loadFromPrefs(_prefs));

  static SettingsState _loadFromPrefs(SharedPreferences prefs) {
    return SettingsState(
      slideInterval: SlideInterval.values[prefs.getInt('slideInterval') ?? 1],
      playOrder: PlayOrder.values[prefs.getInt('playOrder') ?? 0],
      transitionEffect: TransitionEffect.values[prefs.getInt('transitionEffect') ?? 0],
      showClock: prefs.getBool('showClock') ?? false,
      clockPosition: ClockPosition.values[prefs.getInt('clockPosition') ?? 3],
      showFileName: prefs.getBool('showFileName') ?? false,
      includeSubfolders: prefs.getBool('includeSubfolders') ?? true,
    );
  }

  Future<void> _save() async {
    await _prefs.setInt('slideInterval', state.slideInterval.index);
    await _prefs.setInt('playOrder', state.playOrder.index);
    await _prefs.setInt('transitionEffect', state.transitionEffect.index);
    await _prefs.setBool('showClock', state.showClock);
    await _prefs.setInt('clockPosition', state.clockPosition.index);
    await _prefs.setBool('showFileName', state.showFileName);
    await _prefs.setBool('includeSubfolders', state.includeSubfolders);
  }

  Future<void> setSlideInterval(SlideInterval value) async {
    state = state.copyWith(slideInterval: value);
    await _save();
  }

  Future<void> setPlayOrder(PlayOrder value) async {
    state = state.copyWith(playOrder: value);
    await _save();
  }

  Future<void> setTransitionEffect(TransitionEffect value) async {
    state = state.copyWith(transitionEffect: value);
    await _save();
  }

  Future<void> setShowClock(bool value) async {
    state = state.copyWith(showClock: value);
    await _save();
  }

  Future<void> setClockPosition(ClockPosition value) async {
    state = state.copyWith(clockPosition: value);
    await _save();
  }

  Future<void> setShowFileName(bool value) async {
    state = state.copyWith(showFileName: value);
    await _save();
  }

  Future<void> setIncludeSubfolders(bool value) async {
    state = state.copyWith(includeSubfolders: value);
    await _save();
  }
}
