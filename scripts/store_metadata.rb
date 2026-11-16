# SPDX-License-Identifier: MIT
# Copyright (c) 2026 ryuya
ACTION = ARGV.fetch(0, 'metadata')
LOCALE = ARGV.fetch(1, 'ja')
abort 'Invalid locale' unless LOCALE.match?(/\A[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})*\z/)
$stdout.sync = true
require 'spaceship'
require 'dotenv'
require 'json'
require 'digest'
require 'yaml'
ROOT = File.expand_path('..', __dir__)
PROJECT_CONFIG = YAML.safe_load_file(File.join(ROOT, 'project.yml')).dig('targets', 'MicRelay', 'settings', 'base')
PROJECT_BUILD_NUMBER = PROJECT_CONFIG.fetch('CURRENT_PROJECT_VERSION').to_s
PROJECT_VERSION = PROJECT_CONFIG.fetch('MARKETING_VERSION').to_s
abort 'Invalid project build number' unless PROJECT_BUILD_NUMBER.match?(/\A[0-9]+\z/)
abort 'Invalid marketing version' unless PROJECT_VERSION.match?(/\A\d+\.\d+\.\d+\z/)
if ACTION == 'metadata'
  {'description'=>4000, 'subtitle'=>30, 'keywords'=>100, 'release_notes'=>4000}.each do |name, limit|
    value = File.read(File.join(ROOT, 'store/metadata', LOCALE, name + '.txt')).strip
    abort "#{name} is empty or exceeds #{limit} characters" if value.empty? || value.length > limit
  end
end
Dotenv.load(File.join(ROOT, '.env'))
Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.create(
  key_id: ENV.fetch('APP_STORE_CONNECT_API_KEY_ID'), issuer_id: ENV.fetch('APP_STORE_CONNECT_API_ISSUER_ID'),
  filepath: ENV.fetch('APP_STORE_CONNECT_API_KEY_PATH'))
app = Spaceship::ConnectAPI::App.find('net.ryuya-dev.MicRelay') or abort 'App missing'
versions = app.get_app_store_versions(filter: {platform: 'IOS'})
version = versions.find { |v| v.version_string == PROJECT_VERSION }
if ACTION == 'create'
  unless version
    abort 'Another unreleased version already exists' if versions.any? { |v| !['READY_FOR_SALE', 'REPLACED_WITH_NEW_VERSION', 'REMOVED_FROM_SALE', 'DEVELOPER_REMOVED_FROM_SALE'].include?(v.app_store_state) }
    Spaceship::ConnectAPI.post_app_store_version(app_id: app.id, attributes: {versionString: PROJECT_VERSION, platform: 'IOS'})
    version = app.get_app_store_versions(filter: {platform: 'IOS'}).find { |v| v.version_string == PROJECT_VERSION }
  end
  abort 'Could not create the requested version' unless version
  puts JSON.pretty_generate({version: version.version_string, state: version.app_store_state, id: version.id})
  exit
end
abort 'Version missing; run create first' unless version
abort 'Version is not an editable draft' unless version.app_store_state == 'PREPARE_FOR_SUBMISSION'
if ACTION == 'review_notes'
  contact = JSON.parse(File.read(ENV.fetch('BETA_REVIEW_CONTACT_JSON', File.join(ROOT, 'artifacts/release/review-contact.json'))), symbolize_names: true)
  attributes = [:contact_first_name, :contact_last_name, :contact_phone, :contact_email].to_h { |key| [key, contact.fetch(key)] }
  abort 'Review contact incomplete' if attributes.values.any? { |value| value.to_s.strip.empty? }
  attributes[:demo_account_required] = false
  attributes[:notes] = File.read(File.join(ROOT, 'store/review-notes.en.txt')).strip
  review = version.fetch_app_store_review_detail
  review ? review.update(attributes: attributes) : version.create_app_store_review_detail(attributes: attributes)
  puts "Review contact and instructions saved for #{version.version_string}."
  exit
end
localization = version.get_app_store_version_localizations.find { |v| v.locale == LOCALE }
localization ||= version.create_app_store_version_localization(attributes: {locale: LOCALE}) if ACTION == 'metadata'
abort "Localization #{LOCALE} is missing; run metadata first" unless localization
docs_path = LOCALE.start_with?('en') ? 'docs/en' : 'docs'
puts "Store operation: #{ACTION}, locale: #{LOCALE}, root: #{ROOT}"
case ACTION
when 'metadata'
  read = ->(name) { File.read(File.join(ROOT, 'store/metadata', LOCALE, name + '.txt')).strip }
  localization.update(attributes: {
    description: read.call('description'), keywords: read.call('keywords'), whats_new: read.call('release_notes'),
    support_url: "https://github.com/ryuya0124/MicRelay/blob/main/#{docs_path}/SUPPORT.md",
    marketing_url: 'https://github.com/ryuya0124/MicRelay'
  })
  info = app.fetch_edit_app_info
  info_local = info.get_app_info_localizations.find { |v| v.locale == LOCALE }
  info_local ||= info.create_app_info_localization(attributes: {locale: LOCALE, name: 'MicRelay'})
  info_attributes = {name: 'MicRelay', subtitle: read.call('subtitle'),
    privacy_policy_url: "https://github.com/ryuya0124/MicRelay/blob/main/#{docs_path}/PRIVACY.md"}
  changed = info_attributes.reject { |key, value| info_local.public_send(key) == value }
  info_local.update(attributes: changed) unless changed.empty?
  if LOCALE == 'ja'
    release_type = JSON.parse(File.read(File.join(ROOT, 'store/release-policy.json'))).fetch('release_type')
    abort 'Unsupported release policy' unless ['MANUAL', 'AFTER_APPROVAL'].include?(release_type)
    version.update(attributes: {copyright: '2026 ryuya', release_type: release_type})
  end
  puts "#{LOCALE} metadata saved to draft."
when 'screenshots'
  mapping = {'iphone'=>'APP_IPHONE_61', 'ipad'=>'APP_IPAD_PRO_3GEN_129', 'duo'=>'APP_IPHONE_DUO'}
  mapping.each do |folder, type|
    files = Dir[File.join(ROOT, 'store/screenshots', LOCALE, folder, '*.png')].sort
    puts "#{folder}: #{files.count} local screenshots"
    next if files.empty?
    set = localization.get_app_screenshot_sets.find { |s| s.screenshot_display_type == type }
    set ||= localization.create_app_screenshot_set(attributes: {screenshotDisplayType: type})
    files.each do |path|
      checksum = Digest::MD5.file(path).hexdigest
      existing = set.app_screenshots || []
      next if existing.any? { |s| s.source_file_checksum == checksum && s.complete? }
      screenshot = set.upload_screenshot(path: path)
      puts "#{folder}: #{File.basename(path)} #{screenshot.asset_delivery_state}"
    end
  end
when 'attach'
  build = Spaceship::ConnectAPI::Build.all(app_id: app.id).find { |b| b.processing_state == 'VALID' && b.version == PROJECT_BUILD_NUMBER && b.app_version == PROJECT_VERSION } or abort "Valid build #{PROJECT_BUILD_NUMBER} missing"
  version.select_build(build_id: build.id)
  puts "Selected build #{build.id} for draft. No review submission."
when 'verify'
  puts JSON.pretty_generate({app: app.id, version: version.version_string, state: version.app_store_state,
    localization: {locale:localization.locale, description:localization.description, whats_new:localization.whats_new, keywords:localization.keywords, support_url:localization.support_url},
    app_information: app.fetch_edit_app_info.get_app_info_localizations.select { |v| v.locale == LOCALE }.map { |v| {locale:v.locale, name:v.name, subtitle:v.subtitle, privacy_policy_url:v.privacy_policy_url} },
    screenshot_sets: localization.get_app_screenshot_sets.map { |s| {type:s.screenshot_display_type, screenshots:(s.app_screenshots || []).map { |a| {name:a.file_name, state:a.asset_delivery_state} }} },
    reviews: app.get_review_submissions.map { |r| {id:r.id, state:r.state} }})
else
  abort 'Use create, metadata, screenshots, attach, review_notes, or verify, followed by an optional locale such as en-US'
end
