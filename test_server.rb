
require 'gserver'
require 'optparse'

require 'packet'
require 'socket_support'

server_port = DEFAULT_PORT
packet_xml = 'protocol.xml'

ARGV.options do |opts|
  opts.banner = "Usage:  #{File.basename($0)}  [OPTIONS]"

  opts.separator ""
  opts.separator "Specific Options:"

  opts.on( '--port PORT', Integer, 
           'The port to listen for connections on.' ) do |port|
    server_port = port
  end

  opts.on( '--packet-xml FILE', String, 
           'The XML file to read protocol packet definitions from.' ) do |file|
    packet_xml = file
  end

  opts.separator "Common Options:"

  opts.on( '-h', '--help', 'Show this message.' ) do
    puts opts
    exit 1
  end
end.parse!

TPProto::XMLParser.define_packets_from_xml packet_xml

class ConnectionHandler
  def initialize(conn)
    @conn = conn
    @state = :initial
    info! "Connected"
  end
  attr_reader :conn
  def log(msg)
    puts "#{conn}: #{msg.gsub(/\n/, "\n   ")}"
  end
  def gone
    info! "Disconnected"
  end
  def okay(msg=nil)
    send TPProto::Okay.new( msg || 'Okay' )
  end
  def packet(packet)
    debug! "Packet: #{packet}"
    case @state
    when :initial
      case packet
      when TPProto::Connect
        info! "Client is #{packet.string.inspect}"
        okay "And who might you be?"
        @state = :waitauth
      else
        fail! TPProto::Fail::Code::Frame, "Unexpected packet discarded"
      end
    when :waitauth
      case packet
      when TPProto::Login
        if packet.username == 'admin@tp' && packet.password == 'adminpassword'
          info! "Authenticated as #{packet.username}"
          okay "Nice to see you!"
          @state = :idle
        else
          note! TPProto::Fail::Code::PermissionDenied, "Failed authentication for #{packet.username}", "Invalid username or password."
        end
      else
        fail! TPProto::Fail::Code::Frame, "Unexpected packet discarded"
      end
    when :idle
      case packet
      when nil; nil # TODO: Need a bit more functionality here :P
      else
        fail! TPProto::Fail::Code::Frame, "Unexpected packet discarded"
      end
    else
      crit! "Packet received while in unknown state!"
    end
  end

  # Lowest level trace information, including on-the-wire packet
  # representations.
  def trace!(internal_message)
    log "TRACE: #{internal_message}"
  end

  # Debugging messages, such as packet traces.
  def debug!(internal_message)
    log "DEBUG: #{internal_message}"
  end

  # Used to log "normal", but potentially noteworthy events.
  def info!(internal_message)
    log "INFO: #{internal_message}"
  end

  # This method is used when a client does something reasonable, which
  # just happens to fail. This is part of normal operation. An example
  # is an authentication failure. It is the client's responsibility to
  # decide whether it is able to recover from the error, and disconnect
  # if appropriate.
  def note!(protocol_code, internal_message, public_message=nil)
    log "NOTE: #{internal_message}"
    send TPProto::Fail.new( protocol_code, public_message || internal_message ) if protocol_code
  end

  # This method is used when the client does something very wrong;
  # generally a Frame or Protocol failure. Unlike #crit!, this is not
  # the server's fault. This is for irrecoverable errors; the client is
  # forcibly disconnected.
  def fail!(protocol_code, internal_message, public_message=nil)
    log "FAIL: #{internal_message}"
    send TPProto::Fail.new( protocol_code, public_message || internal_message )
    throw :disconnect
  end

  # This method is used when something Bad happens within the server. In
  # normal operation, it should never occur, no matter what the client
  # does. In an effort to recover (and to minimize vulnerability), we
  # drop the client connection.
  def crit!(internal_message)
    log "CRIT: #{internal_message}"
    send TPProto::Fail.new( TPProto::Fail::Code::Protocol, "Critical server failure" )
    throw :disconnect
  end

  def shutdown!
    send TPProto::Fail.new( TPProto::Fail::Code::Protocol, "Server shutting down" )
  end

  def send(packet)
    conn.write packet.to_wire
  end
end

class TPServer < GServer
  def initialize(port, *args)
    super port, *args
  end
  def serve(conn)
    handler = ConnectionHandler.new(conn)
    begin
      catch :disconnect do
        while (packet = read_packet_from_socket( conn ) { |msg| handler.trace! msg })
          handler.packet packet
        end
      end
    rescue 'stop'
      handler.shutdown!
    rescue
      catch :disconnect do
        handler.crit! "Unhandled Exception: #{$!}\n#{$!.backtrace.join("\n")}"
      end
    ensure
      handler.gone
    end
  end
end


if __FILE__ == $0
  s = TPServer.new( server_port )
  s.start
  puts "#{s}: Listening..."
  begin
    s.join
  rescue Interrupt
    puts "#{s}: Stopping"
    s.stop
    puts "#{s}: Stopped"
  end
end

