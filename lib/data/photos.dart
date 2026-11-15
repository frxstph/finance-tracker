import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const String receiptsFolderName = 'receipts';

/// True when [name] is a plain file name (no folders, no "..").
bool isSafePhotoName(String name) {
  if (name.isEmpty || name == '.' || name == '..') return false;
  if (name.contains('/') || name.contains('\\')) return false;
  return name == p.basename(name);
}

/// Receipt photos live in `<app documents>/receipts/`. Only file names are
/// stored in the database.
class PhotoStore {
  PhotoStore(this.documentsPath);

  /// Absolute path of the app documents folder.
  final String documentsPath;

  final Random _random = Random();

  static Future<PhotoStore> open() async {
    final docs = await getApplicationDocumentsDirectory();
    final store = PhotoStore(docs.path);
    await store.receiptsDir.create(recursive: true);
    return store;
  }

  Directory get receiptsDir =>
      Directory(p.join(documentsPath, receiptsFolderName));

  File fileFor(String name) => File(p.join(receiptsDir.path, name));

  String _newName() {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final rand = _random.nextInt(1000000).toString().padLeft(6, '0');
    return '${stamp}_$rand.jpg';
  }

  /// Copies the picked image at [sourcePath] into receipts and returns the
  /// new file name.
  Future<String> importFile(String sourcePath) async {
    await receiptsDir.create(recursive: true);
    final name = _newName();
    await File(sourcePath).copy(fileFor(name).path);
    return name;
  }

  /// Deletes the receipt file [name] if it exists. Never throws.
  Future<void> delete(String? name) async {
    if (name == null || !isSafePhotoName(name)) return;
    try {
      final f = fileFor(name);
      if (await f.exists()) {
        await f.delete();
      }
    } on FileSystemException {
      // A missing or locked file is not worth failing the user's action.
    }
  }

  /// Every file currently in the receipts folder.
  Future<List<File>> allFiles() async {
    final dir = receiptsDir;
    if (!await dir.exists()) return <File>[];
    final files = <File>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File) files.add(entity);
    }
    return files;
  }
}
