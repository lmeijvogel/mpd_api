require 'json'
require 'socket'

class SnapcastBackend
  HOSTNAME = "192.168.2.16"
  PORT = 1705

  def self.build
    @request_id ||= 1

    new(@request_id)
  end

  def initialize(request_id)
    @request_id = request_id
  end

  def client_for_ip(ip)
    clients.find {|client| client.dig("host", "ip") =~ /#{ip}$/ }
  end

  def groups_for_ip(ip)
    current_client = client_for_ip(ip)

    if !current_client
      puts "IP address #{ip} not connected to client."
      return []
    end

    groups.select do |group|
      group["clients"].any? do |client|
        client["id"] == current_client["id"]
      end
    end
  end

  def client_playing?(ip)
    playing_streams = streams.select {|stream| stream["status"] == "playing" }
    playing_stream_ids = playing_streams.map {|stream| stream["id"] }

    groups_for_ip(ip).any? do |group|
      playing_stream_ids.include? group["stream_id"]
    end
  end

  def status
    @status ||= begin
                  TCPSocket.open(HOSTNAME, PORT) do |socket|
                    request_body = %|{"id":#{@request_id},"jsonrpc":"2.0","method":"Server.GetStatus"}|

                    socket.write(request_body)
                    socket.write("\r\n")

                    JSON.parse(socket.gets)["result"]
                  end
                end
  end

  def server_status
    status["server"]
  end

  def groups
    server_status["groups"]
  end

  def clients
    groups.flat_map {|group| group["clients"] }
  end

  def streams
    server_status["streams"]
  end
end
