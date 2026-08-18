Pod::Spec.new do |s|
  s.name             = 'krdpass_auth_flutter'
  s.version           = '1.6.0'
  s.summary          = 'Flutter SDK for Sign in with KRDPASS OAuth authentication'
  s.description      = <<-DESC
KRDPASS Auth SDK for Flutter. Handles app-to-app OAuth sign-in and deep link callbacks.
                       DESC
  s.homepage         = 'https://github.com/ditkrg/krdpass-auth-sdk-flutter'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'KRDPASS' => 'integration@pass.krd' }
  s.source           = { :path => '.' }
  s.source_files = 'krdpass_auth_flutter/Sources/krdpass_auth_flutter/**/*.swift'
  s.dependency 'Flutter'
  # The native core is a GitHub repository, not a trunk pod, so a CocoaPods-based
  # app must supply the source in its Podfile:
  #
  #   pod 'KrdpassAuth',
  #     git: 'https://github.com/ditkrg/krdpass-auth-sdk-ios.git',
  #     tag: 'v1.6.0'
  #
  # Apps on Swift Package Manager resolve it from Package.swift instead and need
  # no Podfile entry.
  s.dependency 'KrdpassAuth', '1.6.0'
  s.platform = :ios, '15.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '6.0'
end
