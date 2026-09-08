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
  s.source_files = "Classes/**/*"
  s.dependency "Flutter"
  s.platform = :ios, "12.0"

  # Flutter.framework does not contain an i386 slice.
  s.pod_target_xcconfig = { "DEFINES_MODULE" => "YES", "EXCLUDED_ARCHS[sdk=iphonesimulator*]" => "i386" }
  s.swift_version = "5.0"
end
