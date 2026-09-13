#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint scrcpy_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'scrcpy_flutter'
  s.version          = '0.0.1'
  s.summary          = 'A new Flutter plugin project.'
  s.description      = <<-DESC
A new Flutter plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }

  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'

  s.dependency 'FlutterMacOS'
  s.frameworks = 'FlutterMacOS', 'AudioToolbox', 'VideoToolbox', 'CoreMedia', 'CoreVideo'

  s.platform = :osx, '11.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'LIBRARY_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/Libs"'
  }
  s.vendored_libraries = 'Libs/librust_scrcpy.a'
  s.swift_version = '5.0'
end
