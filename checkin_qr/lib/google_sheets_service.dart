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

  // ---------- Resultados de marcação ----------
  MarkResult _notFound() => MarkResult(status: MarkStatus.notFound);
  MarkResult _already({int? row, String? timestamp}) =>
      MarkResult(status: MarkStatus.alreadyPresent, row: row, timestamp: timestamp);
  MarkResult _marked({required int row, required String timestamp}) =>
      MarkResult(status: MarkStatus.marked, row: row, timestamp: timestamp);

  /// Procura [valor] na Coluna A da aba [sheetName].
  /// Se achar:
  ///  - Se B já estiver "Presente" -> NÃO sobrescreve (bloqueio) e retorna alreadyPresent.
  ///  - Senão grava "Presente" em B e data/hora em C, formata B (central + verde).
  Future<MarkResult> marcarPresenca(
    String valor, {
    required String sheetName, // 'Segunda' | 'Terca' | 'Quarta'
    String baseRange = 'A2:C20000',
  }) async {
    final range = '$sheetName!$baseRange';

    // 1) Ler A..C para localizar a linha
    final res = await _api.spreadsheets.values.get(spreadsheetId, range);
    final values = res.values ?? [];

    for (int i = 0; i < values.length; i++) {
      final row = values[i];
      final colA = row.isNotEmpty ? (row[0]?.toString() ?? '') : '';
      final colB = row.length > 1 ? (row[1]?.toString() ?? '') : '';
      final colC = row.length > 2 ? (row[2]?.toString() ?? '') : '';

      if (colA.trim().toLowerCase() == valor.trim().toLowerCase()) {
        final rowNumber = i + 2; // começa em A2

        // 2) Bloqueio de duplicata
        if (colB.trim().toLowerCase() == 'presente') {
          return _already(row: rowNumber, timestamp: colC);
        }

        // 3) Escrever "Presente" em B e timestamp em C
        final timestamp = _formatTimestamp(DateTime.now());
        final updateRange = '$sheetName!A$rowNumber:C$rowNumber';
        await _api.spreadsheets.values.update(
          sheets.ValueRange(values: [
            [colA, 'Presente', timestamp]
          ]),
          spreadsheetId,
          updateRange,
          valueInputOption: 'RAW',
        );

        // 4) Formatar B{row}: central + verde claro
        final sheetId = await _getSheetIdByTitle(sheetName);
        if (sheetId != null) {
          final requests = <sheets.Request>[
            sheets.Request(
              repeatCell: sheets.RepeatCellRequest(
                range: sheets.GridRange(
                  sheetId: sheetId,
                  startRowIndex: rowNumber - 1, // zero-based
                  endRowIndex: rowNumber,
                  startColumnIndex: 1, // B = 1
                  endColumnIndex: 2,
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
          ];

          await _api.spreadsheets.batchUpdate(
            sheets.BatchUpdateSpreadsheetRequest(requests: requests),
            spreadsheetId,
          );
        }

        return _marked(row: rowNumber, timestamp: timestamp);
      }
    }

    return _notFound();
  }

  /// Busca o sheetId (gid) a partir do título da aba.
  Future<int?> _getSheetIdByTitle(String title) async {
    final ss = await _api.spreadsheets.get(spreadsheetId);
    for (final sh in ss.sheets ?? []) {
      final props = sh.properties;
      if (props != null && props.title == title) {
        return props.sheetId;
      }
    }
    return null;
  }

  /// dd/MM/yyyy HH:mm:ss no fuso do dispositivo
  String _formatTimestamp(DateTime dt) {
    final d = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }
}

// ---------- Tipos de resultado ----------
enum MarkStatus { marked, alreadyPresent, notFound }

class MarkResult {
  final MarkStatus status;
  final int? row;
  final String? timestamp;
  MarkResult({required this.status, this.row, this.timestamp});
}