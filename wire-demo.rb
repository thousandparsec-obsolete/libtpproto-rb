
require 'packet'

define_packets_from_xml 'packet-partial.xml'

def wire_to_hex s
  s.unpack('C*').map {|c| ('0' + c.to_s(16))[-2,2] }.join('').gsub(/..../){|m|m+' '}
end
def hex_to_wire s
  s.gsub(/\s+/, '').gsub(/../){|m|m+' '}.split(' ').map{|c|c.to_i(16)}.pack('C*')
end

raw_wire = '5450 3033 0000 0002 0000 0001 0000 000f 0000 0004 0000 0007 7370 6c61 7421 00'

t = Okay.new('all good!')
f = Fail.new(Fail::Code::NoSuchThing, 'splat!')

t2 = Okay.from_wire(t.to_wire)
puts wire_to_hex(t.to_wire)
p t
puts wire_to_hex(f.to_wire)
p f

p Header.load(hex_to_wire(raw_wire))

