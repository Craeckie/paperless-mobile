import 'dart:async';
import 'dart:io';

import 'package:bloc/bloc.dart';
import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:paperless_mobile/api/constants/constants.dart';
import 'package:paperless_mobile/core/service/file_service.dart';
import 'package:paperless_mobile/features/logging/models/parsed_log_message.dart';
import 'package:paperless_mobile/features/notifications/services/local_notification_service.dart';
import 'package:path/path.dart' as p;
import 'package:rxdart/rxdart.dart';

part 'app_logs_state.dart';

class AppLogsCubit extends Cubit<AppLogsState> {
  StreamSubscription? _fileChangesSubscription;
  final LocalNotificationService _localNotificationService;
  AppLogsCubit(DateTime date, this._localNotificationService)
    : super(AppLogsStateInitial(date: date));

  Future<void> loadLogs(DateTime date) async {
    if (date == state.date) {
      return;
    }
    _fileChangesSubscription?.cancel();
    emit(AppLogsStateLoading(date: date));
    final logDir = FileService.instance.logDirectory;
    final availableLogs =
        (await logDir
                .list()
                .whereType<File>()
                .where((event) => event.path.endsWith('.log'))
                .map(
                  (e) =>
                      apiDateFormat.parse(p.basenameWithoutExtension(e.path)),
                )
                .toList())
            .sorted();
    final logFile = _getLogfile(date);
    if (!await logFile.exists()) {
      emit(
        AppLogsStateLoaded(date: date, logs: [], availableLogs: availableLogs),
      );
    }
    try {
      _updateLogsFromFile(logFile, date, availableLogs);
      _fileChangesSubscription = logFile.watch().listen((event) async {
        if (!isClosed) {
          _updateLogsFromFile(logFile, date, availableLogs);
        }
      });
    } catch (e) {
      emit(AppLogsStateError(error: e, date: date));
    }
  }

  void _updateLogsFromFile(
    File file,
    DateTime date,
    List<DateTime> availableLogs,
  ) async {
    try {
      final logs = await file.readAsLines();
      final parsedLogs = ParsedLogMessage.parse(logs).reversed.toList();
      if (isClosed) {
        return;
      }
      emit(
        AppLogsStateLoaded(
          date: date,
          logs: parsedLogs,
          availableLogs: availableLogs,
        ),
      );
    } catch (e) {
      // Contain parse/read failures locally. This method is invoked from the
      // file watch callback as `async void`, so an uncaught throw would escape
      // to the global zone handler, which logs it back into the very file being
      // watched and re-triggers this method -> infinite error-spam loop. Do NOT
      // re-log via `logger` here for the same reason.
      if (!isClosed) {
        emit(AppLogsStateError(error: e, date: date));
      }
    }
  }

  Future<void> clearLogs(DateTime date) async {
    final logFile = _getLogfile(date);
    await logFile.writeAsString('');
    await loadLogs(date);
  }

  Future<void> copyToClipboard(DateTime date) async {
    final file = _getLogfile(date);
    if (!await file.exists()) {
      return;
    }
    final content = await file.readAsString();
    Clipboard.setData(ClipboardData(text: content));
  }

  Future<void> saveLogs(DateTime date, String locale) async {
    var formattedDate = apiDateFormat.format(date);
    final filename = 'paperless_mobile_logs_$formattedDate.log';
    // final parentDir = await FilePicker.platform.getDirectoryPath(
    //   dialogTitle: "Save log from ${DateFormat.yMd(locale).format(date)}",
    //   initialDirectory: Platform.isAndroid
    //       ? FileService.instance.downloadsDirectory.path
    //       : null,
    // );
    // if (parentDir == null) {
    //   return;
    // }
    final logFile = _getLogfile(date);
    final parentDir = FileService.instance.downloadsDirectory;
    final downloadedFile = await logFile.copy(p.join(parentDir.path, filename));
    _localNotificationService.notifyFileDownload(filePath: downloadedFile.path);
  }

  File _getLogfile(DateTime date) {
    return File(
      p.join(
        FileService.instance.logDirectory.path,
        '${apiDateFormat.format(date)}.log',
      ),
    );
  }

  @override
  Future<void> close() async {
    await _fileChangesSubscription?.cancel();
    return super.close();
  }
}
