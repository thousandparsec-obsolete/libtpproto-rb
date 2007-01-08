
require 'socket'
require 'packet'

DEFAULT_PORT = 6923
DEFAULT_SSL_PORT = 6924

TPProto::XMLParser.define_packets_from_xml 'protocol.xml'

class String
  def underscore
    gsub(/([A-Z0-9]{2,}s?|[A-Z][^A-Z]+)(?=$|[A-Z])/, '_\1').sub(/^_/, '').downcase
  end
end

class TPConnection
  FrameHandler = Struct.new(:frame_type, :max_calls, :block)

  def initialize(host='demo1.thousandparsec.net', port=DEFAULT_PORT)
    @conn = TCPSocket.new( host, port )
    @handlers = []
    @unprocessed = []
    handle :sequence, -1 do |frame|
      frames = []
      frame.number.times do
        frames << get_unprocessed
      end
      prototype = (frames.find {|fr| !(TPProto::Fail === fr) } || frames.first)
      invoke_handler frame_type_from_frame(prototype), frames
    end
  end
  TPProto::PacketNames.each do |name, klass|
    method_name = name.underscore
    class_eval <<-END, __FILE__, __LINE__
    def #{method_name}(*a)
      @conn.write #{klass.name}.new(*a).to_wire
    end
    def #{method_name}!(*a)
      #{method_name} *a
      result = get_unprocessed
      if TPProto::Fail === result
        raise "Protocol error: \#{result}"
      end
      result
    end
    END
  end
  def handle(frame_type, max_calls=1, &block)
    max_calls = nil unless Integer === max_calls || max_calls < 1
    @handlers << FrameHandler.new(frame_type, max_calls, block)
  end
  def check_queue!
    if frame = read(false)
      process_frame frame
    end
  end
  def process_frame(frame)
    invoke_handler frame_type_from_frame(frame), frame
  end
  def frame_type_from_frame(frame)
    frame.class.name.sub(/.*::/, '').underscore
  end
  def invoke_handler(frame_type, frame)
    if handler = @handlers.find {|hd| hd.frame_type.to_s == frame_type }
      handler.block.call *[frame].flatten
      handler.max_calls -= 1 if handler.max_calls
      @handlers.delete handler if handler.max_calls == 0
    else
      @unprocessed << frame
    end
    handler
  end
  def read(block=true)
    # FIXME: Shouldn't be hard-coding the header length :|
    begin
      wire_header = @conn.__send__(block ? :recvfrom : :recvfrom_nonblock, 16)[0]
    rescue Errno::EAGAIN
      return nil
    end

    return nil unless wire_header && wire_header != ''
    header = TPProto::Header.from_wire( wire_header )
    wire_payload = ''
    while wire_payload.size < header.length
      wire_payload << @conn.recvfrom( header.length - wire_payload.size )[0]
    end
    packet = TPProto::Header.load( wire_header + wire_payload )
  end
  def get_unprocessed
    process_frame( read ) while @unprocessed.empty?
    @unprocessed.shift
  end
end


def object_tree(root=nil, indent='')
  root ||= $conn.get_objects_by_id!([0]).first
  n = 1

  puts indent + root.class.name.sub(/.*::/, '') + ' #' + root.id.to_s + ' - ' + root.name
  children = $conn.get_objects_by_id!(root.contains)
  children.each do |child|
    n += object_tree(child, indent + '  ')
  end

  n
end

