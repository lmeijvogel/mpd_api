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

COVERS_PATH = "public/covers"

FileUtils.mkdir_p(COVERS_PATH)

get '/api/albums' do
  Backend.new.albums.map do |album|
    proposed_filename = "#{album[:album_artist]}-#{album[:album]}.jpg"
    cover_path = File.join("/covers", sanitize_filename(proposed_filename))

    album.merge({
      cover_path: cover_path
    })
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
  Backend.new.clear_add(payload)
end

post '/api/play_id' do
  id = Integer(JSON.parse(request.body.read).fetch("id"))
  Backend.new.play_id(id)
end

post '/api/volume' do
  volume = Integer(JSON.parse(request.body.read).fetch("volume"))
  Backend.new.set_volume(volume)
end

def sanitize_filename(input)
   # NOTE: File.basename doesn't work right with Windows paths on Unix
   # get only the filename, not the whole path
  input
    .gsub(/^.*(\\|\/)/, '')
    .gsub(/[^0-9A-Za-z.\-]/, '_')# Strip out the non-ascii character
end
