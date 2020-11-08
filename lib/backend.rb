require 'mpd_logger'
require 'mpd_backend'

HOSTNAME = "192.168.2.3"
# HOSTNAME = "192.168.2.4"
PORT = 6600

class Output
  attr_reader :id, :name

  def initialize(id, name, enabled)
    @id = id
    @name = name
    @enabled = enabled
  end

  def enabled?
    @enabled
  end
end

class Album
  attr_reader :artist, :title

  def initialize(title, artist)
    @title = title
    @artist = artist
  end

  def cover_filename
    proposed_filename = "#{artist}-#{title}.jpg"
    sanitize_filename(proposed_filename)
  end

  private
  def sanitize_filename(input)
    # NOTE: File.basename doesn't work right with Windows paths on Unix
    # get only the filename, not the whole path
    input
      .gsub(/^.*(\\|\/)/, '')
      .gsub(/[^0-9A-Za-z.\-]/, '_')# Strip out the non-ascii character
  end
end

class Backend
  def playlist
    response = MpdBackend.query("playlistinfo")

    return [] if response.lines.count <= 1

    entries = response.slice_before(/^file: /)

    entries.map do |entry|
      to_song(entry)
    end
  end

  def status
    response = MpdBackend.query("status")

    result = {
      repeat: response.read_value("repeat"),
      random: response.read_value("random"),
      single: response.read_value("single"),
      consume: response.read_value("consume"),
      state: response.read_value("state"),
      volume: response.read_value("volume", default: '-'),
      outputs: self.outputs
    }

    if result[:state] == "stop"
      result
    else
      result.merge({
        songid: response.read_value("songid"),
        elapsed: response.read_value("elapsed"),
        duration: response.read_value("duration")
      })
    end
  end

  def command(command)
    MpdBackend.command(command)
  end

  def set_volume(volume)
    MpdBackend.command("setvol %d", [Integer(volume)])
  end

  def play_id(id)
    MpdBackend.command("playid %d", [Integer(id)])
  end

  def retrieve_albumart(album, output_file)
    begin
      File.open(output_file, "wb") do |file|
        MpdBackend.fetch_and_save_albumart(album, file)
      end
    rescue MpdNoAlbumArt
      FileUtils.rm_f output_file
      raise
    end
  end

  def albums
    albums_and_artists = MpdBackend.query("list album group albumartistsort")

    artist_header = %r[\AAlbumArtistSort: ]
    album_header = %r[\AAlbum: ]

    albums_and_artists.slice_before(artist_header).each_with_object([]) do |group, result|
      artist = group.lines[0].gsub(artist_header, "")

      titles = group.lines[1..-1].map { |title| title.gsub(album_header, "") }

      titles.each do |title|
        result << Album.new(
          title.force_encoding("UTF-8"),
          artist.force_encoding("UTF-8")
        )
      end
    end.sort_by {|album| album.artist.downcase }
  end

  def update_albums
    MpdBackend.command("update")
  end

  def clear_add(title:, artist:)
    MpdBackend.command_list do |backend|
      backend.command("clear", [])
      backend.command(%[findadd "((Album == %s) AND (AlbumArtist == %s))"], [title, artist])
      backend.command("play", [])
    end
  end

  def enable_output(id)
    current_outputs = outputs # Do this outside of the command list

    MpdBackend.command_list do |backend|
      to_enable, to_disable = current_outputs.partition {|output| output[:id] == id }

      [to_enable, to_disable].zip(["enableoutput", "disableoutput"]).each do |outputs, command|
        outputs.each do |output|
          backend.command("#{command} %d", [output[:id]])
        end
      end
    end
  end

  private

  def to_song(mpd_response)
    {
      id: mpd_response.read_value("Id"),
      artist: mpd_response.read_value("Artist"),
      title: mpd_response.read_value("Title"),
      position: mpd_response.read_value("Pos"),
      time: mpd_response.read_value("Time")
    }
  end

  def outputs
    MpdBackend.query("outputs").slice_before(/^outputid:/).map do |mpd_response_part|
      {
        id: Integer(mpd_response_part.read_value("outputid")),
        name: mpd_response_part.read_value("outputname"),
        is_enabled: mpd_response_part.read_value("outputenabled") == "1"
      }
    end
  end
end
