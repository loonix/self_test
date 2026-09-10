import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/manager.dart';
import '../core/recording_mode.dart';
import 'control_panel.dart';

/// A wrapper widget for the root of the app to enable programmatic restart.
class SelfTestRoot extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState>? navigatorKey;

  SelfTestRoot({Key? key, required this.child, this.navigatorKey})
      : super(key: key ?? (SelfTestManager().rootKey ?? GlobalKey<State>(debugLabel: 'SelfTestRoot'))) {
    // Ensure the manager has a root key
    SelfTestManager().rootKey ??= GlobalKey<State>(debugLabel: 'SelfTestRoot');
  }

  @override
  State<SelfTestRoot> createState() => _SelfTestRootState();
}

class _SelfTestRootState extends State<SelfTestRoot> {
  bool _isFabExpanded = false;
  Offset _fabPosition = const Offset(300, 300); // Default position, will be updated

  // FAB dimensions for bounds calculation
  static const double _fabSize = 72.0;
  static const double _fabTotalHeight = 100.0; // FAB + label
  static const double _fabPadding = 16.0;

  /// Clamps the FAB position to keep it within screen bounds
  Offset _clampFabPosition(Offset position, Size screenSize) {
    final minX = _fabPadding;
    final maxX = screenSize.width - _fabSize - _fabPadding;
    final minY = _fabPadding + MediaQuery.of(context).padding.top;
    final maxY = screenSize.height - _fabTotalHeight - _fabPadding - MediaQuery.of(context).padding.bottom;

    return Offset(
      position.dx.clamp(minX, maxX),
      position.dy.clamp(minY, maxY),
    );
  }

  @override
  void initState() {
    super.initState();
    debugPrint('[SelfTest] SelfTestRoot initState called');
    debugPrint('[SelfTest] SelfTestRoot key: ${widget.key}, manager rootKey: ${SelfTestManager().rootKey}');
    // Ensure the manager's rootKey points to this state
    SelfTestManager().rootKey = widget.key as GlobalKey<State>?;
    // Initialize FAB position to middle-right, fully visible
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final screenSize = MediaQuery.of(context).size;
        final newPosition = Offset(screenSize.width - 88, screenSize.height / 2 - 36);
        debugPrint('[SelfTest] Setting FAB position to: $newPosition, screen size: $screenSize');
        setState(() {
          _fabPosition = newPosition;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Force rebuild when self-test mode changes or restart is called
    final manager = SelfTestManager();
    debugPrint('[SelfTest] SelfTestRoot building with key: ${manager.isSelfTestModeActive}_${manager.isTestMode}_${manager.rebuildCounter}');
    final child = KeyedSubtree(
      key: ValueKey('${manager.isSelfTestModeActive}_${manager.isTestMode}_${manager.rebuildCounter}'),
      child: widget.child,
    );

    if (!kDebugMode) return child;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          child,
          Positioned.fill(
            child: _buildOverlay(context, manager),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlay(BuildContext context, SelfTestManager manager) {
    final isRecording = manager.recordingMode == RecordingMode.recording;
    debugPrint('[SelfTest] Building overlay, isRecording: $isRecording');
    return Stack(
      children: [
        // Recording indicator
        if (isRecording)
          Positioned(
            top: 50,
            right: 16,
            child: AnimatedOpacity(
              opacity: 0.8,
              duration: const Duration(milliseconds: 500),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withAlpha(77),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Row(
                  children: [
                    Icon(Icons.circle, color: Colors.white, size: 12),
                    SizedBox(width: 4),
                    Text('RECORDING', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),
        // Expandable FAB or Stop FAB
        if (!isRecording) _buildExpandableFab(context, manager) else _buildStopFab(context, manager),
      ],
    );
  }

  Widget _buildDraggableFab(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (details) {
        setState(() {
          final screenSize = MediaQuery.of(context).size;
          _fabPosition = _clampFabPosition(_fabPosition + details.delta, screenSize);
        });
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: FloatingActionButton(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              onPressed: () => setState(() => _isFabExpanded = !_isFabExpanded),
              child: Icon(_isFabExpanded ? Icons.close : Icons.menu, size: 32),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(179),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _isFabExpanded ? 'CLOSE' : 'TEST',
              style: const TextStyle(color: Colors.white, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandableFab(BuildContext context, SelfTestManager manager) {
    debugPrint('[SelfTest] Building expandable FAB');
    return Stack(
      children: [
        // Background overlay when expanded
        if (_isFabExpanded)
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _isFabExpanded = false),
              child: Container(color: Colors.black.withAlpha(26)),
            ),
          ),

        // Mini FABs (when expanded) - now positioned relative to main FAB
        if (_isFabExpanded) ...[
          Positioned(
            left: _fabPosition.dx,
            top: _fabPosition.dy - 100,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton(
                  mini: true,
                  backgroundColor: Colors.green,
                  onPressed: () async {
                    setState(() => _isFabExpanded = false);
                    final name = await _showNameDialog(widget.navigatorKey?.currentContext ?? context);
                    if (name != null && name.isNotEmpty) {
                      await manager.startRecording(name);
                      manager.setRecordingMode(RecordingMode.recording);
                      if ((widget.navigatorKey?.currentContext ?? context).mounted) {
                        ScaffoldMessenger.of(widget.navigatorKey?.currentContext ?? context).showSnackBar(
                          SnackBar(content: Text('Started recording: "$name"')),
                        );
                      }
                    }
                  },
                  child: const Icon(Icons.play_circle_fill, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(179),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('START', style: TextStyle(color: Colors.white, fontSize: 8)),
                ),
              ],
            ),
          ),

          Positioned(
            left: _fabPosition.dx,
            top: _fabPosition.dy - 150,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton(
                  mini: true,
                  backgroundColor: Colors.blue,
                  onPressed: () {
                    setState(() => _isFabExpanded = false);
                    _showControlPanel(widget.navigatorKey?.currentContext ?? context, manager);
                  },
                  child: const Icon(Icons.list, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(179),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('VIEW', style: TextStyle(color: Colors.white, fontSize: 8)),
                ),
              ],
            ),
          ),
        ],
        Positioned(
          left: _fabPosition.dx,
          top: _fabPosition.dy,
          child: _buildDraggableFab(context),
        ),
      ],
    );
  }

  Widget _buildStopFab(BuildContext context, SelfTestManager manager) {
    debugPrint('[SelfTest] Building stop FAB');
    return Positioned(
      left: _fabPosition.dx,
      top: _fabPosition.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            final screenSize = MediaQuery.of(context).size;
            _fabPosition = _clampFabPosition(_fabPosition + details.delta, screenSize);
          });
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: FloatingActionButton(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                onPressed: () {
                  manager.stopRecording();
                  manager.setRecordingMode(RecordingMode.viewing);
                  _showControlPanel(widget.navigatorKey?.currentContext ?? context, manager);
                  if ((widget.navigatorKey?.currentContext ?? context).mounted) {
                    ScaffoldMessenger.of(widget.navigatorKey?.currentContext ?? context).showSnackBar(
                      const SnackBar(content: Text('Recording stopped')),
                    );
                  }
                },
                child: const Icon(Icons.stop, size: 32),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(179),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('STOP', style: TextStyle(color: Colors.white, fontSize: 10)),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _showNameDialog(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Test Script'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Enter script name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Start'),
          ),
        ],
      ),
    );
  }

  Future<void> _showControlPanel(BuildContext ctx, SelfTestManager manager) async {
    // Initialize database if needed
    await manager.initializeRecordingStore();

    if (!mounted) return;

    // Use navigator key context if available, otherwise use this state's context
    final dialogContext = widget.navigatorKey?.currentContext ?? context;
    if (!dialogContext.mounted) return;

    showModalBottomSheet(
      context: dialogContext,
      builder: (_) => ControlPanel(manager: manager),
    );
  }
}
