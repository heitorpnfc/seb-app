import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart';

class GoogleSheetsService {
  final String spreadsheetId;
  final sheets.SheetsApi _api;

  GoogleSheetsService._(this.spreadsheetId, this._api);

  static Future<GoogleSheetsService> create(String spreadsheetId) async {
    final jsonString =
        await rootBundle.loadString('assets/checkin-presenca-service.json');
    final creds = ServiceAccountCredentials.fromJson(jsonDecode(jsonString));
    final client = await clientViaServiceAccount(
      creds,
      [sheets.SheetsApi.spreadsheetsScope],
    );
    return GoogleSheetsService._(spreadsheetId, sheets.SheetsApi(client));
  }

  // ---------- Resultados ----------
  MarkResult _notFound() => MarkResult(status: MarkStatus.notFound);
  MarkResult _already({int? row}) =>
      MarkResult(status: MarkStatus.alreadyPresent, row: row);
  MarkResult _marked({required int row, required String ts}) =>
      MarkResult(status: MarkStatus.marked, row: row, timestamp: ts);

  /// Marca na coluna informada (B=1, D=3, F=5, H=7...) e grava o HORÁRIO na coluna ao lado (C,E,G,I...).
  Future<MarkResult> marcarPresencaEmColuna(
    String valor, {
    required String sheetName,
    required int presenceColIndex,
    String baseRange = 'A2:Z20000',
  }) async {
    final tab = "'$sheetName'";
    final range = '$tab!$baseRange';

    // 1) Localiza o nome na coluna A
    final res = await _retry(() => _api.spreadsheets.values.get(spreadsheetId, range));
    final values = res.values ?? [];

    for (int i = 0; i < values.length; i++) {
      final row = values[i];
      final colA = row.isNotEmpty ? (row[0]?.toString() ?? '') : '';
      final currentPresence =
          row.length > presenceColIndex ? (row[presenceColIndex]?.toString() ?? '') : '';

      if (colA.trim().toLowerCase() == valor.trim().toLowerCase()) {
        final rowNumber = i + 2; // começa em A2

        // 2) evita duplicar
        if (currentPresence.trim().toLowerCase() == 'presente') {
          return _already(row: rowNumber);
        }

        // 3) escreve "Presente"
        final presenceColA1 = _colIndexToA1(presenceColIndex);
        final presenceCellRange = '$tab!$presenceColA1$rowNumber';
        await _retry(() => _api.spreadsheets.values.update(
              sheets.ValueRange(values: [
                ['Presente']
              ]),
              spreadsheetId,
              presenceCellRange,
              valueInputOption: 'RAW',
            ));

        // 4) escreve o HORÁRIO na coluna ao lado
        final timeColIndex = presenceColIndex + 1;
        final timeColA1 = _colIndexToA1(timeColIndex);
        final timeCellRange = '$tab!$timeColA1$rowNumber';

        String _p2(int n) => n.toString().padLeft(2, '0');
        final now = DateTime.now();
        final timeStr =
            '${now.year}-${_p2(now.month)}-${_p2(now.day)} ${_p2(now.hour)}:${_p2(now.minute)}:${_p2(now.second)}';

        await _retry(() => _api.spreadsheets.values.update(
              sheets.ValueRange(values: [
                [timeStr]
              ]),
              spreadsheetId,
              timeCellRange,
              valueInputOption: 'USER_ENTERED', // Sheets interpreta como data/hora
            ));

        // 5) formatação visual
        final sheetId = await _getSheetIdByTitle(sheetName);
        if (sheetId != null) {
          final requests = <sheets.Request>[
            sheets.Request(
              repeatCell: sheets.RepeatCellRequest(
                range: sheets.GridRange(
                  sheetId: sheetId,
                  startRowIndex: rowNumber - 1,
                  endRowIndex: rowNumber,
                  startColumnIndex: presenceColIndex,
                  endColumnIndex: presenceColIndex + 1,
                ),
                cell: sheets.CellData(
                  userEnteredFormat: sheets.CellFormat(
                    horizontalAlignment: 'CENTER',
                    verticalAlignment: 'MIDDLE',
                    backgroundColor: sheets.Color(
                      red: 200 / 255, green: 230 / 255, blue: 201 / 255, // #C8E6C9
                    ),
                    textFormat: sheets.TextFormat(bold: true),
                  ),
                ),
                fields:
                    'userEnteredFormat(horizontalAlignment,verticalAlignment,backgroundColor,textFormat)',
              ),
            ),
            sheets.Request(
              repeatCell: sheets.RepeatCellRequest(
                range: sheets.GridRange(
                  sheetId: sheetId,
                  startRowIndex: rowNumber - 1,
                  endRowIndex: rowNumber,
                  startColumnIndex: timeColIndex,
                  endColumnIndex: timeColIndex + 1,
                ),
                cell: sheets.CellData(
                  userEnteredFormat: sheets.CellFormat(
                    horizontalAlignment: 'CENTER',
                    numberFormat: sheets.NumberFormat(
                      type: 'DATE_TIME',
                      pattern: 'dd/MM/yyyy HH:mm:ss',
                    ),
                  ),
                ),
                fields: 'userEnteredFormat(horizontalAlignment,numberFormat)',
              ),
            ),
          ];

          await _retry(() => _api.spreadsheets.batchUpdate(
                sheets.BatchUpdateSpreadsheetRequest(requests: requests),
                spreadsheetId,
              ));
        }

        return _marked(row: rowNumber, ts: timeStr);
      }
    }
    return _notFound();
  }

  Future<T> _retry<T>(Future<T> Function() fn) async {
    const delays = [Duration(milliseconds: 0), Duration(milliseconds: 300), Duration(milliseconds: 700)];
    Object? lastErr;
    for (final d in delays) {
      if (d.inMilliseconds > 0) await Future.delayed(d);
      try {
        return await fn();
      } catch (e) {
        lastErr = e;
      }
    }
    throw lastErr ?? Exception('Erro desconhecido');
  }

  Future<int?> _getSheetIdByTitle(String title) async {
    final ss = await _retry(() => _api.spreadsheets.get(spreadsheetId));
    for (final sh in ss.sheets ?? []) {
      final props = sh.properties;
      if (props != null && props.title == title) return props.sheetId;
    }
    return null;
  }

  String _colIndexToA1(int idx) {
    int n = idx;
    String s = '';
    while (n >= 0) {
      s = String.fromCharCode((n % 26) + 65) + s;
      n = (n ~/ 26) - 1;
    }
    return s;
  }
}

// ---------- Tipos de resultado ----------
enum MarkStatus { marked, alreadyPresent, notFound }

class MarkResult {
  final MarkStatus status;
  final int? row;
  final String? timestamp; // horário gravado (texto)
  MarkResult({required this.status, this.row, this.timestamp});
}