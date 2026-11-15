# SPDX-License-Identifier: MIT
# Copyright (c) 2026 ryuya
# Replace one locale/device screenshot set after every new image is COMPLETE.
# Existing source images must be recoverable from HEAD; rollback copies stay in artifacts/.
require 'spaceship'
require 'dotenv'
require 'json'
require 'digest'
require 'fileutils'
require 'open3'
require 'yaml'

ROOT = File.expand_path('..', __dir__)
locale, device = ARGV
mapping = {'iphone'=>'APP_IPHONE_61','ipad'=>'APP_IPAD_PRO_3GEN_129','duo'=>'APP_IPHONE_DUO'}
abort 'Usage: sync-store-screenshots.rb <locale> <iphone|ipad|duo>' unless ARGV.size == 2 && locale.match?(/\A[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})*\z/) && mapping.key?(device)
directory = "store/screenshots/#{locale}/#{device}"
files = Dir[File.join(ROOT,directory,'*.png')].sort
abort 'Expected 1 to 10 local screenshots' unless (1..10).cover?(files.size)
checksums = files.map { |path| Digest::MD5.file(path).hexdigest }
abort 'Duplicate local screenshot content' unless checksums.uniq.size == checksums.size
Dotenv.load(File.join(ROOT,'.env'))
Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.create(
  key_id:ENV.fetch('APP_STORE_CONNECT_API_KEY_ID'),issuer_id:ENV.fetch('APP_STORE_CONNECT_API_ISSUER_ID'),filepath:ENV.fetch('APP_STORE_CONNECT_API_KEY_PATH'))
app = Spaceship::ConnectAPI::App.find('net.ryuya-dev.MicRelay') or abort 'App missing'
marketing_version = YAML.safe_load_file(File.join(ROOT,'project.yml')).dig('targets','MicRelay','settings','base','MARKETING_VERSION').to_s
version = app.get_app_store_versions(filter:{platform:'IOS'}).find { |v| v.version_string == marketing_version } or abort 'Version missing'
abort 'Store version is not an editable draft' unless version.app_store_state == 'PREPARE_FOR_SUBMISSION'
localization = version.get_app_store_version_localizations.find { |l| l.locale == locale } or abort 'Locale missing'
set = localization.get_app_screenshot_sets.find { |s| s.screenshot_display_type == mapping.fetch(device) } or abort 'Screenshot set missing'
existing = set.app_screenshots || []
extra = existing.reject { |image| checksums.include?(image.source_file_checksum) }
abort 'Not enough free screenshot slots to stage replacements' if existing.size + checksums.count { |md5| existing.none? { |i| i.source_file_checksum == md5 && i.complete? } } > 10

# Capture recoverable copies before changing the remote set. No existing image is removed on upload failure.
rollback = File.join(ROOT,'artifacts',"screenshot-rollback-#{Time.now.utc.strftime('%Y%m%dT%H%M%S')}-#{locale}-#{device}")
FileUtils.mkdir_p(rollback)
tracked, status = Open3.capture2('git','ls-tree','-r','--name-only','-z','HEAD','--',directory,chdir:ROOT)
abort 'Cannot inspect tracked screenshots' unless status.success?
old_sources = tracked.split("\0").filter_map do |path|
  bytes, result = Open3.capture2('git','show',"HEAD:#{path}",chdir:ROOT,binmode:true)
  [Digest::MD5.hexdigest(bytes),bytes] if result.success?
end.to_h
extra.each do |image|
  bytes = old_sources[image.source_file_checksum] or abort "No rollback source for #{image.id}; leave remote images untouched"
  File.binwrite(File.join(rollback,"#{image.id}.png"),bytes)
end
File.write(File.join(rollback,'before.json'),JSON.pretty_generate({locale:locale,device:device,set_id:set.id,
 images:existing.map { |i| {id:i.id,name:i.file_name,md5:i.source_file_checksum,asset:i.image_asset,state:i.asset_delivery_state} }}))

new_images = files.zip(checksums).map do |path, checksum|
  image = existing.find { |i| i.source_file_checksum == checksum && i.complete? }
  image ||= set.upload_screenshot(path:path)
  fresh = Spaceship::ConnectAPI.get_app_screenshot(app_screenshot_id:image.id).first
  abort "Screenshot not complete: #{File.basename(path)}" unless fresh.complete? && fresh.source_file_checksum == checksum
  puts "#{locale}/#{device}: #{File.basename(path)} COMPLETE"
  fresh
end
extra.each(&:delete!)
set.reorder_screenshots(app_screenshot_ids:new_images.map(&:id))
verified = Spaceship::ConnectAPI::AppScreenshotSet.get(app_screenshot_set_id:set.id)
images = verified.app_screenshots || []
abort 'Final screenshot count, order, checksum, or delivery mismatch' unless images.map(&:id) == new_images.map(&:id) && images.map(&:source_file_checksum) == checksums && images.all?(&:complete?)
report = {locale:locale,device:device,version:marketing_version,images:images.map { |i| {id:i.id,name:i.file_name,md5:i.source_file_checksum,state:i.asset_delivery_state,asset:i.image_asset,url:i.image_asset_url} }}
File.write(File.join(ROOT,'artifacts',"screenshots-#{locale}-#{device}-verified.json"),JSON.pretty_generate(report))
puts "Replaced #{locale}/#{device}: #{images.size} verified screenshots; rollback sources saved."
