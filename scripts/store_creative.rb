# SPDX-License-Identifier: MIT
# Copyright (c) 2026 ryuya
# Apple API: https://developer.apple.com/documentation/appstoreconnectapi/uploading-and-managing-image-assets
KIND = ARGV.fetch(0, 'header')
LOCALE = ARGV.fetch(1, 'ja')
abort 'Invalid locale' unless LOCALE.match?(/\A[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})*\z/)
PLACEMENT_TYPE = {'header'=>'PRODUCT_PAGE_HEADER_ASSET', 'search'=>'APP_STORE_SEARCH_RESULTS_ASSET'}.fetch(KIND)
require 'spaceship'
require 'dotenv'
require 'net/http'
require 'json'
ROOT = File.expand_path('..', __dir__)
Dotenv.load(File.join(ROOT, '.env'))
$stdout.sync = true
TOKEN = Spaceship::ConnectAPI::Token.create(key_id: ENV.fetch('APP_STORE_CONNECT_API_KEY_ID'), issuer_id: ENV.fetch('APP_STORE_CONNECT_API_ISSUER_ID'), filepath: ENV.fetch('APP_STORE_CONNECT_API_KEY_PATH'))
Spaceship::ConnectAPI.token = TOKEN

def request(method, path, body = nil)
  uri = URI('https://api.appstoreconnect.apple.com/v1/' + path)
  req = Net::HTTP.const_get(method.capitalize).new(uri)
  req['Authorization'] = 'Bearer ' + TOKEN.text
  if body
    req['Content-Type'] = 'application/json'
    req.body = JSON.generate(body)
  end
  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
  result = response.body.to_s.empty? ? {} : JSON.parse(response.body)
  abort "Apple API #{response.code}: #{result['errors']}" unless response.code.to_i.between?(200, 299)
  result
end

app = Spaceship::ConnectAPI::App.find('net.ryuya-dev.MicRelay')
version = app.get_app_store_versions.find { |v| v.version_string == '1.0.0' && v.app_store_state == 'PREPARE_FOR_SUBMISSION' } or abort 'Editable draft missing'
localization = version.get_app_store_version_localizations.find { |l| l.locale == LOCALE } or abort 'Localization missing; register metadata first'
library = request('get', "apps/#{app.id}/assetLibrary")['data']['id']
reference = request('get', 'appAssetLibraryRefData')['data'][0]['attributes']
policy = reference['features'].find { |f| f['featureId'] == 'APP_STORE_VERSIONS' }['placementPolicies'].find { |p| p['placementType'] == PLACEMENT_TYPE }
group = policy['groupLimits'].find { |g| g['groupIds'].include?('DEFAULT_PROFILE') } or abort 'Header placement unsupported'
abort 'Header placement limit changed' unless group['maxCount'] == 1
path = File.join(ROOT, "store/header/MicRelay-#{KIND}.png")
name = "MicRelay #{KIND} v3"
images = request('get', "appAssetLibraries/#{library}/images?filter[category]=CREATIVE_ASSETS")['data']
image = images.find { |i| i['attributes']['referenceName'] == name }
unless image
  image = request('post', 'appAssetLibraryImages', data: {type: 'appAssetLibraryImages', attributes: {fileName: File.basename(path), fileSize: File.size(path), category: 'CREATIVE_ASSETS', referenceName: name}, relationships: {assetLibrary: {data: {type: 'appAssetLibraries', id: library}}}})['data']
  Spaceship::ConnectAPI::FileUploader.upload(image['attributes']['uploadOperations'], File.binread(path))
  image = request('patch', "appAssetLibraryImages/#{image['id']}", data: {type: 'appAssetLibraryImages', id: image['id'], attributes: {uploaded: true}})['data']
end
30.times do
  state = image['attributes']['state']
  break if state == 'PREPARE_FOR_SUBMISSION'
  abort "Header failed: #{image['attributes']['stateDetails']}" if state == 'FAILED'
  sleep 2
  image = request('get', "appAssetLibraryImages/#{image['id']}")['data']
end
abort 'Header is still processing; rerun to finish placement' unless image['attributes']['state'] == 'PREPARE_FOR_SUBMISSION'
spec = reference['imageSpecs'].find { |s| s['specId'] == image['attributes']['specId'] }
abort 'Unexpected header specification' unless spec && spec['compatiblePlacementTypes'].include?(PLACEMENT_TYPE)
placements = request('get', "appStoreVersionLocalizations/#{localization.id}/placements?filter[placementType]=#{PLACEMENT_TYPE}")['data']
placement = placements.find { |p| p.dig('relationships','image','data','id') == image['id'] }
if !placement && !placements.empty?
  # Replace our previous draft-only artwork; the reusable image remains in Asset Library.
  placements.each { |p| request('delete', "appAssetLibraryPlacements/#{p['id']}") }
end
placement ||= request('post', 'appAssetLibraryPlacements', data: {type:'appAssetLibraryPlacements', attributes: {placementType:PLACEMENT_TYPE, placementGroup:'DEFAULT_PROFILE'}, relationships: {image: {data: {type:'appAssetLibraryImages', id:image['id']}}, appStoreVersionLocalization: {data:{type:'appStoreVersionLocalizations', id:localization.id}}}})['data']
puts JSON.pretty_generate({locale:LOCALE, kind:KIND, image_id:image['id'], image_state:image['attributes']['state'], placement_id:placement['id'], placement_state:placement['attributes']['state']})
