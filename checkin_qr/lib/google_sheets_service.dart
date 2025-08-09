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
  MarkResult _marked({required int row}) =>
      MarkResult(status: MarkStatus.marked, row: row);

  /// Marca presença em UMA coluna de presença (ex.: B..E).
  ///
  /// [sheetName]        -> nome da aba (ex.: 'Segunda', 'Terca', 'Quarta')
  /// [presenceColIndex] -> índice zero-based da coluna de presença (B=1, C=2, D=3, E=4)
  Future<MarkResult> marcarPresencaEmColuna(
    String valor, {
    required String sheetName,
    required int presenceColIndex,
    String baseRange = 'A2:E20000',
  }) async {
    final range = '$sheetName!$baseRange';

    // 1) Ler A..E para localizar a linha
    final res = await _api.spreadsheets.values.get(spreadsheetId, range);
    final values = res.values ?? [];

    for (int i = 0; i < values.length; i++) {
      final row = values[i];
      final colA = row.isNotEmpty ? (row[0]?.toString() ?? '') : '';
      final currentPresence =
          row.length > presenceColIndex ? (row[presenceColIndex]?.toString() ?? '') : '';

      if (colA.trim().toLowerCase() == valor.trim().toLowerCase()) {
        final rowNumber = i + 2; // começa em A2

        // 2) Bloqueio de duplicata para a coluna selecionada
        if (currentPresence.trim().toLowerCase() == 'presente') {
          return _already(row: rowNumber);
        }

        // 3) Escrever "Presente" na coluna escolhida (somente a célula necessária)
        final presenceColA1 = _colIndexToA1(presenceColIndex); // B, C, D, E...
        final presenceCellRange = '$sheetName!$presenceColA1$rowNumber';

        await _api.spreadsheets.values.update(
          sheets.ValueRange(values: [
            ['Presente']
          ]),
          spreadsheetId,
          presenceCellRange,
          valueInputOption: 'RAW',
        );

        // 4) Formatar a célula da presença (central + verde claro + negrito)
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
          ];

          await _api.spreadsheets.batchUpdate(
            sheets.BatchUpdateSpreadsheetRequest(requests: requests),
            spreadsheetId,
          );
        }

        return _marked(row: rowNumber);
      }
    }
    return _notFound();
  }

  /// Busca o sheetId (gid) a partir do título da aba.
  Future<int?> _getSheetIdByTitle(String title) async {
    final ss = await _api.spreadsheets.get(spreadsheetId);
    for (final sh in ss.sheets ?? []) {
      final props = sh.properties;
      if (props != null && props.title == title) return props.sheetId;
    }
    return null;
  }

  /// Converte índice zero-based para letra(s) de coluna (0->A, 1->B, ..., 25->Z, 26->AA, ...)
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
  MarkResult({required this.status, this.row});
}