require 'xcodeproj'

project_path = File.expand_path('../GasPhotoIOS.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)
app_target = project.targets.find { |target| target.name == 'GasPhotoIOS' }
test_target = project.targets.find { |target| target.name == 'GasPhotoIOSTests' }

abort 'GasPhotoIOS target missing' unless app_target
abort 'GasPhotoIOSTests target missing' unless test_target

scheme = Xcodeproj::XCScheme.new
scheme.configure_with_targets(app_target, test_target, launch_target: true)
scheme.save_as(project_path, 'GasPhotoIOS', true)
