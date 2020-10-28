require 'socket'

require 'mpd_logger'

class MpdCommandError < StandardError; end
class MpdNoAlbumArt < StandardError; end

HOSTNAME = "192.168.2.3"
# HOSTNAME = "192.168.2.4"
PORT = 6600

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
    lines = query("playlistinfo")

    return [] if lines.count <= 1

    entries = lines[1..-1].slice_before(/^file: /)

    entries.map do |entry_lines|
      to_song(entry_lines)
    end
  end

  def command(command)
    query(command)
  end

  def status
    lines = query("status")

    result = {
      repeat: read_value("repeat", lines),
      random: read_value("random", lines),
      single: read_value("single", lines),
      consume: read_value("consume", lines),
      state: read_value("state", lines),
      volume: read_value("volume", lines, default: '-')
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
    query("setvol #{volume}")
  end

  def play_id(id)
    query("playid #{id}")
  end

  def get_albumart(album, output_file)
    offset = 0

    song_uri = first_song_uri(album).gsub(/"/, "\\\"")

    begin
      File.open(output_file, "wb") do |file|
        loop do
          response = read_albumart(album, song_uri, offset)

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
    interpolated_query = interpolate(%[find "((Album == '%s') AND (AlbumArtist == '%s'))"], album.title, album.artist)

    songs_result = query(interpolated_query)

    read_value("file", songs_result)
  end

  def albums
    albums_and_artists = query("list album group albumartistsort")

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
    query("command_list_begin", should_read_response: false)
    query("clear", should_read_response: false)
    query(interpolate(%[findadd "((Album == '%s') AND (AlbumArtist == '%s'))"], title, artist))
    query("play", should_read_response: false)
    query("command_list_end", should_read_response: false)
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

  def interpolate(query, *args)
    escaped_args = args.map {|arg| arg.gsub(/'/, "\\\\\\\\'").gsub(/"/, '\\"') }

    format(query, *escaped_args)
  end

  def read_albumart(album, song_uri, offset = 0)
    command = %Q[albumart "#{song_uri}" #{offset}]

    MpdLogger.debug("Retrieving albumart [[#{command}]])")

    TCPSocket.open(HOSTNAME, PORT) do |socket|
      socket.write command
      socket.write "\n" unless command.end_with?("\n")
      socket.flush

      welcome_line = socket.gets

      size_line = socket.gets

      raise MpdNoAlbumArt if size_line =~ /^ACK.*No file exists/

      binary_line = socket.gets

      size_line =~ /size: (\d+)/
      total_size_in_bytes = $1

      binary_line =~ /binary: (\d+)/
      current_bytes = Integer($1)

      bytes = socket.read(current_bytes)

      ok_line = socket.gets

      {
        total_byte_count: Integer(total_size_in_bytes),
        byte_count: Integer(current_bytes),
        bytes: bytes
      }
    end
  end

  def query(command, should_read_response: true)
    MpdLogger.debug("Sending command [[#{command}]])")

    TCPSocket.open(HOSTNAME, PORT) do |socket|
      socket.write command
      socket.write "\n" unless command.end_with?("\n")
      socket.flush

      read_response(socket) if should_read_response
    end
  end

  def read_response(socket)
    result = []

    loop do
      line = socket.gets

      break if line.strip == "OK"

      if line.start_with?("ACK")
        raise MpdCommandError, line
      end

      result << line.strip.force_encoding("UTF-8")
    end

    result
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
