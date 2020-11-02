require 'mpd_logger'

class MpdBackend
  def self.command(command, parameters = [], socket: nil)
    new(command, parameters, socket: socket, should_read_response: false).send
  end

  def self.query(command, parameters = [], socket: nil)
    new(command, parameters, socket: socket, should_read_response: true).send
  end

  def self.command_list(&block)
    TCPSocket.open(HOSTNAME, PORT) do |socket|
      begin
        Query.send("command_list_begin", [], socket: socket)

        block.yield socket
      ensure
        Query.send("command_list_end", [], socket: socket)
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

  def initialize(command, parameters = [], socket: nil, should_read_response: true)
    @query = Interpolator.interpolate(command, parameters)

    @socket = socket

    @should_read_response = !socket && should_read_response
  end

  def send
    MpdLogger.debug("Sending command [[#{@query}]])")

    if @socket
      # Never read response for an existing socket: That is likely a
      # command list, so we don't receive responses for each query.
      send_query(socket: @socket)
    else
      TCPSocket.open(HOSTNAME, PORT) do |socket|
        send_query(socket: socket)
      end
    end
  end

  private
  def send_query(socket:)
    socket.write @query
    socket.write "\n" unless @query.end_with?("\n")
    socket.flush

    begin
      read_response(socket) if @should_read_response
    rescue MpdCommandError => e
      raise MpdCommandError, "#{e.message}. Command: [[#{@query}]]"
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

