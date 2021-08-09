$stdout.sync = true
require 'fileutils'
require 'json'

require 'sinatra'

$LOAD_PATH << __dir__
$LOAD_PATH << File.join(__dir__, "lib")

require "backend"

require "cover_loader"

require "sinatra/reloader" if development?

also_reload("**/*.rb")

COVERS_PATH = "covers"

FileUtils.mkdir_p(COVERS_PATH)

set :show_exceptions, false

error do |e|
  status 400

  e.inspect
end

get '/players' do
  Backend.players.to_json
end

get '/:player/albums' do
  Backend.new(player.fetch(:ip)).albums.map do |album|
    {
      album: album.title,
      album_artist: album.artist,
      cover_path: File.join(COVERS_PATH, album.cover_filename)
    }
  end.to_json
end

get '/:player/status' do
  Backend.new(player.fetch(:ip)).status.to_json
end

get "/:player/album_cover" do
  cover_filename = Backend.new(player.fetch(:ip)).album_cover

  {
    cover_path: File.join(COVERS_PATH, cover_filename[:path])
  }.to_json
end

get '/:player/takeover_status' do
  return Backend.new(player.fetch(:ip)).takeover_status.to_json
end

post '/:player/command' do
  command = JSON.parse(request.body.read).fetch("command")

  unless %w[previous play pause next stop].include?(command)
    status 400
    return
  end

  Backend.new(player.fetch(:ip)).command(command)
end

post '/:player/update_playback_setting' do
  input = JSON.parse(request.body.read)

  key, value = input.values_at("key", "value")

  is_request_correct = %w[repeat random single consume].include?(key) && %w[0 1].include?(value)

  if !is_request_correct
    status 400

    return
  end

  Backend.new(player.fetch(:ip)).command("#{key} #{value}")
end

post '/update_album_covers' do
  CoverLoader.perform_async
end

post '/update_albums' do
  Backend.new(ip).update_albums
end

get '/:player/playlist' do
  Backend.new(player.fetch(:ip)).playlist.to_json
end

post '/:player/clear_and_play' do
  payload = JSON.parse(request.body.read)

  Backend.new(player.fetch(:ip)).clear_add(title: payload.fetch("album"), artist: payload.fetch("album_artist"))
end

post '/:player/play_id' do
  id = Integer(JSON.parse(request.body.read).fetch("id"))
  Backend.new(player.fetch(:ip)).play_id(id)
end

post '/:player/volume' do
  volume = Integer(JSON.parse(request.body.read).fetch("volume"))
  Backend.new(player.fetch(:ip)).set_volume(volume)
end

post '/:player/enable_output' do
  id = Integer(JSON.parse(request.body.read).fetch("id"))

  Backend.new(player.fetch(:ip)).enable_output(id)

  status 204
end

def player
  Backend.players.find {|p| p[:name].downcase == params.fetch(:player).downcase }
end
