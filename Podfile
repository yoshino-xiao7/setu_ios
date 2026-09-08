source 'https://cdn.cocoapods.org/'
platform :ios, '17.0'
project 'SetuIOSApp.xcodeproj'

target 'SetuIOSApp' do
  pod 'MobileVLCKit', '3.7.3'
  pod 'KTVHTTPCache', '3.1.0'

  target 'SetuVLCIntegrationTests' do
    inherit! :search_paths
  end

  target 'SetuIOSAppTests' do
    inherit! :search_paths
  end
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
      config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
    end
  end
end
