/// Event dispatched between Flutter host and Lynx template.
class LynxEvent {
  final String name;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  LynxEvent({
    required this.name,
    this.data = const {},
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      "name": name,
      "data": data,
      "timestamp": timestamp.millisecondsSinceEpoch,
    };
  }

  factory LynxEvent.fromMap(Map<String, dynamic> map) {
    return LynxEvent(
      name: map["name"] as String? ?? "",
      data: Map<String, dynamic>.from(map["data"] as Map? ?? {}),
      timestamp: map["timestamp"] != null
          ? DateTime.fromMillisecondsSinceEpoch(map["timestamp"] as int)
          : null,
    );
  }
}
