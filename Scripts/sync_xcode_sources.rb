require 'xcodeproj'
require 'set'

project_path = File.expand_path('../GasPhotoIOS.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

def sync_sources(project, group_name, directory, target_name)
  target = project.targets.find { |candidate| candidate.name == target_name }
  group = project.main_group.groups.find { |candidate| candidate.display_name == group_name }
  raise "Missing target: #{target_name}" unless target
  raise "Missing group: #{group_name}" unless group

  known_paths = group.recursive_children
    .filter_map { |child| child.real_path.to_s if child.respond_to?(:real_path) }
    .to_set

  Dir.glob(File.join(directory, '**', '*.swift')).sort.each do |path|
    next if known_paths.include?(path)

    reference = group.new_file(path)
    target.source_build_phase.add_file_reference(reference)
  end

  Dir.glob(File.join(directory, '**', '*.onnx')).sort.each do |path|
    next if known_paths.include?(path)

    reference = group.new_file(path)
    target.resources_build_phase.add_file_reference(reference)
  end
end

sync_sources(project, 'GasPhotoIOS', File.expand_path('../GasPhotoIOS', __dir__), 'GasPhotoIOS')
sync_sources(project, 'GasPhotoIOSTests', File.expand_path('../GasPhotoIOSTests', __dir__), 'GasPhotoIOSTests')
project.save
