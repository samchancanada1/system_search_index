Pod::Spec.new do |s|
  s.name             = 'system_search_index'
  s.version          = '0.1.0'
  s.summary          = 'Spotlight indexing, semantic search, suggestions, and activation events.'
  s.description      = 'On-device Flutter search backed by Core Spotlight, including iOS 18 semantic queries.'
  s.homepage         = 'https://github.com/samchancanada1/system_search_index'
  s.license          = { :file => '../LICENSE' }
  s.author           = 'Tungworks'
  s.source           = { :path => '.' }
  s.source_files     = 'system_search_index/Sources/system_search_index/**/*.swift'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.frameworks       = 'CoreSpotlight', 'UniformTypeIdentifiers'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
  s.resource_bundles = { 'system_search_index_privacy' => ['system_search_index/Sources/system_search_index/PrivacyInfo.xcprivacy'] }
end
