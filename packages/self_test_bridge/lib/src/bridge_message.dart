// The envelope every message on the bridge socket travels in.
//
// Split out of bridge_commands.dart, which had grown to hold the wire
// format, the command catalogue and the mock value types at once.

/// Command sent from MCP server to Flutter app
class BridgeCommand {
  final int id;
  final String command;
  final Map<String, dynamic> params;

  BridgeCommand({
    required this.id,
    required this.command,
    required this.params,
  });

  factory BridgeCommand.fromJson(Map<String, dynamic> json) {
    return BridgeCommand(
      id: json['id'] as int,
      command: json['command'] as String,
      params: (json['params'] as Map<String, dynamic>?) ?? {},
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'command': command,
    'params': params,
  };
}

/// Response sent from Flutter app to MCP server
class BridgeResponse {
  final int id;
  final dynamic result;
  final String? error;

  BridgeResponse({required this.id, this.result, this.error});

  factory BridgeResponse.fromJson(Map<String, dynamic> json) {
    return BridgeResponse(
      id: json['id'] as int,
      result: json['result'],
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'id': id};
    if (error != null) {
      json['error'] = error;
    } else {
      json['result'] = result;
    }
    return json;
  }
}
