import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_lynx_platform_interface.dart';

/// An implementation of [FlutterLynxPlatform] that uses method channels.
class MethodChannelFlutterLynx extends FlutterLynxPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_lynx');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
