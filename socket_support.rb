
def wire_to_hex s
  s.unpack('C*').map {|c| ('0' + c.to_s(16))[-2,2] }.join('').gsub(/..../){|m|m+' '}
end

