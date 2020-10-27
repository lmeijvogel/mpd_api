require 'fileutils'
require 'sidekiq'

$LOAD_PATH << __dir__

require "backend"

class CoverLoader
  include Sidekiq::Worker

  ERRORS_FILE = "/tmp/sidekiq_errors"

  COVERS_PATH = File.join(__dir__, "../public/covers")

  def perform
    FileUtils.mkdir_p(COVERS_PATH)

    Backend.new.albums.each do |album|
      return if cancelled?

      artist = album.fetch(:album_artist)
      album_name = album.fetch(:album)

      proposed_filename = "#{artist}-#{album_name}.jpg"

      cover_path = File.join(COVERS_PATH, sanitize_filename(proposed_filename))

      if File.exist?(cover_path)
        MpdLogger.info("Skipping #{artist} - #{album_name}")
        next
      end

      MpdLogger.info("Retrieving for #{artist} - #{album_name}")

      begin
        Backend.new.get_albumart({
          "album" => album_name,
          "album_artist" => artist,
        }, cover_path)
      rescue MpdNoAlbumArt => e
        MpdLogger.info("No album art exists for #{artist} - #{album_name}")
      end
    end
  end

  def cancelled?
    Sidekiq.redis {|c| c.exists?("cancelled-#{jid}") } # Use c.exists? on Redis >= 4.2.0
  end

  def self.cancel!(jid)
    Sidekiq.redis {|c| c.setex("cancelled-#{jid}", 86400, 1) }
  end

  def sanitize_filename(input)
    # NOTE: File.basename doesn't work right with Windows paths on Unix
    # get only the filename, not the whole path
    input
      .gsub(/^.*(\\|\/)/, '')
      .gsub(/[^0-9A-Za-z.\-]/, '_')# Strip out the non-ascii character
  end
end
