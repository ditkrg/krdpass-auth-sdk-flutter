#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint krdpass_auth.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'krdpass_auth_flutter'
  s.version          = '1.0.0'
  s.summary          = 'Flutter SDK for Sign in with KRDPass OAuth authentication'
  s.description      = <<-DESC
A Flutter plugin for integrating Sign in with KRDPass OAuth authentication.
                       DESC
  s.homepage         = 'https://github.com/ditkrg/krdpass-auth-sdk'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'KRDPass' => 'integration@pass.krd' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency 'KrdpassAuth', '~> 1.0'
  s.platform = :ios, '15.5'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
