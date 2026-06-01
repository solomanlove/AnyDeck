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

  # If your plugin requires a privacy manifest, for example if it collects user
  # data, update the PrivacyInfo.xcprivacy file to describe your plugin's
  # privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'scrcpy_flutter_privacy' => ['Resources/PrivacyInfo.xcprivacy']}

  s.dependency 'FlutterMacOS'
  s.frameworks = 'FlutterMacOS'

  s.platform = :osx, '10.11'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'HEADER_SEARCH_PATHS' => '"/opt/homebrew/opt/ffmpeg/include"',
    'LIBRARY_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/Libs"',
    'OTHER_LDFLAGS' => '$(inherited) -lavcodec -lavformat -lavutil -lswscale'
  }
  s.vendored_libraries = 'Libs/*.dylib'
  s.swift_version = '5.0'
end
