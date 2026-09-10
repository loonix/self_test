import 'dart:io';
import 'dart:typed_data';

/// The one place in the package that touches the filesystem.
///
/// Kept in a file of its own so the `dart:io` import stays isolated: it is the
/// only thing standing between this package and a `web` platform tag on
/// pub.dev, and a single seam is what makes a conditional implementation
/// possible later.
class ScreenshotWriter {
  const ScreenshotWriter();

  /// The directory screenshots land in when the caller has not chosen one.
  String get defaultDirectory => Directory.systemTemp.path;

  /// Writes [bytes] to `<directory>/<fileName>` and returns the full path,
  /// creating the directory if needed.
  Future<String> write(
    Uint8List bytes, {
    required String directory,
    required String fileName,
  }) async {
    final dir = Directory(directory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File('$directory/$fileName');
    await file.writeAsBytes(bytes);
    return file.path;
  }
}
