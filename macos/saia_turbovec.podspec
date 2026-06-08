Pod::Spec.new do |s|
  s.name             = 'saia_turbovec'
  s.version          = '1.0.0'
  s.summary          = 'Native bindings for turbovec FFI'
  s.description      = 'Native bindings for turbovec FFI'
  s.homepage         = 'https://github.com/Open-Neom'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Open-Neom' => 'info@openneom.org' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.11'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
  s.vendored_libraries = 'libturbovec.dylib'
end
