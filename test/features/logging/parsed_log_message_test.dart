import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:paperless_mobile/features/logging/models/parsed_log_message.dart';

void main() {
  group('ParsedLogMessage.parse', () {
    test('parses a well-formed error + stacktrace block', () {
      final log = [
        '2026-06-19 07:38:29.794	ERROR   --- [                         ] - main                     : An unexpected error occurred ',
        '---BEGIN ERROR---',
        'Null check operator used on a null value',
        '---END ERROR---',
        '---BEGIN STACKTRACE---',
        '#0      OverlayEntry.remove (package:flutter/src/widgets/overlay.dart:228)',
        '#1      NavigatorState._disposeRouteEntry (package:flutter/src/widgets/navigator.dart:3913)',
        '',
        '---END STACKTRACE---',
      ];

      final messages = ParsedLogMessage.parse(log);

      expect(messages, hasLength(1));
      final formatted = messages.single as ParsedFormattedLogMessage;
      expect(formatted.level, Level.error);
      expect(formatted.error, isNotNull);
      expect(
        formatted.error!.error,
        contains('Null check operator used on a null value'),
      );
      expect(formatted.error!.stackTrace, contains('OverlayEntry.remove'));
    });

    test('does not throw on a block truncated before ---END ERROR---', () {
      final log = [
        '2026-06-19 07:38:29.794	ERROR   --- [ ] - main : An unexpected error occurred ',
        '---BEGIN ERROR---',
        'RangeError (length): Invalid value: Only valid value is 0: 1',
      ];

      late List<ParsedLogMessage> messages;
      expect(() => messages = ParsedLogMessage.parse(log), returnsNormally);

      final formatted = messages.single as ParsedFormattedLogMessage;
      expect(formatted.error, isNotNull);
      expect(formatted.error!.error, contains('RangeError'));
      expect(formatted.error!.stackTrace, isNull);
    });

    test('does not throw on a block truncated before ---END STACKTRACE---', () {
      final log = [
        '2026-06-19 07:38:29.794	ERROR   --- [ ] - main : An unexpected error occurred ',
        '---BEGIN ERROR---',
        'RangeError (length): Invalid value: Only valid value is 0: 1',
        '---END ERROR---',
        '---BEGIN STACKTRACE---',
        '#0      List.[] (dart:core-patch/growable_array.dart)',
        '#1      ParsedErrorLogMessage.consume (.../parsed_log_message.dart:49)',
      ];

      late List<ParsedLogMessage> messages;
      expect(() => messages = ParsedLogMessage.parse(log), returnsNormally);

      final formatted = messages.single as ParsedFormattedLogMessage;
      expect(formatted.error, isNotNull);
      expect(formatted.error!.stackTrace, contains('ParsedErrorLogMessage'));
    });

    test('does not throw on the exact RangeError block cut mid-write', () {
      // Mirrors the trailing entry of the uploaded log captured while the
      // logger was still appending it line-by-line.
      final log = [
        '2026-06-19 07:38:29.808	ERROR   --- [ ] - main : An unexpected error occurred ',
        '---BEGIN ERROR---',
        'RangeError (length): Invalid value: Only valid value is 0: 1',
        '---END ERROR---',
        '---BEGIN STACKTRACE---',
        '#0      List.[] (dart:core-patch/growable_array.dart)',
        '#1      ParsedErrorLogMessage.consume (package:paperless_mobile/features/logging/models/parsed_log_message.dart:49)',
        '#2      ParsedFormattedLogMessage.consume (package:paperless_mobile/features/logging/models/parsed_log_message.dart:125)',
        '#3      ParsedLogMessage.parse (package:paperless_mobile/features/logging/models/parsed_log_message.dart:14)',
        '#4      AppLogsCubit._updateLogsFromFile (package:paperless_mobile/features/logging/cubit/app_logs_cubit.dart:64)',
        '<asynchronous suspension>',
        // truncated here: no trailing blank line, no ---END STACKTRACE---
      ];

      expect(() => ParsedLogMessage.parse(log), returnsNormally);
    });
  });
}
