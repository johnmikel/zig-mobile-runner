#!/usr/bin/env ruby
# frozen_string_literal: true

require 'cgi'
require 'fileutils'
require 'optparse'
require 'pathname'

options = {
  sources: [],
  deployment_target: '15.0',
}

OptionParser.new do |parser|
  parser.banner = 'Usage: ensure-ios-shim-target.rb --project ios/App.xcodeproj --app-target App --test-target AppZMRUITests --scheme AppZMRUITests --bundle-id com.example.app [options]'
  parser.on('--project PATH', 'Xcode project path') { |value| options[:project] = value }
  parser.on('--app-target NAME', 'App target under test') { |value| options[:app_target] = value }
  parser.on('--test-target NAME', 'UI test target to create/update') { |value| options[:test_target] = value }
  parser.on('--scheme NAME', 'Shared UI test scheme to create/update') { |value| options[:scheme] = value }
  parser.on('--bundle-id ID', 'App bundle id under test') { |value| options[:bundle_id] = value }
  parser.on('--test-bundle-id ID', 'UI test bundle id') { |value| options[:test_bundle_id] = value }
  parser.on('--deployment-target VERSION', 'iOS deployment target') { |value| options[:deployment_target] = value }
  parser.on('--source PATH', 'Shim source path relative to app root; repeatable') { |value| options[:sources] << value }
  parser.on('--info-plist PATH', 'Info.plist path relative to app root') { |value| options[:info_plist] = value }
  parser.on('-h', '--help', 'Show help') do
    puts parser
    exit 0
  end
end.parse!

required = %i[project app_target test_target scheme bundle_id test_bundle_id info_plist]
missing = required.select { |key| options[key].to_s.empty? }
missing << :source if options[:sources].empty?
unless missing.empty?
  abort "error: missing required option(s): #{missing.map { |key| "--#{key.to_s.tr('_', '-')}" }.join(', ')}"
end

begin
  require 'xcodeproj'
rescue LoadError
  abort 'error: missing Ruby gem xcodeproj. Install with `gem install xcodeproj` or add it to the app Gemfile.'
end

def app_root
  Pathname.new(Dir.pwd)
end

def project_dir(project)
  Pathname.new(File.dirname(File.expand_path(project.path)))
end

def source_root_relative(project, relative_path)
  absolute = app_root.join(relative_path).expand_path
  absolute.relative_path_from(project_dir(project)).to_s
end

def ensure_file_reference(project, relative_path)
  xcode_path = source_root_relative(project, relative_path)
  existing = project.files.find { |file| file.path == xcode_path || file.path == relative_path }
  if existing
    existing.path = xcode_path
    existing.source_tree = 'SOURCE_ROOT'
    return existing
  end

  file_ref = project.main_group.new_file(xcode_path)
  file_ref.source_tree = 'SOURCE_ROOT'
  file_ref
end

def ensure_source(target, file_ref)
  return if target.source_build_phase.files_references.include?(file_ref)

  target.source_build_phase.add_file_reference(file_ref, true)
end

def ensure_dependency(target, dependency)
  return if target.dependencies.any? { |candidate| candidate.target == dependency }

  target.add_dependency(dependency)
end

def product_name(target)
  target.product_reference&.display_name || "#{target.name}.app"
end

def buildable_reference(target, container)
  <<~XML
    <BuildableReference
       BuildableIdentifier = "primary"
       BlueprintIdentifier = "#{CGI.escapeHTML(target.uuid)}"
       BuildableName = "#{CGI.escapeHTML(product_name(target))}"
       BlueprintName = "#{CGI.escapeHTML(target.name)}"
       ReferencedContainer = "#{CGI.escapeHTML(container)}">
    </BuildableReference>
  XML
end

def write_scheme(project, app_target, test_target, scheme_name)
  scheme_dir = File.join(project.path, 'xcshareddata/xcschemes')
  FileUtils.mkdir_p(scheme_dir)
  scheme_path = File.join(scheme_dir, "#{scheme_name}.xcscheme")
  container = "container:#{File.basename(project.path)}"
  app_ref = buildable_reference(app_target, container)
  test_ref = buildable_reference(test_target, container)

  xml = <<~XML
    <?xml version="1.0" encoding="UTF-8"?>
    <Scheme
       LastUpgradeVersion = "1600"
       version = "1.7">
       <BuildAction
          parallelizeBuildables = "YES"
          buildImplicitDependencies = "YES">
          <BuildActionEntries>
             <BuildActionEntry
                buildForTesting = "YES"
                buildForRunning = "YES"
                buildForProfiling = "YES"
                buildForArchiving = "YES"
                buildForAnalyzing = "YES">
    #{app_ref.rstrip}
             </BuildActionEntry>
             <BuildActionEntry
                buildForTesting = "YES"
                buildForRunning = "NO"
                buildForProfiling = "NO"
                buildForArchiving = "NO"
                buildForAnalyzing = "YES">
    #{test_ref.rstrip}
             </BuildActionEntry>
          </BuildActionEntries>
       </BuildAction>
       <TestAction
          buildConfiguration = "Debug"
          selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
          selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
          shouldUseLaunchSchemeArgsEnv = "YES">
          <Testables>
             <TestableReference skipped = "NO">
    #{test_ref.rstrip}
                <SelectedTests>
                   <Test Identifier = "ZMRShimUITestCase/testRunZMRCommand">
                   </Test>
                </SelectedTests>
             </TestableReference>
          </Testables>
          <MacroExpansion>
    #{app_ref.rstrip}
          </MacroExpansion>
          <EnvironmentVariables>
             <EnvironmentVariable key = "ZMR_SHIM_REQUEST_FILE" value = "$(ZMR_SHIM_REQUEST_FILE)" isEnabled = "YES">
             </EnvironmentVariable>
             <EnvironmentVariable key = "ZMR_SHIM_RESPONSE_FILE" value = "$(ZMR_SHIM_RESPONSE_FILE)" isEnabled = "YES">
             </EnvironmentVariable>
             <EnvironmentVariable key = "ZMR_SHIM_MODE" value = "$(ZMR_SHIM_MODE)" isEnabled = "YES">
             </EnvironmentVariable>
             <EnvironmentVariable key = "ZMR_SHIM_SERVER_DIR" value = "$(ZMR_SHIM_SERVER_DIR)" isEnabled = "YES">
             </EnvironmentVariable>
             <EnvironmentVariable key = "ZMR_APP_BUNDLE_ID" value = "$(ZMR_APP_BUNDLE_ID)" isEnabled = "YES">
             </EnvironmentVariable>
          </EnvironmentVariables>
       </TestAction>
       <LaunchAction
          buildConfiguration = "Debug"
          selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
          selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
          launchStyle = "0"
          useCustomWorkingDirectory = "NO"
          ignoresPersistentStateOnLaunch = "NO"
          debugDocumentVersioning = "YES"
          debugServiceExtension = "internal"
          allowLocationSimulation = "YES">
          <BuildableProductRunnable runnableDebuggingMode = "0">
    #{app_ref.rstrip}
          </BuildableProductRunnable>
       </LaunchAction>
       <ProfileAction
          buildConfiguration = "Release"
          shouldUseLaunchSchemeArgsEnv = "YES"
          savedToolIdentifier = ""
          useCustomWorkingDirectory = "NO"
          debugDocumentVersioning = "YES">
          <BuildableProductRunnable runnableDebuggingMode = "0">
    #{app_ref.rstrip}
          </BuildableProductRunnable>
       </ProfileAction>
       <AnalyzeAction buildConfiguration = "Debug">
       </AnalyzeAction>
       <ArchiveAction
          buildConfiguration = "Release"
          revealArchiveInOrganizer = "YES">
       </ArchiveAction>
    </Scheme>
  XML

  File.write(scheme_path, xml)
end

project_path = File.expand_path(options[:project], Dir.pwd)
project = Xcodeproj::Project.open(project_path)
app_target = project.targets.find { |target| target.name == options[:app_target] }
abort "error: missing app target #{options[:app_target]}" unless app_target

test_target = project.targets.find { |target| target.name == options[:test_target] }
test_target ||= project.new_target(:ui_test_bundle, options[:test_target], :ios, options[:deployment_target])

ensure_dependency(test_target, app_target)

options[:sources].each do |source_path|
  abort "error: missing #{source_path}; run install-ios-shim first" unless File.exist?(app_root.join(source_path))

  ensure_source(test_target, ensure_file_reference(project, source_path))
end

info_plist = source_root_relative(project, options[:info_plist])
team = app_target.build_configurations.map { |config| config.build_settings['DEVELOPMENT_TEAM'] }.find { |value| !value.to_s.empty? }

test_target.build_configurations.each do |configuration|
  settings = configuration.build_settings
  settings['CODE_SIGN_STYLE'] = 'Automatic'
  settings['DEVELOPMENT_TEAM'] = team if team
  settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  settings['INFOPLIST_FILE'] = info_plist
  settings['IPHONEOS_DEPLOYMENT_TARGET'] = options[:deployment_target]
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = options[:test_bundle_id]
  settings['PRODUCT_MODULE_NAME'] = '$(TARGET_NAME)'
  settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  settings['SWIFT_VERSION'] = '5.0'
  settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  settings['TEST_TARGET_NAME'] = options[:app_target]
end

project.save
write_scheme(project, app_target, test_target, options[:scheme])

puts "ensured #{options[:test_target]} and #{options[:scheme]}.xcscheme"
