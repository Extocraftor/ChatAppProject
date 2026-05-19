import 'dart:io' as io;
import 'dart:typed_data';

Future<Uint8List?> readLocalFileBytes(String path) async {
  final file = io.File(path);
  if (!await file.exists()) {
    return null;
  }
  return file.readAsBytes();
}
