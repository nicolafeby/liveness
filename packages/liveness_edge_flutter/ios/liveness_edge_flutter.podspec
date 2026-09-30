#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint liveness_edge_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'liveness_edge_flutter'
  s.version          = '0.0.1'
  s.summary          = 'Private on-device face-liveness verification for Flutter.'
  s.description      = <<-DESC
MediaPipe face landmarks and ONNX Runtime anti-spoofing, entirely on device.
                       DESC
  s.homepage         = 'https://github.com/nicolafeby/liveness'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Muhammad Nicola Feby Salvaturi' => 'opensource@invalid.example' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency 'MediaPipeTasksVision', '~> 0.10.26'
  s.dependency 'onnxruntime-objc', '~> 1.22.0'
  s.resources = 'Assets/*'
  s.static_framework = true
  s.platform = :ios, '15.1'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  s.resource_bundles = {
    'liveness_edge_flutter_privacy' => ['Resources/PrivacyInfo.xcprivacy']
  }
end
