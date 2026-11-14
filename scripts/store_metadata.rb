# SPDX-License-Identifier: MIT
# Copyright (c) 2026 ryuya
ACTION = ARGV.fetch(0, 'metadata')
$stdout.sync = true
require 'spaceship'
require 'dotenv'
require 'json'
require 'digest'
ROOT = File.expand_path('..', __dir__)
Dotenv.load(File.join(ROOT, '.env'))
Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.create(
  key_id: ENV.fetch('APP_STORE_CONNECT_API_KEY_ID'), issuer_id: ENV.fetch('APP_STORE_CONNECT_API_ISSUER_ID'),
  filepath: ENV.fetch('APP_STORE_CONNECT_API_KEY_PATH'))
app = Spaceship::ConnectAPI::App.find('net.ryuya-dev.MicRelay') or abort 'App missing'
version = app.get_app_store_versions(filter: {platform: 'IOS'}).find { |v| v.version_string == '1.0.0' } or abort 'Version missing'
abort 'Version is not an editable draft' unless version.app_store_state == 'PREPARE_FOR_SUBMISSION'
localization = version.get_app_store_version_localizations.find { |v| v.locale == 'ja' }
localization ||= version.create_app_store_version_localization(attributes: {locale: 'ja'})
puts "Store operation: #{ACTION}, root: #{ROOT}"
case ACTION
when 'metadata'
  read = ->(name) { File.read(File.join(ROOT, 'store/metadata/ja', name + '.txt')).strip }
  localization.update(attributes: {
    description: read.call('description'), keywords: read.call('keywords'),
    support_url: 'https://github.com/ryuya0124/MicRelay/blob/main/docs/SUPPORT.md',
    marketing_url: 'https://github.com/ryuya0124/MicRelay'
  })
  info = app.fetch_edit_app_info
  info.update_categories(category_id_map: {primary_category_id: 'UTILITIES', secondary_category_id: 'MUSIC'})
  info_local = info.get_app_info_localizations.find { |v| v.locale == 'ja' }
  info_local.update(attributes: {name: 'MicRelay', subtitle: read.call('subtitle'),
    privacy_policy_url: 'https://github.com/ryuya0124/MicRelay/blob/main/docs/PRIVACY.md'})
  rating = info.fetch_age_rating_declaration
  attrs = {}
  %w(alcohol_tobacco_or_drug_use_or_references contests gambling_simulated guns_or_other_weapons horror_or_fear_themes mature_or_suggestive_themes medical_or_treatment_information profanity_or_crude_humor sexual_content_graphic_and_nudity sexual_content_or_nudity violence_cartoon_or_fantasy violence_realistic_prolonged_graphic_or_sadistic violence_realistic).each { |k| attrs[k.to_sym] = 'NONE' }
  %w(advertising age_assurance gambling health_or_wellness_topics loot_box messaging_and_chat parental_controls social_media social_media_age_restricted unrestricted_web_access user_generated_content).each { |k| attrs[k.to_sym] = false }
  attrs[:age_rating_override_v2] = 'NONE'
  rating.update(attributes: attrs)
  version.update(attributes: {copyright: '2026 ryuya', release_type: 'MANUAL'})
  puts 'Japanese metadata, categories and age declarations saved to draft.'
when 'screenshots'
  mapping = {'iphone'=>'APP_IPHONE_61', 'ipad'=>'APP_IPAD_PRO_3GEN_129', 'duo'=>'APP_IPHONE_DUO'}
  mapping.each do |folder, type|
    files = Dir[File.join(ROOT, 'store/screenshots/ja', folder, '*.png')].sort
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
  build = Spaceship::ConnectAPI::Build.all(app_id: app.id).find { |b| b.processing_state == 'VALID' && b.version == '2' && b.app_version == '1.0.0' } or abort 'Valid build 2 missing'
  version.select_build(build_id: build.id)
  puts "Selected build #{build.id} for draft. No review submission."
when 'verify'
  puts JSON.pretty_generate({app: app.id, version: version.version_string, state: version.app_store_state,
    localization: {locale:localization.locale, description:localization.description, keywords:localization.keywords, support_url:localization.support_url},
    screenshot_sets: localization.get_app_screenshot_sets.map { |s| {type:s.screenshot_display_type, screenshots:(s.app_screenshots || []).map { |a| {name:a.file_name, state:a.asset_delivery_state} }} },
    reviews: app.get_review_submissions.map { |r| {id:r.id, state:r.state} }})
else
  abort 'Use metadata, screenshots, attach, or verify'
end
