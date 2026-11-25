#!/usr/bin/env ruby
# Adds the QuranJourneyWidget WidgetKit extension to ios/Runner.xcodeproj and
# wires App Group entitlements for Runner and the extension.
#
# Idempotent: running it again changes nothing if everything is already set.
# Requires: gem install xcodeproj
# Usage (from quran-journey/):  ruby tools/ios/add_widget_target.rb
require 'xcodeproj'

ROOT = File.expand_path('../../app/ios', __dir__)
PROJECT_PATH = File.join(ROOT, 'Runner.xcodeproj')
EXT_NAME = 'QuranJourneyWidget'
EXT_BUNDLE_ID = 'app.quranjourney.quranJourney.QuranJourneyWidget'
EXT_DEPLOYMENT = '17.0'
APP_DEPLOYMENT = '15.0'

project = Xcodeproj::Project.open(PROJECT_PATH)
runner = project.targets.find { |t| t.name == 'Runner' } or abort('Runner target not found')

# ---------- Runner: entitlements + deployment target ----------
runner_group = project.main_group.children.find { |g| g.respond_to?(:path) && g.path == 'Runner' && g.isa == 'PBXGroup' }
abort('Runner group not found') unless runner_group
unless runner_group.files.any? { |f| f.path == 'Runner.entitlements' }
  runner_group.new_reference('Runner.entitlements')
end
runner.build_configurations.each do |c|
  c.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
  c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = APP_DEPLOYMENT
end
project.build_configurations.each do |c|
  c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = APP_DEPLOYMENT
end

# ---------- Extension target ----------
ext = project.targets.find { |t| t.name == EXT_NAME }
unless ext
  ext = project.new_target(:app_extension, EXT_NAME, :ios, EXT_DEPLOYMENT, project.products_group, :swift)
end

group = project.main_group.children.find { |g| g.isa == 'PBXGroup' && g.path == EXT_NAME } ||
        project.main_group.new_group(EXT_NAME, EXT_NAME)

def ensure_ref(group, name)
  group.files.find { |f| f.path == name } || group.new_reference(name)
end

swift_files = %w[QuranJourneyWidget.swift WidgetData.swift].map { |n| ensure_ref(group, n) }
font = ensure_ref(group, 'AmiriQuran-Regular.ttf')
ensure_ref(group, 'Info.plist')
ensure_ref(group, "#{EXT_NAME}.entitlements")
xcconfig = ensure_ref(group, "#{EXT_NAME}.xcconfig")

swift_files.each do |f|
  ext.source_build_phase.add_file_reference(f, true) unless ext.source_build_phase.files_references.include?(f)
end
ext.resources_build_phase.add_file_reference(font, true) unless ext.resources_build_phase.files_references.include?(font)

%w[WidgetKit SwiftUI].each do |fw|
  next if ext.frameworks_build_phase.files_references.any? { |r| r.path&.end_with?("#{fw}.framework") }
  ext.add_system_framework(fw)
end

ext.build_configurations.each do |c|
  s = c.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = EXT_BUNDLE_ID
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['INFOPLIST_FILE'] = "#{EXT_NAME}/Info.plist"
  s['CODE_SIGN_ENTITLEMENTS'] = "#{EXT_NAME}/#{EXT_NAME}.entitlements"
  s['CODE_SIGN_STYLE'] = 'Automatic'
  s['SWIFT_VERSION'] = '5.0'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = EXT_DEPLOYMENT
  s['TARGETED_DEVICE_FAMILY'] = '1,2'
  s['SKIP_INSTALL'] = 'YES'
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
  s['ASSETCATALOG_COMPILER_WIDGET_BACKGROUND_COLOR_NAME'] = ''
  s['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  # Version comes from QuranJourneyWidget.xcconfig (mirrors the app's Flutter
  # build name/number; the extension must match or App Store validation fails).
  s.delete('MARKETING_VERSION')
  s.delete('CURRENT_PROJECT_VERSION')
  s['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
  s['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
  s['SWIFT_OPTIMIZATION_LEVEL'] = c.name == 'Debug' ? '-Onone' : '-O'
  s['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG' if c.name == 'Debug'
end
# Profile configuration exists in Flutter projects; xcodeproj only creates Debug/Release.
unless ext.build_configurations.any? { |c| c.name == 'Profile' }
  release = ext.build_configurations.find { |c| c.name == 'Release' }
  profile = project.new(Xcodeproj::Project::Object::XCBuildConfiguration)
  profile.name = 'Profile'
  profile.build_settings = release.build_settings.dup
  ext.build_configuration_list.build_configurations << profile
end

ext.build_configurations.each { |c| c.base_configuration_reference = xcconfig }

# ---------- Embed extension in Runner ----------
embed = runner.copy_files_build_phases.find { |p| p.name == 'Embed Foundation Extensions' }
unless embed
  embed = project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
  embed.name = 'Embed Foundation Extensions'
  embed.symbol_dst_subfolder_spec = :plug_ins # dstSubfolderSpec = 13
  embed.dst_path = ''
  runner.build_phases << embed
end
unless embed.files_references.include?(ext.product_reference)
  bf = embed.add_file_reference(ext.product_reference, true)
  bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
end
# Must run before Flutter's "Thin Binary" script, otherwise Xcode reports a build cycle.
thin = runner.build_phases.find { |p| p.respond_to?(:name) && p.name == 'Thin Binary' }
if thin
  runner.build_phases.delete(embed)
  runner.build_phases.insert(runner.build_phases.index(thin), embed)
end

runner.add_dependency(ext) unless runner.dependencies.any? { |d| d.target == ext }

# Target attributes (automatic signing; team left empty for the user to choose).
attrs = project.root_object.attributes['TargetAttributes'] ||= {}
attrs[ext.uuid] ||= {}
attrs[ext.uuid]['CreatedOnToolsVersion'] = '15.0'

project.save
puts "OK: #{EXT_NAME} target configured in #{PROJECT_PATH}"
