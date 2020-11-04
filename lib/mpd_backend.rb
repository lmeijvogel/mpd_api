require 'mpd_logger'

class MpdBackend
  def self.command(command, parameters = [], socket: nil)
    new(socket: socket).command(command, parameters)
  end

  def self.query(command, parameters = [], socket: nil)
    new(socket: socket).query(command, parameters)
  end

  def self.command_list(&block)
    TCPSocket.open(HOSTNAME, PORT) do |socket|
      backend = MpdBackend.new(socket: socket)

      begin
        backend.command("command_list_begin", [])

        block.yield backend
      ensure
        # Receive the response from mpd so it can close its end of the connection.
        # Otherwise, later commands will wait and timeout because mpd didn't finish its
        # last request yet.
        backend.query("command_list_end", [])
      end
    end
  end

  def self.read_albumart(album, song_uri, offset = 0)
    MpdBackend.command = Interpolator.interpolate(%Q[albumart %s %d], [song_uri, offset])

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

  def initialize(socket: nil)
    @socket = socket
  end

  def command(query, parameters)
    interpolated_query = Interpolator.interpolate(query, parameters)

    send(interpolated_query, should_read_response: @socket.nil?) # Only read response if no socket was given: That means that this request is not in a command list

    nil
  end

  def query(query, parameters)
    interpolated_query = Interpolator.interpolate(query, parameters)

    send(interpolated_query, should_read_response: true)
  end

  def send(query, should_read_response:)
    MpdLogger.debug("Sending command [[#{@query}]])")

    if @socket
      # Never read response for an existing socket: That is likely a
      # command list, so we don't receive responses for each query.
      send_query(query, socket: @socket, should_read_response: should_read_response)
    else
      TCPSocket.open(HOSTNAME, PORT) do |socket|
        send_query(query, socket: socket, should_read_response: should_read_response)
      end
    end
  end

  private
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
    def self.interpolate(string, args)
      escaped_args = args.map do |arg|
        case arg
        when Integer, Numeric
          arg
        else
          escaped = arg.to_s.gsub(/'/, "\\\\\\\\'").gsub(/"/, '\\"')
          %['#{escaped}']
        end
      end

      format(string, *escaped_args)
    end
  end
end

