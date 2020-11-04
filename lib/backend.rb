require 'mpd_logger'
require 'mpd_backend'

class MpdCommandError < StandardError; end
class MpdNoAlbumArt < StandardError; end

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
    lines = MpdBackend.query("playlistinfo")

    return [] if lines.count <= 1

    entries = lines[1..-1].slice_before(/^file: /)

    entries.map do |entry_lines|
      to_song(entry_lines)
    end
  end

  def status
    lines = MpdBackend.query("status")

    result = {
      repeat: read_value("repeat", lines),
      random: read_value("random", lines),
      single: read_value("single", lines),
      consume: read_value("consume", lines),
      state: read_value("state", lines),
      volume: read_value("volume", lines, default: '-'),
      outputs: self.outputs
    }

    if result[:state] == "stop"
      result
    else
      result.merge({
        songid: read_value("songid", lines),
        elapsed: read_value("elapsed", lines),
        duration: read_value("duration", lines)
      })
    end
  end

  def set_volume(volume)
    MpdBackend.command("setvol %d", [Integer(volume)])
  end

  def play_id(id)
    MpdBackend.command("playid %d", [Integer(id)])
  end

  def get_albumart(album, output_file)
    offset = 0

    song_uri = first_song_uri(album).gsub(/"/, "\\\"")

    begin
      File.open(output_file, "wb") do |file|
        loop do
          response = MpdBackend.fetch_albumart(album, song_uri, offset)

          break if response[:byte_count] == 0

          file.write response[:bytes]

          offset += response[:byte_count]
        end
      end
    rescue MpdNoAlbumArt
      FileUtils.rm_f output_file
      raise
    end
  end

  def first_song_uri(album)
    songs_result = MpdBackend.query(%[find "((Album == '%s') AND (AlbumArtist == '%s'))"], [album.title, album.artist])

    read_value("file", songs_result)
  end

  def albums
    albums_and_artists = MpdBackend.query("list album group albumartistsort")

    artist_header = %r[\AAlbumArtistSort: ]
    album_header = %r[\AAlbum: ]

    albums_and_artists.slice_before(artist_header).each_with_object([]) do |group, result|
      artist = group[0].gsub(artist_header, "")

      titles = group[1..-1].map { |title| title.gsub(album_header, "") }

      titles.each do |title|
        result << Album.new(
          title.force_encoding("UTF-8"),
          artist.force_encoding("UTF-8")
        )
      end
    end.sort_by {|album| album.artist.downcase }
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

  def to_song(entry_lines)
    {
      id: read_value("Id", entry_lines),
      artist: read_value("Artist", entry_lines),
      title: read_value("Title", entry_lines),
      position: read_value("Pos", entry_lines),
      time: read_value("Time", entry_lines)
    }
  end

  def outputs
    MpdBackend.query("outputs")[1..-1].slice_before(/^outputid:/).map do |output_lines|
      {
        id: Integer(read_value("outputid", output_lines)),
        name: read_value("outputname", output_lines),
        is_enabled: read_value("outputenabled", output_lines) == "1"
      }
    end
  end

  def read_value(field_name, input, default: nil)
    regex = %r[^#{field_name}: (.*)]

    matching_lines = input.grep(regex)

    if matching_lines.none? && default
      return default
    end

    matches = matching_lines[0].match(regex)

    matches[1]
  end
end
