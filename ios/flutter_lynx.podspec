Pod::Spec.new do |s|
  s.name             = "flutter_lynx"
  s.version          = "0.1.0"
  s.summary          = "Lynx dynamic mini-program engine and container for Flutter applications."
  s.description      = <<-DESC
Lynx dynamic mini-program engine and container for Flutter applications.
                       DESC
  s.homepage         = "https://github.com/kmanager/flutter_lynx"
  s.license          = { :file => "../LICENSE" }
  s.author           = { "KManager Team" => "dev@kmanager.com" }
  s.source           = { :path => "." }
  s.source_files = "Classes/**/*.{h,m,mm}"
  s.public_header_files = "Classes/FlutterLynxPlugin.h"
  s.dependency "Flutter"
  s.platform = :ios, "12.0"

  # Official stable 4.1 stack. Host Podfile must also declare lynx-family Specs.
  # Image only; no HTTP/Log/DevTool service.
  s.dependency "Lynx/Framework", "4.1.0"
  s.dependency "PrimJS/quickjs", "4.1.1"
  s.dependency "PrimJS/napi", "4.1.1"
  s.dependency "LynxService/Image", "4.1.0"
  s.dependency "SDWebImage", "5.15.5"
  s.dependency "SDWebImageWebPCoder", "0.11.0"

  # Flutter.framework does not contain an i386 slice.
  s.pod_target_xcconfig = { "DEFINES_MODULE" => "YES", "EXCLUDED_ARCHS[sdk=iphonesimulator*]" => "i386" }
end
