import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('설정'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 슬라이드쇼 설정 섹션
          _buildSectionHeader(context, '슬라이드쇼'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.timer),
                  title: const Text('전환 간격'),
                  trailing: DropdownButton<SlideInterval>(
                    value: settings.slideInterval,
                    onChanged: (value) {
                      if (value != null) notifier.setSlideInterval(value);
                    },
                    items: SlideInterval.values.map((interval) {
                      return DropdownMenuItem(
                        value: interval,
                        child: Text(interval.label),
                      );
                    }).toList(),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.shuffle),
                  title: const Text('재생 순서'),
                  trailing: DropdownButton<PlayOrder>(
                    value: settings.playOrder,
                    onChanged: (value) {
                      if (value != null) notifier.setPlayOrder(value);
                    },
                    items: PlayOrder.values.map((order) {
                      return DropdownMenuItem(
                        value: order,
                        child: Text(order.label),
                      );
                    }).toList(),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.animation),
                  title: const Text('트랜지션 효과'),
                  trailing: DropdownButton<TransitionEffect>(
                    value: settings.transitionEffect,
                    onChanged: (value) {
                      if (value != null) notifier.setTransitionEffect(value);
                    },
                    items: TransitionEffect.values.map((effect) {
                      return DropdownMenuItem(
                        value: effect,
                        child: Text(effect.label),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 폴더 설정 섹션
          _buildSectionHeader(context, '폴더'),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.folder_copy),
              title: const Text('하위 폴더 포함'),
              subtitle: const Text('선택한 폴더의 하위 폴더도 스캔합니다'),
              value: settings.includeSubfolders,
              onChanged: (value) => notifier.setIncludeSubfolders(value),
            ),
          ),

          const SizedBox(height: 24),

          // 시계 표시 섹션
          _buildSectionHeader(context, '시계 표시'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.access_time),
                  title: const Text('시계 표시'),
                  value: settings.showClock,
                  onChanged: (value) => notifier.setShowClock(value),
                ),
                if (settings.showClock) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.place),
                    title: const Text('표시 위치'),
                    trailing: DropdownButton<ClockPosition>(
                      value: settings.clockPosition,
                      onChanged: (value) {
                        if (value != null) notifier.setClockPosition(value);
                      },
                      items: ClockPosition.values.map((position) {
                        return DropdownMenuItem(
                          value: position,
                          child: Text(position.label),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 사진 정보 표시 섹션
          _buildSectionHeader(context, '사진 정보 표시'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.text_fields),
                  title: const Text('파일명 표시'),
                  value: settings.showFileName,
                  onChanged: (value) => notifier.setShowFileName(value),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.calendar_today),
                  title: const Text('촬영 날짜 표시'),
                  value: settings.showDate,
                  onChanged: (value) => notifier.setShowDate(value),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}
