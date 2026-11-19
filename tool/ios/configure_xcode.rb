# frozen_string_literal: true

require 'xcodeproj'

ROOT = File.expand_path(ARGV[0] || File.join(__dir__, '..', '..'))
PROJECT_PATH = File.join(ROOT, 'ios', 'Runner.xcodeproj')

COMPILED = %w[.swift .c .m].freeze
HEADERS = %w[.h].freeze

# Each entry: target, the group that holds the managed folders, and the folders.
MANAGED = [
  { target: 'Runner', group: 'Runner', folders: %w[Fetchr Pigeon], compiled: COMPILED },
  { target: 'RunnerTests', group: 'RunnerTests', folders: %w[Fetchr], compiled: %w[.swift] }
].freeze

FIXTURE_NAME = 'info'
FIXTURE_PATH = '../../android/app/src/test/resources/info'

def find_group(parent, attr, value)
  parent.children.find { |c| c.isa == 'PBXGroup' && c.public_send(attr) == value }
end

def sub_group(parent, name)
  find_group(parent, :path, name) || parent.new_group(name, name)
end

def file_ref(group, path)
  group.files.find { |f| f.path == File.basename(path) } || group.new_reference(File.basename(path))
end

def sync_dir(group, dir, target, compiled)
  entries = Dir.children(dir).sort
  entries.each do |name|
    full = File.join(dir, name)
    if File.directory?(full)
      sync_dir(sub_group(group, name), full, target, compiled)
    else
      ext = File.extname(name)
      next unless compiled.include?(ext) || HEADERS.include?(ext)

      ref = file_ref(group, full)
      next unless compiled.include?(ext)

      target.source_build_phase.add_file_reference(ref, true)
    end
  end
end

# Removes references whose file is gone (with their build files), then the group if it ends up empty.
# Generated files (GeneratedPluginRegistrant.m) sit outside the managed folders and are never visited.
def prune_stale_refs(group)
  group.children.dup.each do |child|
    if child.isa == 'PBXGroup'
      prune_stale_refs(child)
    elsif child.isa == 'PBXFileReference' && (COMPILED + HEADERS).include?(File.extname(child.path.to_s)) &&
          !File.exist?(child.real_path)
      child.remove_from_project
    end
  end
  group.remove_from_project if group.children.empty?
end

def sync_fixture(project, target)
  group = project.main_group.children.find { |c| c.path == 'RunnerTests' } or abort('no RunnerTests group')
  ref = group.files.find { |f| f.path == FIXTURE_PATH } || group.new_reference(FIXTURE_PATH)
  ref.name = FIXTURE_NAME
  ref.last_known_file_type = 'folder'
  target.resources_build_phase.add_file_reference(ref, true)
end

PYTHON_XCFRAMEWORK = 'Python.xcframework'
PYTHON_PHASE = 'Process Python libraries'
PYTHON_SCRIPT = "bash \"$PROJECT_DIR/../tool/ios/install_python.sh\"\n"

# Appended after what is there; $(inherited) first so the Flutter and Pods xcconfigs still apply.
PYTHON_LIST_SETTINGS = {
  'FRAMEWORK_SEARCH_PATHS' => ['$(inherited)', '$(PROJECT_DIR)'],
  'HEADER_SEARCH_PATHS' => ['$(inherited)', '"$(BUILT_PRODUCTS_DIR)/Python.framework/Headers"']
}.freeze
PYTHON_SETTINGS = {
  'ENABLE_TESTABILITY' => 'YES',
  'CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER' => 'NO',
  'ENABLE_USER_SCRIPT_SANDBOXING' => 'NO'
}.freeze

def python_ref(project)
  group = find_group(project.main_group, :display_name, 'Frameworks') or
    abort('no Frameworks group')
  ref = group.files.find { |f| f.path == PYTHON_XCFRAMEWORK } || group.new_reference(PYTHON_XCFRAMEWORK)
  ref.last_known_file_type = 'wrapper.xcframework'
  ref.source_tree = '<group>'
  ref
end

def embed_framework(target, ref)
  target.frameworks_build_phase.add_file_reference(ref, true)
  embed = target.copy_files_build_phases.find { |p| p.name == 'Embed Frameworks' } or abort('no Embed Frameworks phase')
  build_file = embed.add_file_reference(ref, true)
  build_file.settings = { 'ATTRIBUTES' => %w[CodeSignOnCopy RemoveHeadersOnCopy] }
end

FFMPEG_DIR = 'Frameworks/ffmpegkit'
FFMPEG_XCFRAMEWORKS = %w[ffmpegkit libavcodec libavdevice libavfilter libavformat libavutil libswresample libswscale]
                      .map { |n| "#{n}.xcframework" }.freeze

# A fixed list, like Python.xcframework, so a clone that has not run build_ffmpeg.sh yet configures to
# the same project; a build that produces another framework stops here until it is listed.
def ffmpeg_refs(project)
  built = Dir.glob(File.join(ROOT, 'ios', FFMPEG_DIR, '*.xcframework')).map { |p| File.basename(p) }
  extra = built - FFMPEG_XCFRAMEWORKS
  abort("configure_xcode: add #{extra.join(', ')} to FFMPEG_XCFRAMEWORKS") unless extra.empty?

  frameworks = find_group(project.main_group, :display_name, 'Frameworks') or
    abort('no Frameworks group')
  group = find_group(frameworks, :path, FFMPEG_DIR) ||
          frameworks.new_group('ffmpegkit', FFMPEG_DIR)
  FFMPEG_XCFRAMEWORKS.map do |name|
    ref = group.files.find { |f| f.path == name } || group.new_reference(name)
    ref.last_known_file_type = 'wrapper.xcframework'
    ref.source_tree = '<group>'
    ref
  end
end

def link_system_framework(target, name)
  return if target.frameworks_build_phase.files.any? { |f| f.display_name == "#{name}.framework" }

  target.add_system_framework(name)
end

# install_python.sh installs one architecture's extension modules, and `flutter build ios --simulator`
# builds arm64 and x86_64 unless told otherwise. RunnerTests is excluded too, to match its host app.
SIMULATOR_ARCH_SETTINGS = { 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => ['$(inherited)', 'x86_64'] }.freeze

def list_settings(target, lists)
  target.build_configurations.each do |config|
    settings = config.build_settings
    lists.each do |key, wanted|
      # xcodeproj saves some list settings (EXCLUDED_ARCHS) as one space-separated string.
      current = settings[key].is_a?(String) ? settings[key].split(' ') : Array(settings[key])
      settings[key] = current + (wanted - current)
    end
  end
end

def python_settings(target)
  list_settings(target, PYTHON_LIST_SETTINGS)
  target.build_configurations.each do |config|
    settings = config.build_settings
    settings.merge!(PYTHON_SETTINGS)
  end
end

# CPython's script must run once resources are copied and before frameworks are embedded and signed.
def python_phase(target)
  phase = target.shell_script_build_phases.find { |p| p.name == PYTHON_PHASE } ||
          target.new_shell_script_build_phase(PYTHON_PHASE)
  phase.shell_path = '/bin/sh'
  phase.shell_script = PYTHON_SCRIPT
  phase.always_out_of_date = '1'
  phase.input_paths = []
  phase.output_paths = []

  phases = target.build_phases
  resources = phases.index(target.resources_build_phase) or abort('no Resources phase')
  return if phases.index(phase) == resources + 1

  phases.delete(phase)
  phases.insert(phases.index(target.resources_build_phase) + 1, phase)
end

def check_python_order(target)
  names = target.build_phases.map(&:display_name)
  py = names.index(PYTHON_PHASE)
  later = ['Embed Frameworks', 'Thin Binary']
  return if later.all? { |n| (names.index(n) or abort("no #{n} phase")) > py }

  abort("#{PYTHON_PHASE} must run before #{later.join(' and ')}: #{names.inspect}")
end

SHARE_TARGET = 'ShareExtension'
SHARE_FILES = %w[ShareViewController.swift Info.plist ShareExtension.entitlements].freeze
GROUP_ID = 'group.com.defo.fetchr'

# The share extension: a link shared from another app lands in the App Group the receive_sharing_intent plugin
# reads, then opens Fetchr. It takes ShareExtension.xcconfig (Flutter's version numbers and the signing team, never
# the Pods settings) and is embedded before Thin Binary, as the plugin asks.
def share_extension(project, runner)
  group = sub_group(project.main_group, SHARE_TARGET)
  refs = SHARE_FILES.to_h { |name| [name, file_ref(group, name)] }
  flutter = find_group(project.main_group, :display_name, 'Flutter') or
    abort('no Flutter group')
  # The Flutter group has no path of its own; its references carry "Flutter/".
  xcconfig = flutter.files.find { |f| File.basename(f.path.to_s) == 'ShareExtension.xcconfig' } ||
             flutter.new_reference('Flutter/ShareExtension.xcconfig')
  xcconfig.path = 'Flutter/ShareExtension.xcconfig'

  target = project.targets.find { |t| t.name == SHARE_TARGET } ||
           project.new_target(:app_extension, SHARE_TARGET, :ios, '26.0', nil, :swift)
  target.source_build_phase.files.each { |f| f.remove_from_project unless f.file_ref == refs['ShareViewController.swift'] }
  target.source_build_phase.add_file_reference(refs['ShareViewController.swift'], true)
  project.build_configurations.map(&:name).each do |name|
    config = target.build_configuration_list[name] || target.add_build_configuration(name, name == 'Debug' ? :debug : :release)
    config.base_configuration_reference = xcconfig
    config.build_settings.merge!(
      'INFOPLIST_FILE' => "#{SHARE_TARGET}/Info.plist",
      'CODE_SIGN_ENTITLEMENTS' => "#{SHARE_TARGET}/ShareExtension.entitlements",
      'PRODUCT_BUNDLE_IDENTIFIER' => 'com.defo.fetchr.ShareExtension',
      'PRODUCT_NAME' => '$(TARGET_NAME)',
      'CUSTOM_GROUP_ID' => GROUP_ID,
      'GENERATE_INFOPLIST_FILE' => 'NO',
      'IPHONEOS_DEPLOYMENT_TARGET' => '26.0',
      'SWIFT_VERSION' => '5.0',
      'TARGETED_DEVICE_FAMILY' => '1,2',
      'SKIP_INSTALL' => 'YES',
      'CODE_SIGN_STYLE' => 'Automatic',
      'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
    )
  end

  runner.build_configurations.each do |config|
    config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
    config.build_settings['CUSTOM_GROUP_ID'] = GROUP_ID
  end
  runner_group = find_group(project.main_group, :path, 'Runner')
  file_ref(runner_group, 'Runner.entitlements')

  runner.add_dependency(target) unless runner.dependencies.any? { |d| d.target == target }
  embed = runner.copy_files_build_phases.find { |p| p.name == 'Embed Foundation Extensions' } ||
          runner.new_copy_files_build_phase('Embed Foundation Extensions')
  embed.dst_subfolder_spec = '13'
  embed.dst_path = ''
  unless embed.files_references.include?(target.product_reference)
    build_file = embed.add_file_reference(target.product_reference, true)
    build_file.settings = { 'ATTRIBUTES' => %w[RemoveHeadersOnCopy] }
  end
  # The plugin's guide: embedding after Thin Binary makes a build cycle.
  phases = runner.build_phases
  thin = phases.find { |p| p.respond_to?(:name) && p.name == 'Thin Binary' }
  return unless thin && phases.index(embed) > phases.index(thin)

  phases.delete(embed)
  phases.insert(phases.index(thin), embed)
end

project = Xcodeproj::Project.open(PROJECT_PATH)
before = project.to_hash

MANAGED.each do |cfg|
  target = project.targets.find { |t| t.name == cfg[:target] } or abort("no target #{cfg[:target]}")
  top = find_group(project.main_group, :path, cfg[:group]) or
    abort("no group #{cfg[:group]}")
  cfg[:folders].each do |folder|
    dir = File.join(ROOT, 'ios', cfg[:group], folder)
    next unless File.directory?(dir)

    sync_dir(sub_group(top, folder), dir, target, cfg[:compiled])
  end
  cfg[:folders].each do |folder|
    sub = find_group(top, :path, folder) or next
    prune_stale_refs(sub)
  end
end

sync_fixture(project, project.targets.find { |t| t.name == 'RunnerTests' })

runner = project.targets.find { |t| t.name == 'Runner' }
embed_framework(runner, python_ref(project))
ffmpeg_refs(project).each { |ref| embed_framework(runner, ref) }
link_system_framework(runner, 'JavaScriptCore')
python_settings(runner)
[runner, project.targets.find { |t| t.name == 'RunnerTests' }].each { |t| list_settings(t, SIMULATOR_ARCH_SETTINGS) }
python_phase(runner)
check_python_order(runner)
share_extension(project, runner)

if project.to_hash == before
  puts 'configure_xcode: no changes'
else
  project.save
  puts 'configure_xcode: project updated'
end
