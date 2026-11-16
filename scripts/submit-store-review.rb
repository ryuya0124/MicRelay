# SPDX-License-Identifier: MIT
# Copyright (c) 2026 ryuya
# Explicit App Store review submission using store/release-policy.json.
require 'spaceship'
require 'dotenv'
require 'json'
require 'yaml'
require 'fileutils'
require 'digest'
ROOT = File.expand_path('..', __dir__)
Dotenv.load(File.join(ROOT,'.env'))
Spaceship::ConnectAPI.token=Spaceship::ConnectAPI::Token.create(
  key_id:ENV.fetch('APP_STORE_CONNECT_API_KEY_ID'),issuer_id:ENV.fetch('APP_STORE_CONNECT_API_ISSUER_ID'),filepath:ENV.fetch('APP_STORE_CONNECT_API_KEY_PATH'))
config=YAML.safe_load_file(File.join(ROOT,'project.yml')).dig('targets','MicRelay','settings','base')
app=Spaceship::ConnectAPI::App.find('net.ryuya-dev.MicRelay') or abort 'App missing'
version=app.get_app_store_versions(filter:{platform:'IOS'},includes:'build').find{|v|v.version_string==config.fetch('MARKETING_VERSION').to_s} or abort 'Version missing'
abort 'Selected build does not match project.yml or is not VALID' unless version.build&.version==config.fetch('CURRENT_PROJECT_VERSION').to_s && version.build.processing_state=='VALID'
release_type=JSON.parse(File.read(File.join(ROOT,'store/release-policy.json'))).fetch('release_type')
abort 'Unsupported release policy' unless ['MANUAL','AFTER_APPROVAL'].include?(release_type)
if version.release_type!=release_type
 abort 'Release policy can only be changed by this script on an editable version' unless ['PREPARE_FOR_SUBMISSION','READY_FOR_REVIEW'].include?(version.app_store_state)
 version.update(attributes:{release_type:release_type})
end
abort 'Complete export compliance before submitting' unless version.build.uses_non_exempt_encryption==false
review=version.fetch_app_store_review_detail
abort 'App Review contact and instructions are incomplete' unless review && [:contact_first_name,:contact_last_name,:contact_phone,:contact_email,:notes].all?{|f|!review.public_send(f).to_s.strip.empty?} && review.demo_account_required==false
localizations=version.get_app_store_version_localizations
%w(ja en-US).each do |locale|
 l=localizations.find{|x|x.locale==locale} or abort "Missing #{locale} metadata"
 abort "Description differs from source for #{locale}" unless l.description.strip==File.read(File.join(ROOT,'store/metadata',locale,'description.txt')).strip
 abort "Release notes differ from source for #{locale}" unless l.whats_new.to_s.strip==File.read(File.join(ROOT,'store/metadata',locale,'release_notes.txt')).strip
 {'iphone'=>'APP_IPHONE_61','ipad'=>'APP_IPAD_PRO_3GEN_129','duo'=>'APP_IPHONE_DUO'}.each do |device,type|
  set=l.get_app_screenshot_sets.find{|s|s.screenshot_display_type==type} or abort "Missing #{locale}/#{device} screenshots"
  images=set.app_screenshots || []
  checksums=Dir[File.join(ROOT,'store/screenshots',locale,device,'*.png')].sort.map{|p|Digest::MD5.file(p).hexdigest}
  abort "Screenshot delivery/order/checksum mismatch for #{locale}/#{device}" unless !checksums.empty? && images.all?(&:complete?) && images.map(&:source_file_checksum)==checksums
 end
end

submissions=app.get_review_submissions(filter:{platform:'IOS'},includes:'appStoreVersionForReview')
active=submissions.find{|s|['WAITING_FOR_REVIEW','IN_REVIEW','UNRESOLVED_ISSUES'].include?(s.state)}
if active
 abort 'A different version is already in review' unless active.app_store_version_for_review&.id==version.id
 submission=active
else
 abort 'Version is not ready for review preparation' unless ['PREPARE_FOR_SUBMISSION','READY_FOR_REVIEW'].include?(version.app_store_state) || version.app_version_state=='READY_FOR_REVIEW'
 submission=submissions.find{|s|s.state=='READY_FOR_REVIEW'} || app.create_review_submission(platform:'IOS')
 items=Spaceship::ConnectAPI::ReviewSubmissionItem.all(review_submission_id:submission.id,includes:'appStoreVersion')
 abort 'Existing submission contains other review items' unless items.all?{|i|i.app_store_version&.id==version.id}
 submission.add_app_store_version_to_review_items(app_store_version_id:version.id) if items.empty?
 15.times do
  fresh=Spaceship::ConnectAPI::AppStoreVersion.get(app_store_version_id:version.id)
  break if fresh.app_version_state=='READY_FOR_REVIEW'
  sleep(2)
 end
 submission.submit_for_review
end
fresh=Spaceship::ConnectAPI::ReviewSubmission.get(review_submission_id:submission.id,includes:'appStoreVersionForReview')
version=Spaceship::ConnectAPI::AppStoreVersion.get(app_store_version_id:version.id,includes:'build')
report={app_id:app.id,version:version.version_string,build:version.build&.version,app_store_state:version.app_store_state,
 app_version_state:version.app_version_state,release_type:version.release_type,review_id:fresh.id,review_state:fresh.state,submitted_date:fresh.submitted_date}
FileUtils.mkdir_p(File.join(ROOT,'artifacts/release'))
File.write(File.join(ROOT,'artifacts/release/appstore-review-submission.json'),JSON.pretty_generate(report))
puts JSON.pretty_generate(report)
abort 'Submission did not reach a submitted review state' unless ['WAITING_FOR_REVIEW','IN_REVIEW','COMPLETE'].include?(fresh.state)
