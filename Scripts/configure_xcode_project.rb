require 'xcodeproj'

project_path = File.expand_path('../GasPhotoIOS.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)
config_group = project.main_group.groups.find { |group| group.display_name == 'Config' }
config_group ||= project.main_group.new_group('Config', 'Config')
configuration_references = %w[Debug Release].to_h do |name|
  path = File.expand_path("../Config/#{name}.xcconfig", __dir__)
  reference = config_group.files.find { |file| file.path == "#{name}.xcconfig" }
  reference ||= config_group.new_file(path)
  [name, reference]
end

unless config_group.files.any? { |file| file.path == 'BuildSettings.xcconfig' }
  config_group.new_file(File.expand_path('../Config/BuildSettings.xcconfig', __dir__))
end

app_target = project.targets.find { |target| target.name == 'GasPhotoIOS' }
raise 'Missing app target' unless app_target

app_target.build_configurations.each do |configuration|
  configuration.base_configuration_reference = configuration_references.fetch(configuration.name)
  configuration.build_settings.delete('PRODUCT_BUNDLE_IDENTIFIER')
  configuration.build_settings.delete('IPHONEOS_DEPLOYMENT_TARGET')
  configuration.build_settings.delete('SWIFT_VERSION')
  configuration.build_settings.delete('SWIFT_STRICT_CONCURRENCY')
end

project.save
