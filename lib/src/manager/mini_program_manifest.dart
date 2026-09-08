import "dart:convert";

/// Manifest definition for a dynamic Lynx mini program.
class MiniProgramManifest {
  final String appId;
  final String name;
  final String version;
  final String bundleUrl;
  final String? description;
  final String? icon;
  final String? md5;
  final Map<String, dynamic>? initialData;
  final Map<String, dynamic>? extra;

  const MiniProgramManifest({
    required this.appId,
    required this.name,
    required this.version,
    required this.bundleUrl,
    this.description,
    this.icon,
    this.md5,
    this.initialData,
    this.extra,
  });

  factory MiniProgramManifest.fromMap(Map<String, dynamic> map) {
    return MiniProgramManifest(
      appId: map["appId"] as String? ?? "",
      name: map["name"] as String? ?? "",
      version: map["version"] as String? ?? "1.0.0",
      bundleUrl: map["bundleUrl"] as String? ?? "",
      description: map["description"] as String?,
      icon: map["icon"] as String?,
      md5: map["md5"] as String?,
      initialData: map["initialData"] != null
          ? Map<String, dynamic>.from(map["initialData"] as Map)
          : null,
      extra: map["extra"] != null
          ? Map<String, dynamic>.from(map["extra"] as Map)
          : null,
    );
  }

  factory MiniProgramManifest.fromJson(String jsonStr) {
    return MiniProgramManifest.fromMap(
      jsonDecode(jsonStr) as Map<String, dynamic>,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "appId": appId,
      "name": name,
      "version": version,
      "bundleUrl": bundleUrl,
      if (description != null) "description": description,
      if (icon != null) "icon": icon,
      if (md5 != null) "md5": md5,
      if (initialData != null) "initialData": initialData,
      if (extra != null) "extra": extra,
    };
  }

  String toJson() => jsonEncode(toMap());
}
