import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/l10n/app_localizations.dart';

void main() {
  test('生成的中英文数量文案插入实际数量，英文按单复数变化', () {
    for (final language in ['en', 'zh']) {
      final strings = lookupAppLocalizations(Locale(language));
      final countedMessages = <String Function(int)>[
        strings.uiHistoryItemCount,
        strings.msgPickingFinished,
        strings.msgPickingContinues,
        strings.msgMeasurementsRetained,
        strings.msgColorsMerged,
        (count) => strings.msgPaletteCodeCopied(count, 'CSS'),
        strings.msgMeasurementsExported,
      ];
      for (final count in [0, 1, 2, 12]) {
        for (final message in countedMessages) {
          final text = message(count);
          expect(text, contains('$count'), reason: '$language: $text');
          expect(text, isNot(contains('#')), reason: '$language: $text');
        }
      }
    }

    final english = lookupAppLocalizations(const Locale('en'));
    expect(english.uiHistoryItemCount(1), '1 item');
    expect(english.uiHistoryItemCount(2), '2 items');
    expect(english.uiHistoryItemCount(0), '0 items');
  });
}
