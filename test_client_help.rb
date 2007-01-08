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
require 'client'

#$conn = TPConnection.new('localhost', 6923)
$conn = TPConnection.new

def r; $conn.read; end

def ok! msg=nil; @conn.okay(msg || 'Manual okay'); end
def fail! code, msg=nil; code = TPProto::Fail::Code.const_get(code) if code.is_a? Symbol; $conn.fail(code, msg || 'Manual failure'); end
def connect! client=nil; ident = 'libtpproto-rb'; ident = "#{client} [#{ident}]" if client; $conn.connect!(ident); end
def auth! user, pass; $conn.login!(user, pass); end

def c!
	connect! 'Ruby Interactive Test Client'
	auth! 'matthew', 'matthew'
end

