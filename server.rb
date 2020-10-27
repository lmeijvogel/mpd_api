require 'bundler'

Bundler.load

require 'fileutils'
require 'json'

require 'sinatra'

$LOAD_PATH << __dir__
$LOAD_PATH << File.join(__dir__, "lib")

require "backend"

require "cover_loader"

require "sinatra/reloader" if development?

also_reload './backend.rb'

COVERS_PATH = "covers"

FileUtils.mkdir_p(COVERS_PATH)

get '/api/albums' do
  Backend.new.albums.map do |album|
    {
      album: album.title,
      album_artist: album.artist,
      cover_path: File.join(COVERS_PATH, album.cover_filename)
    }
  end.to_json
end

get '/api/status' do
  Backend.new.status.to_json
end

post '/api/command' do
  command = JSON.parse(request.body.read).fetch("command")
  puts command.inspect
  unless %w[previous play pause next stop].include?(command)
    status 400
    return
  end

  Backend.new.command(command)
end

post '/api/retrieve_album_covers' do
  CoverLoader.perform_async
end

get '/api/playlist' do
  Backend.new.playlist.to_json
end

post '/api/clear_and_play' do
  payload = JSON.parse(request.body.read)
  Backend.new.clear_add(title: payload.fetch("album"), artist: payload.fetch("album_artist"))
end

post '/api/play_id' do
  id = Integer(JSON.parse(request.body.read).fetch("id"))
  Backend.new.play_id(id)
end

post '/api/volume' do
  volume = Integer(JSON.parse(request.body.read).fetch("volume"))
  Backend.new.set_volume(volume)
end
