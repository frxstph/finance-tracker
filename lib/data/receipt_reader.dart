import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../domain/receipt_parser.dart';

/// Reads a receipt photo on the phone (no internet) with ML Kit text
/// recognition, then guesses the total, date and store.
class ReceiptReader {
  /// The photo's text, row by row from the top, then the guess. When the
  /// text can't be read, the guess carries the error so the screen can say
  /// why.
  static Future<ReceiptGuess> read(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result =
          await recognizer.processImage(InputImage.fromFilePath(imagePath));
      final lines = <TextLine>[
        for (final block in result.blocks) ...block.lines,
      ]..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
      // Text in separate columns ("TOTAL" on the left, "1,248.50" on the
      // right) comes back as separate lines. Join lines that sit on the
      // same row, left to right, so a label and its amount stay together.
      final rows = <List<TextLine>>[];
      for (final line in lines) {
        final mid = line.boundingBox.center.dy;
        final row = rows.isEmpty ? null : rows.last;
        if (row != null) {
          final box = row.first.boundingBox;
          if ((mid - box.center.dy).abs() < box.height * 0.6) {
            row.add(line);
            continue;
          }
        }
        rows.add(<TextLine>[line]);
      }
      final text = <String>[
        for (final row in rows)
          ((row..sort((a, b) =>
                      a.boundingBox.left.compareTo(b.boundingBox.left)))
                  .map((l) => l.text)
                  .join('  ')),
      ];
      return parseReceipt(text);
    } catch (e) {
      return ReceiptGuess(error: e.toString());
    } finally {
      await recognizer.close();
    }
  }
}
