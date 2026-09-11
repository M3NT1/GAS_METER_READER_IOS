require 'xcodeproj'

project_path = File.expand_path('../GasPhotoIOS.xcodeproj', __dir__)
project = Xcodeproj::Project.new(project_path)

app_target = project.new_target(:application, 'GasPhotoIOS', :ios, '26.0')
test_target = project.new_target(:unit_test_bundle, 'GasPhotoIOSTests', :ios, '26.0')
test_target.add_dependency(app_target)

[app_target, test_target].each do |target|
  target.build_configurations.each do |configuration|
    configuration.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '26.0'
    configuration.build_settings['SWIFT_VERSION'] = '6.0'
    configuration.build_settings['SWIFT_STRICT_CONCURRENCY'] = 'complete'
    configuration.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  end
end

app_target.build_configurations.each do |configuration|
  configuration.build_settings['TARGETED_DEVICE_FAMILY'] = '1'
end

test_target.build_configurations.each do |configuration|
  configuration.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'hu.m3nt1.gasphoto.ios.tests'
  configuration.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/GasPhotoIOS.app/GasPhotoIOS'
  configuration.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
end

app_group = project.main_group.new_group('GasPhotoIOS', 'GasPhotoIOS')
Dir.glob(File.expand_path('../GasPhotoIOS/**/*.swift', __dir__)).sort.each do |path|
  reference = app_group.new_file(path)
  app_target.source_build_phase.add_file_reference(reference)
end

test_group = project.main_group.new_group('GasPhotoIOSTests', 'GasPhotoIOSTests')
Dir.glob(File.expand_path('../GasPhotoIOSTests/**/*.swift', __dir__)).sort.each do |path|
  reference = test_group.new_file(path)
  test_target.source_build_phase.add_file_reference(reference)
end

project.save

scheme = Xcodeproj::XCScheme.new
scheme.configure_with_targets(app_target, test_target, launch_target: true)
scheme.save_as(project_path, 'GasPhotoIOS', true)
