import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus, XFile;

/// Saves [csv] as a dated file and opens the share sheet, so it can go to
/// Drive, Gmail, Sheets or Files.
Future<void> shareCsv(String csv, DateTime now) async {
  final dir = await getTemporaryDirectory();
  final stamp = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
  final file = File(p.join(dir.path, 'finance-tracker-entries-$stamp.csv'));
  // A byte-order mark tells Excel the file is UTF-8, so ₱ and ñ show right.
  await file.writeAsBytes(
    <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(csv)],
    flush: true,
  );
  await SharePlus.instance.share(
    ShareParams(
      files: <XFile>[XFile(file.path, mimeType: 'text/csv')],
      subject: p.basename(file.path),
      text: 'Finance tracker entries',
    ),
  );
}
