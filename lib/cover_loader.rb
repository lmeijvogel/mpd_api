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

      cover_path = File.join(COVERS_PATH, album.cover_filename)

      artist = album.artist
      title = album.title

      if File.exist?(cover_path) && File.size(cover_path) > 0
        MpdLogger.info("Skipping #{artist} - #{title}")
        next
      end

      MpdLogger.info("Retrieving for #{artist} - #{title}")

      begin
        Backend.new.retrieve_albumart(album, cover_path)
      rescue MpdNoAlbumArt => e
        MpdLogger.info("No album art exists for #{artist} - #{title}")
      end
    end
  end

  def cancelled?
    Sidekiq.redis {|c| c.exists?("cancelled-#{jid}") } # Use c.exists? on Redis >= 4.2.0
  end

  def self.cancel!(jid)
    Sidekiq.redis {|c| c.setex("cancelled-#{jid}", 86400, 1) }
  end
end
