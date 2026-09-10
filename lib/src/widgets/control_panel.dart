import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/manager.dart';
import '../core/recording_mode.dart';
import '../models.dart';
import '../test_code_generator.dart';

/// Control panel widget for managing test scripts.
class ControlPanel extends StatefulWidget {
  final SelfTestManager manager;

  const ControlPanel({super.key, required this.manager});

  @override
  State<ControlPanel> createState() => _ControlPanelState();
}

class _ControlPanelState extends State<ControlPanel> {
  TestScript? selectedScript;
  List<TestScript> scripts = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadScripts();
  }

  Future<void> _loadScripts() async {
    try {
      final loadedScripts = await widget.manager.getTestScriptsAsync();
      if (mounted) {
        setState(() {
          scripts = loadedScripts;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[SelfTest] ERROR loading scripts: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 400,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                'Recorded Tests',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Tap a test to view/edit steps',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : scripts.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.videocam_off, size: 48, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'No recorded tests yet',
                          style: TextStyle(color: Colors.grey),
                        ),
                        Text(
                          'Tap the play button to start recording',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: scripts.length,
                    itemBuilder: (context, index) {
                      final script = scripts[index];
                      return ListTile(
                        title: Text(script.name),
                        subtitle: Text(
                          'Created: ${script.createdAt} • ${script.lastRunStatus}',
                        ),
                        onTap: () => setState(() => selectedScript = script),
                        selected: selectedScript == script,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _confirmDelete(script),
                        ),
                      );
                    },
                  ),
          ),
          if (selectedScript != null) ...[
            const Divider(),
            Expanded(child: _buildStepsList(selectedScript!)),
            _buildActionButtons(context),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmDelete(TestScript script) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Test'),
        content: Text('Are you sure you want to delete "${script.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await widget.manager.deleteTestScript(script.id);
        await _loadScripts(); // Refresh the list
        if (selectedScript == script) {
          setState(() => selectedScript = null);
        }
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Deleted "${script.name}"')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
        }
      }
    }
  }

  Widget _buildStepsList(TestScript script) {
    final steps = widget.manager.getTestSteps(script.id);
    return ListView.builder(
      itemCount: steps.length,
      itemBuilder: (context, index) {
        final step = steps[index];
        return ListTile(
          title: Text('${step.action} on ${step.targetId}'),
          subtitle: step.value != null ? Text('Value: ${step.value}') : null,
        );
      },
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: () {
              widget.manager.setRecordingMode(RecordingMode.asserting);
              Navigator.of(context).pop();
            },
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_circle_outline, size: 16),
                SizedBox(height: 2),
                Text('Assert', textScaler: TextScaler.linear(0.7)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton(
            onPressed: () => _runTest(context),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_arrow, size: 16),
                SizedBox(height: 2),
                Text('Run', textScaler: TextScaler.linear(0.7)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton(
            onPressed: () => _exportDart(context),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.code, size: 16),
                SizedBox(height: 2),
                Text('Dart', textScaler: TextScaler.linear(0.7)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton(
            onPressed: () => _exportJson(context),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.data_object, size: 16),
                SizedBox(height: 2),
                Text('JSON', textScaler: TextScaler.linear(0.7)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _runTest(BuildContext context) async {
    try {
      debugPrint('[SelfTest] Running test script: ${selectedScript!.name}');
      await widget.manager.runTestScript(selectedScript!.id);
      debugPrint('[SelfTest] Test run completed');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Test completed successfully')),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('[SelfTest] ERROR running test: $e');
      debugPrint('[SelfTest] Stack trace: $stackTrace');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Test failed: $e')));
      }
    }
  }

  Future<void> _exportDart(BuildContext context) async {
    await _copyGenerated(
      context,
      label: 'Dart test',
      extension: 'dart',
      build: (generator, script, steps) =>
          generator.generateTestCode(script, steps),
    );
  }

  Future<void> _exportJson(BuildContext context) async {
    await _copyGenerated(
      context,
      label: 'JSON export',
      extension: 'json',
      build: (generator, script, steps) =>
          generator.generateJsonExport(script, steps),
    );
  }

  /// Generates code for the selected script and puts it on the clipboard.
  ///
  /// The clipboard, not a file: writing into the app's documents directory
  /// needed path_provider as a runtime dependency of every consumer app, and
  /// left the developer digging through a sandbox to find the result.
  Future<void> _copyGenerated(
    BuildContext context, {
    required String label,
    required String extension,
    required String Function(
      TestCodeGenerator generator,
      TestScript script,
      List<RecordedStep> steps,
    )
    build,
  }) async {
    final script = selectedScript;
    if (script == null) return;
    try {
      final steps = widget.manager.getTestSteps(script.id);
      final generator = TestCodeGenerator();
      final source = build(generator, script, steps);
      await Clipboard.setData(ClipboardData(text: source));
      final fileName = generator.fileNameFor(script, extension: extension);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$label copied to clipboard, save as $fileName'),
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('[SelfTest] ERROR generating $label: $e');
      debugPrint('[SelfTest] Stack trace: $stackTrace');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$label failed: $e')));
      }
    }
  }
}
