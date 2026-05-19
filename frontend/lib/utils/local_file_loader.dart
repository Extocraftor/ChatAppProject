import 'dart:typed_data';

import 'local_file_loader_stub.dart'
    if (dart.library.io) 'local_file_loader_io.dart' as impl;

Future<Uint8List?> readLocalFileBytes(String path) =>
    impl.readLocalFileBytes(path);

String basenameFromPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/');
  for (var index = parts.length - 1; index >= 0; index -= 1) {
    final part = parts[index].trim();
    if (part.isNotEmpty) {
      return part;
    }
  }
  return 'attachment';
}
