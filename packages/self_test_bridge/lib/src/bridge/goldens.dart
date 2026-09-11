part of '../bridge_service.dart';

/// Screenshots, golden comparison and video.
extension _BridgeGoldens on SelfTestBridge {
  /// The goldens commands.
  ///
  /// Returns [_unhandled] for a command this group does not
  /// own, which is how the dispatcher walks on to the next.
  Future<Object?> _goldensCommands(BridgeCommand command) async {
    final params = command.params;
    switch (command.command) {
      case 'expectScreenshot':
        final name = params['name'] as String;
        final widgetId = params.containsKey('locator')
            ? _targetId(params)
            : params['widgetId'] as String?;
        final threshold = (params['threshold'] as num?)?.toDouble() ?? 0.01;
        final updateBaseline = params['updateBaseline'] as bool? ?? false;
        final goldensDir = params['goldensDir'] as String?;
        return await _expectScreenshot(
          name,
          widgetId,
          threshold,
          updateBaseline,
          goldensDir,
        );

      case 'updateGoldens':
        final names = (params['names'] as List?)?.cast<String>();
        final goldensDir = params['goldensDir'] as String?;
        return await _updateGoldens(names, goldensDir);

      case 'listGoldens':
        final goldensDir = params['goldensDir'] as String?;
        return await _listGoldens(goldensDir);

      case 'screenshot':
        final name = params['name'] as String? ?? 'screenshot';
        final widgetId = params.containsKey('locator')
            ? _targetId(params)
            : params['widgetId'] as String?;
        final fullPage = params['fullPage'] as bool? ?? false;
        return await _takeScreenshot(name, widgetId, fullPage);

      case 'recordStart':
        final name = params['name'] as String? ?? 'recording';
        _startRecording(name);
        return {'success': true};

      case 'recordStop':
        return await _stopRecording();

      // =====================================================================
      // NETWORK
      // =====================================================================

      default:
        return _unhandled;
    }
  }

  /// Get the absolute path to the goldens directory.
  String _getGoldensDirectory(String? goldensDir) {
    final dir = goldensDir ?? _defaultGoldensDir;
    if (_projectRoot != null) {
      return '$_projectRoot/$dir';
    }
    // Fallback: use current directory
    return dir;
  }

  /// Ensure the goldens directory exists.
  Future<Directory> _ensureGoldensDirectory(String? goldensDir) async {
    final path = _getGoldensDirectory(goldensDir);
    final directory = Directory(path);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  /// Get the path to a golden file.
  String _getGoldenPath(String name, String? goldensDir) {
    final dir = _getGoldensDirectory(goldensDir);
    // Sanitize name for filesystem
    final safeName = name.replaceAll(RegExp(r'[^\w\-.]'), '_');
    return '$dir/$safeName.png';
  }

  /// Get the path to a diff file.
  String _getDiffPath(String name, String? goldensDir) {
    final dir = _getGoldensDirectory(goldensDir);
    final safeName = name.replaceAll(RegExp(r'[^\w\-.]'), '_');
    return '$dir/${safeName}_diff.png';
  }

  Future<Map<String, dynamic>> _expectScreenshot(
    String name,
    String? widgetId,
    double threshold,
    bool updateBaseline,
    String? goldensDir,
  ) async {
    await _ensureGoldensDirectory(goldensDir);
    final baselinePath = _getGoldenPath(name, goldensDir);
    final baselineFile = File(baselinePath);
    final currentBytes = await _captureScreenshotBytes(widgetId);
    final safeName = name.replaceAll(RegExp(r'[^\w\-.]'), '_');
    final relativeDir = goldensDir ?? _defaultGoldensDir;
    final relativeBaselinePath = '$relativeDir/$safeName.png';

    if (updateBaseline) {
      await baselineFile.writeAsBytes(currentBytes);
      return {
        'passed': true,
        'baselineUpdated': true,
        'baselinePath': relativeBaselinePath,
        'difference': 0.0,
      };
    }

    if (!await baselineFile.exists()) {
      await baselineFile.writeAsBytes(currentBytes);
      return {
        'passed': true,
        'baselineCreated': true,
        'baselinePath': relativeBaselinePath,
        'difference': 0.0,
      };
    }

    final baselineBytes = await baselineFile.readAsBytes();
    final baselineImage = await _decodeImage(baselineBytes);
    final currentImage = await _decodeImage(currentBytes);

    if (baselineImage == null || currentImage == null) {
      return {
        'passed': false,
        'difference': 1.0,
        'message': 'Failed to decode images',
        'baselinePath': relativeBaselinePath,
      };
    }

    if (baselineImage.width != currentImage.width ||
        baselineImage.height != currentImage.height) {
      final diffPath = _getDiffPath(name, goldensDir);
      await File(diffPath).writeAsBytes(currentBytes);
      return {
        'passed': false,
        'difference': 1.0,
        'message':
            'Size mismatch: ${baselineImage.width}x${baselineImage.height} vs ${currentImage.width}x${currentImage.height}',
        'baselinePath': relativeBaselinePath,
        'diffPath': '$relativeDir/${safeName}_diff.png',
      };
    }

    final baselineData = await baselineImage.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    final currentData = await currentImage.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );

    if (baselineData == null || currentData == null) {
      return {
        'passed': false,
        'difference': 1.0,
        'message': 'Failed to get image data',
        'baselinePath': relativeBaselinePath,
      };
    }

    int differentPixels = 0;
    final totalPixels = baselineImage.width * baselineImage.height;
    final diffBuffer = Uint8List(baselineData.lengthInBytes);

    for (int i = 0; i < baselineData.lengthInBytes; i += 4) {
      final r1 = baselineData.getUint8(i);
      final g1 = baselineData.getUint8(i + 1);
      final b1 = baselineData.getUint8(i + 2);
      final a1 = baselineData.getUint8(i + 3);
      final r2 = currentData.getUint8(i);
      final g2 = currentData.getUint8(i + 1);
      final b2 = currentData.getUint8(i + 2);
      final a2 = currentData.getUint8(i + 3);

      if (r1 != r2 || g1 != g2 || b1 != b2 || a1 != a2) {
        differentPixels++;
        diffBuffer[i] = 255;
        diffBuffer[i + 1] = 0;
        diffBuffer[i + 2] = 0;
        diffBuffer[i + 3] = 255;
      } else {
        diffBuffer[i] = (r1 * 0.3).round();
        diffBuffer[i + 1] = (g1 * 0.3).round();
        diffBuffer[i + 2] = (b1 * 0.3).round();
        diffBuffer[i + 3] = a1;
      }
    }

    final difference = differentPixels / totalPixels;
    final passed = difference <= threshold;
    String? diffImageBase64;

    if (!passed) {
      final diffPath = _getDiffPath(name, goldensDir);
      final diffImage = await _createImageFromRgba(
        diffBuffer,
        baselineImage.width,
        baselineImage.height,
      );
      if (diffImage != null) {
        final diffPngBytes = await diffImage.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (diffPngBytes != null) {
          await File(diffPath).writeAsBytes(diffPngBytes.buffer.asUint8List());
          diffImageBase64 = base64Encode(diffPngBytes.buffer.asUint8List());
        }
      }
    }

    return {
      'passed': passed,
      'difference': difference,
      'baselinePath': relativeBaselinePath,
      if (!passed) 'diffPath': '$relativeDir/${safeName}_diff.png',
      if (!passed && diffImageBase64 != null) 'diffImage': diffImageBase64,
    };
  }

  Future<ui.Image?> _decodeImage(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (e) {
      return null;
    }
  }

  Future<ui.Image?> _createImageFromRgba(
    Uint8List rgba,
    int width,
    int height,
  ) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return await completer.future;
  }

  Future<Map<String, dynamic>> _updateGoldens(
    List<String>? names,
    String? goldensDir,
  ) async {
    await _ensureGoldensDirectory(goldensDir);
    final directory = Directory(_getGoldensDirectory(goldensDir));
    final updated = <String>[];

    if (names != null && names.isNotEmpty) {
      for (final name in names) {
        final currentBytes = await _captureScreenshotBytes(null);
        final path = _getGoldenPath(name, goldensDir);
        await File(path).writeAsBytes(currentBytes);
        updated.add(name);
      }
    } else {
      if (await directory.exists()) {
        await for (final file in directory.list()) {
          if (file is File &&
              file.path.endsWith('.png') &&
              !file.path.endsWith('_diff.png')) {
            final name = file.path.split('/').last.replaceAll('.png', '');
            final currentBytes = await _captureScreenshotBytes(null);
            await file.writeAsBytes(currentBytes);
            updated.add(name);
          }
        }
      }
    }
    return {'updated': updated, 'skipped': <String>[]};
  }

  Future<Map<String, dynamic>> _listGoldens(String? goldensDir) async {
    final directoryPath = _getGoldensDirectory(goldensDir);
    final directory = Directory(directoryPath);
    final goldens = <Map<String, dynamic>>[];
    final relativeDir = goldensDir ?? _defaultGoldensDir;

    if (await directory.exists()) {
      await for (final file in directory.list()) {
        if (file is File &&
            file.path.endsWith('.png') &&
            !file.path.endsWith('_diff.png')) {
          final stat = await file.stat();
          final name = file.path.split('/').last.replaceAll('.png', '');
          final sizeStr = stat.size < 1024
              ? '${stat.size} B'
              : '${(stat.size / 1024).toStringAsFixed(1)} KB';
          goldens.add({
            'name': name,
            'path': '$relativeDir/$name.png',
            'size': sizeStr,
            'modified': stat.modified.toIso8601String(),
          });
        }
      }
    }
    return {'directory': relativeDir, 'goldens': goldens};
  }

  // ===========================================================================
  // SCREENSHOT & RECORDING
  // ===========================================================================

  Future<Map<String, dynamic>> _takeScreenshot(
    String name,
    String? widgetId,
    bool fullPage,
  ) async {
    final manager = SelfTestManager();

    try {
      final path = await manager.captureScreenshot(name);

      if (path != null) {
        final file = File(path);
        final bytes = await file.readAsBytes();
        final base64Data = base64Encode(bytes);

        return {
          'filename': path.split('/').last,
          'filepath': path,
          'base64': base64Data,
        };
      }
    } catch (e) {
      _logConsole('error', 'Screenshot failed: $e');
    }

    return {'error': 'Failed to capture screenshot'};
  }

  Future<Uint8List> _captureScreenshotBytes(String? widgetId) async {
    final manager = SelfTestManager();
    final path = await manager.captureScreenshot('temp_comparison');

    if (path != null) {
      final file = File(path);
      return await file.readAsBytes();
    }

    return Uint8List(0);
  }

  void _startRecording(String name) {
    _isRecording = true;
    _recordingName = name;
    _recordingFrames.clear();

    _recordingTimer = Timer.periodic(const Duration(milliseconds: 100), (
      _,
    ) async {
      if (_isRecording) {
        final bytes = await _captureScreenshotBytes(null);
        _recordingFrames.add(bytes);
      }
    });
  }

  Future<Map<String, dynamic>> _stopRecording() async {
    _recordingTimer?.cancel();
    _isRecording = false;

    // Save frames as video or animated GIF
    final filepath = '/tmp/${_recordingName ?? 'recording'}.gif';

    // Note: Actual video encoding would require a native plugin
    // For now, save frames metadata
    return {
      'filepath': filepath,
      'frames': _recordingFrames.length,
      'note': 'Video encoding requires native implementation',
    };
  }

  Future<void> _captureTraceScreenshot(String name) async {
    final bytes = await _captureScreenshotBytes(null);
    _traceEvents.add({
      'type': 'screenshot',
      'name': name,
      'timestamp': DateTime.now().toIso8601String(),
      'data': base64Encode(bytes),
    });
  }

  Future<String> _saveTrace() async {
    final filepath = '/tmp/${_traceName ?? 'trace'}.json';
    final file = File(filepath);
    await file.writeAsString(jsonEncode(_traceEvents));
    return filepath;
  }
}
