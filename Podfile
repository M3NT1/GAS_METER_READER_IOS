platform :ios, '26.0'
use_frameworks! :linkage => :static

target 'GasPhotoIOS' do
  pod 'onnxruntime-training-objc', '1.19.2'
end

target 'GasPhotoIOSTests' do
  inherit! :search_paths
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      if config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'].to_f < 15.0
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
      end
    end
  end
end
