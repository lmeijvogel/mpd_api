require 'mpd_logger'
require 'mpd_response'

class MpdConnectionError < StandardError; end
class MpdCommandError < StandardError; end
class MpdNoAlbumArt < StandardError; end

class MpdBackend
  def self.command(command, parameters = [])
    new.command(command, parameters)
  end

  def self.query(command, parameters = [])
    new.query(command, parameters)
  end

  def self.command_list(&block)
    open_socket do |socket|
      backend = MpdBackend.new(socket: socket)

      backend.prevent_reading_response = true

      begin
        backend.command("command_list_begin", [])

        block.yield backend
      ensure
        # Receive the response from mpd so it can close its end of the connection.
        # Otherwise, later commands will wait and timeout because mpd didn't finish its
        # last request yet.
        backend.prevent_reading_response = false
        backend.command("command_list_end", [])
      end
    end
  end

  def self.fetch_and_save_albumart(album, output_file)
    offset = 0

    song_uri = first_song_uri(album).gsub(/"/, "\\\"")

    loop do
      response = fetch_albumart_part(album, song_uri, offset)

      break if response[:byte_count] == 0

      output_file.write response[:bytes]

      offset += response[:byte_count]
    end
  end

  def self.first_song_uri(album)
    songs_result = MpdBackend.query(%[find "((Album == %s) AND (AlbumArtist == %s))"], [album.title, album.artist])

    songs_result.read_value("file")
  end

  def self.fetch_albumart_part(album, song_uri, offset = 0)
    command = Interpolator.interpolate(%Q[albumart %s %d], [song_uri, offset], quote_char: '"')

    open_socket do |socket|
      banner_line = socket.gets

      socket.write command
      socket.write "\n" unless command.end_with?("\n")
      socket.flush

      size_line = socket.gets

      raise MpdNoAlbumArt if size_line =~ /^ACK.*No file exists/
      raise MpdCommandError, "Error occurred! '#{size_line.strip}'" if size_line =~ /^ACK/

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

  def initialize(socket: nil)
    @socket = socket
  end

  def command(query, parameters)
    interpolated_query = Interpolator.interpolate(query, parameters)

    send(interpolated_query, should_read_response: !prevent_reading_response) # Read the response if it is allowed, to clear mpd's send queue.

    nil
  end

  def query(query, parameters)
    raise MpdCommandError, "Forbidden to query in command_list_mode." if prevent_reading_response

    interpolated_query = Interpolator.interpolate(query, parameters)

    response_text = send(interpolated_query, should_read_response: true)

    MpdResponse.new(response_text)
  end

  def send(query, should_read_response:)
    MpdLogger.debug("Sending command [[#{@query}]])")

    if @socket
      send_query(query, socket: @socket, should_read_response: should_read_response)
    else
      open_socket do |socket|
        send_query(query, socket: socket, should_read_response: should_read_response)
      end
    end
  end

  attr_accessor :prevent_reading_response

  private

  def open_socket(&block)
    TCPSocket.open(HOSTNAME, PORT) do |socket|
      banner_line = socket.gets

      raise MpdConnectionError, "Error connecting: '#{banner_line.strip}'" if banner_line !~ /\AOK MPD/

      block.yield socket
    end
  end

  def send_query(query, socket:, should_read_response:)
    socket.write query
    socket.write "\n" unless query.end_with?("\n")
    socket.flush

    begin
      read_response(socket) if should_read_response
    rescue MpdCommandError => e
      raise MpdCommandError, "#{e.message}. Command: [[#{query}]]"
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

  module Interpolator
    def self.interpolate(string, args, quote_char: "'")
      escaped_args = args.map do |arg|
        case arg
        when Integer, Numeric
          arg
        else
          if quote_char == "'"
            escaped = arg.to_s.gsub(/'/, "\\\\\\\\'").gsub(/"/, '\\"')
            %['#{escaped}']
          else
            escaped = arg.to_s.gsub(/"/, '\\\\\\\\"').gsub(/'/, "\\'")
            %["#{escaped}"]
          end
        end
      end

      format(string, *escaped_args)
    end
  end
end
