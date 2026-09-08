import "dart:convert";

/// Data passed into the Lynx template during initialization or runtime updates.
class LynxTemplateData {
  final Map<String, dynamic> data;

  const LynxTemplateData(this.data);

  factory LynxTemplateData.empty() => const LynxTemplateData({});

  factory LynxTemplateData.fromJson(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, dynamic>) {
        return LynxTemplateData(decoded);
      }
    } catch (_) {}
    return const LynxTemplateData({});
  }

  Map<String, dynamic> toMap() => data;

  String toJson() => jsonEncode(data);

  LynxTemplateData copyWith(Map<String, dynamic> other) {
    return LynxTemplateData({...data, ...other});
  }

  @override
  String toString() => "LynxTemplateData(${toJson()})";
}
