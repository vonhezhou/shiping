part of 'fruler_app.dart';

class _RecordingOptionsPage extends StatelessWidget {
  const _RecordingOptionsPage({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final options = controller.recordingOptions;
    final editable =
        !controller.busy &&
        !controller.initializing &&
        !controller.screenRecording &&
        !controller.recordingTransition;
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (controller.screenRecording || controller.recordingTransition) ...[
          _Hint(
            icon: Icons.fiber_manual_record,
            text: controller.recordingTransition
                ? l10n.uiRecordingWorking
                : l10n.uiRecordingActive,
          ),
          const SizedBox(height: 16),
        ],
        _SettingsCard(
          title: l10n.uiRecordingOptions,
          icon: Icons.tune,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _option<String>(
                key: 'recording-codec',
                label: l10n.uiRecordingCodec,
                value: options.codec,
                choices: {
                  'h264': l10n.uiRecordingH264,
                  'hevc': l10n.uiRecordingHevc,
                },
                onChanged: editable
                    ? (value) => controller.setRecordingOptions(
                        options.copyWith(codec: value),
                      )
                    : null,
              ),
              _option<int>(
                key: 'recording-frame-rate',
                label: l10n.uiRecordingFrameRate,
                value: options.frameRate,
                choices: {
                  for (final rate in RecordingOptions.frameRates)
                    rate: '$rate fps',
                },
                onChanged: editable
                    ? (value) => controller.setRecordingOptions(
                        options.copyWith(frameRate: value),
                      )
                    : null,
              ),
              _option<String>(
                key: 'recording-quality',
                label: l10n.uiRecordingQuality,
                value: options.quality,
                choices: {
                  'low': l10n.uiRecordingQualityLow,
                  'medium': l10n.uiRecordingQualityMedium,
                  'high': l10n.uiRecordingQualityHigh,
                },
                onChanged: editable
                    ? (value) => controller.setRecordingOptions(
                        options.copyWith(quality: value),
                      )
                    : null,
              ),
              _option<String>(
                key: 'recording-resolution',
                label: l10n.uiRecordingResolution,
                value: options.resolution,
                choices: {
                  'original': l10n.uiRecordingOriginal,
                  '1080p': '1080p',
                  '720p': '720p',
                },
                onChanged: editable
                    ? (value) => controller.setRecordingOptions(
                        options.copyWith(resolution: value),
                      )
                    : null,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.uiRecordingResolutionHint,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 11,
                  height: 1.6,
                ),
              ),
              const Divider(height: 28),
              SwitchListTile(
                key: const ValueKey('recording-cursor'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.uiRecordingCursor),
                value: options.showCursor,
                onChanged: editable
                    ? (value) => controller.setRecordingOptions(
                        options.copyWith(showCursor: value),
                      )
                    : null,
              ),
              SwitchListTile(
                key: const ValueKey('recording-system-audio'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.uiRecordingAudio),
                subtitle: Text(
                  l10n.uiRecordingAudioHint,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 11,
                    height: 1.6,
                  ),
                ),
                value: options.systemAudio,
                onChanged: editable
                    ? (value) => controller.setRecordingOptions(
                        options.copyWith(systemAudio: value),
                      )
                    : null,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.uiRecordingSettingsHint,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 11,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SettingsCard(
          title: l10n.uiRecordingWorkflow,
          icon: Icons.videocam_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Hint(icon: Icons.crop_free, text: l10n.uiRecordingSelect),
              const SizedBox(height: 12),
              _Hint(icon: Icons.save_outlined, text: l10n.uiRecordingFinish),
            ],
          ),
        ),
      ],
    );
  }

  Widget _option<T>({
    required String key,
    required String label,
    required T value,
    required Map<T, String> choices,
    required ValueChanged<T>? onChanged,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 16),
        SizedBox(
          width: 215,
          child: DropdownButton<T>(
            key: ValueKey(key),
            isExpanded: true,
            value: value,
            items: [
              for (final item in choices.entries)
                DropdownMenuItem(value: item.key, child: Text(item.value)),
            ],
            onChanged: onChanged == null
                ? null
                : (value) {
                    if (value != null) onChanged(value);
                  },
          ),
        ),
      ],
    ),
  );
}
