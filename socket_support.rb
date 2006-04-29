
DEFAULT_PORT = 6923
DEFAULT_SSL_PORT = 6924

def read_packet_from_socket( socket )
  # FIXME: Shouldn't be hard-coding the header length :|
  wire_header = socket.recvfrom(16)[0]
  return nil unless wire_header && wire_header != ''
  yield "Got header: #{ wire_to_hex( wire_header ) }" if block_given?
  header = TPProto::Header.from_wire( wire_header )
  wire_payload = socket.recvfrom( header.length )[0]
  yield "Got payload: #{ wire_to_hex( wire_payload ) }" if block_given?
  TPProto::Header.load( wire_header + wire_payload )
end

def wire_to_hex s
  s.unpack('C*').map {|c| ('0' + c.to_s(16))[-2,2] }.join('').gsub(/..../){|m|m+' '}
end

