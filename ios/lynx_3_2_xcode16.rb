# Official Lynx 3.2.0 / PrimJS 2.12.0 cannot compile on Xcode 16.3+
# (lynx-family/lynx#892, #1398). Hosts must call this from Podfile post_install.
# Do not bump Lynx or PrimJS here; keep the 3.2 lock used by Android.
# Apple Clang 17 treats both C-style and reinterpret_cast function-pointer
# conversions as errors, so the header is rewritten to a union type-pun.

def clang_compat_cflags
  '$(inherited) -Wno-cast-function-type-strict -Wno-cast-function-type-mismatch -Wno-vla -Wno-vla-cxx-extension -Wno-gnu-folding-constant -Wno-macro-redefined -Wno-enum-compare -Wno-enum-compare-conditional'
end

def clang_compat_cxxflags
  "#{clang_compat_cflags} -Wno-deprecated-declarations -Wno-deprecated-builtins"
end

def apply_lynx_3_2_xcode16_compat(installer)
  patch_primjs_function_cast!(installer)
  patch_lynx_background_renderer_vla!(installer)
  patch_lynx_core_js_bundle!(installer)
  patch_lynx_warning_xcconfigs!(installer)
  patch_file_compiler_flags!(installer)
  exclude_simulator_x86 = `uname -m`.strip == 'arm64'
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      if exclude_simulator_x86
        config.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = 'i386 x86_64'
      end
      next unless target.name.start_with?('PrimJS', 'Lynx', 'LynxService', 'flutter_lynx')
      config.build_settings['CLANG_CXX_LANGUAGE_STANDARD'] = 'gnu++17'
      config.build_settings['GCC_TREAT_WARNINGS_AS_ERRORS'] = 'NO'
      config.build_settings['OTHER_CFLAGS'] = "#{clang_compat_cflags} #{config.build_settings['OTHER_CFLAGS']}".strip
      config.build_settings['OTHER_CPLUSPLUSFLAGS'] = "#{clang_compat_cxxflags} #{config.build_settings['OTHER_CPLUSPLUSFLAGS']}".strip
    end
  end
  return unless exclude_simulator_x86

  installer.aggregate_targets.each do |aggregate|
    aggregate.user_project.native_targets.each do |target|
      target.build_configurations.each do |config|
        config.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = 'i386 x86_64'
      end
    end
    aggregate.user_project.save
  end
end

def patch_primjs_function_cast!(installer)
  header = File.join(installer.sandbox.root, 'PrimJS/src/interpreter/quickjs/include/quickjs.h')
  return unless File.exist?(header)

  contents = File.read(header)
  return if contents.include?('fn.magic_fn = func')

  replacement = <<~'C'.chomp
      union {
        LEPUSCFunctionMagic *magic_fn;
        LEPUSCFunction *generic_fn;
      } fn;
      fn.magic_fn = func;
      return LEPUS_NewCFunction2(ctx, fn.generic_fn, name, length, cproto,
                                 magic);
  C

  patterns = [
    "  return LEPUS_NewCFunction2(ctx, (LEPUSCFunction *)func, name, length, cproto,\n                             magic);",
    "  return LEPUS_NewCFunction2(ctx, reinterpret_cast<LEPUSCFunction *>(func), name, length, cproto,\n                             magic);"
  ]

  replaced = patterns.any? do |old|
    next false unless contents.include?(old)
    contents = contents.sub(old, replacement)
    true
  end
  raise 'PrimJS quickjs.h Xcode 16.3 patch did not match LEPUS_NewCFunctionMagic' unless replaced

  File.chmod(0o644, header)
  File.write(header, contents)
end

def patch_lynx_background_renderer_vla!(installer)
  header = File.join(
    installer.sandbox.root,
    'Lynx/lynx/platform/darwin/ios/lynx/public/base/background/LynxBackgroundRenderer.h'
  )
  return unless File.exist?(header)

  contents = File.read(header)
  return if contents.include?('enum { sides = 4 }')

  old = '  const int sides = 4;'
  raise 'LynxBackgroundRenderer.h Xcode 16.3 VLA patch did not match' unless contents.include?(old)

  File.chmod(0o644, header)
  File.write(header, contents.sub(old, '  enum { sides = 4 };'))
end

def patch_lynx_core_js_bundle!(installer)
  source = File.join(installer.sandbox.root, 'Lynx/lynx/core/resource/lynx_resource_loader_darwin.mm')
  return unless File.exist?(source)

  contents = File.read(source)
  return if contents.include?('bundleForClass:[LynxEnv class]')

  old = '  NSBundle* frameworkBundle = [NSBundle mainBundle];'
  raise 'lynx_resource_loader_darwin.mm LynxResources bundle patch did not match' unless contents.include?(old)

  File.chmod(0o644, source)
  File.write(source, contents.sub(old, '  NSBundle* frameworkBundle = [NSBundle bundleForClass:[LynxEnv class]];'))
end

def patch_lynx_warning_xcconfigs!(installer)
  pattern = File.join(installer.sandbox.root, 'Target Support Files/{Lynx,LynxService,PrimJS}/*.xcconfig')
  Dir.glob(pattern).each do |path|
    text = File.read(path)
    next if text.include?('-Wno-vla-cxx-extension')
    next unless text.match?(/^OTHER_CPLUSPLUSFLAGS = /)

    text = text.sub(
      /^OTHER_CPLUSPLUSFLAGS = (.*)$/,
      "OTHER_CPLUSPLUSFLAGS = #{clang_compat_cxxflags} \\1"
    )
    File.chmod(0o644, path)
    File.write(path, text)
  end
end

def patch_file_compiler_flags!(installer)
  extra = '-Wno-vla -Wno-vla-cxx-extension -Wno-gnu-folding-constant -Wno-deprecated-builtins -Wno-deprecated-declarations -Wno-macro-redefined -Wno-enum-compare -Wno-enum-compare-conditional'
  installer.pods_project.targets.each do |target|
    next unless target.name.start_with?('PrimJS', 'Lynx', 'LynxService')
    target.source_build_phase.files.each do |build_file|
      settings = build_file.settings
      next unless settings.is_a?(Hash)
      flags = settings['COMPILER_FLAGS']
      next unless flags.is_a?(String)
      missing = extra.split.reject { |flag| flags.include?(flag) }
      next if missing.empty?
      settings['COMPILER_FLAGS'] = "#{flags} #{missing.join(' ')}"
    end
  end
end
