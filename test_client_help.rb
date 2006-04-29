# This just defines a few useful methods for hand-cranking a connection
# to the server. Use it like this:
#
#   $ irb -rtest_client_help
#   irb(main):001:0> c!
#   => true
#   irb(main):002:0> ok! 'Blah!'
#   => true
#   irb(main):003:0> r
#   => #<struct Packet::Fail version="TP03", sequence=3, packet_type=1,
#   length=36, code=1, result="Unexpected packet discarded">
#

require 'socket'

require 'packet'
require 'socket_support'
include TPProto

$conn = TCPSocket.new( 'localhost', 6923 )
XMLParser.define_packets_from_xml 'protocol.xml'

def s p; $conn.write p.to_wire; true; end
def r; read_packet_from_socket $conn; end

def ok! msg=nil; s Okay.new(msg || 'Manual okay'); end
def fail! code, msg=nil; code = Fail::Code.const_get(code) if code.is_a? Symbol; s Fail.new(code, msg || 'Manual failure'); end
def connect! client=nil; ident = 'libtpproto-rb'; ident = "#{client} [#{ident}]" if client; s Connect.new(ident); end
def auth! user, pass; s Login.new(user, pass); end

def c!
	connect! 'Ruby Interactive Test Client'
	raise "Connect failed" unless Okay === r
	auth! 'admin@tp', 'adminpassword'
	raise "Auth failed" unless Okay === r
	true
end

