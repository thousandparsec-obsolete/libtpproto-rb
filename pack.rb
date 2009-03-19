
module PackListExtensions
  def first_pack_list_type(template_string)
    list_types = [['[', ']', 'N', nil], ['{', '}', 'Q', nil], ['$', '', 'N', :string], ['%', nil, nil, nil]]

    list_types.each { |lt| lt.push template_string.index( lt[0] ) }
    list_types.delete_if {|lt| lt[4].nil? }
    list_types = list_types.sort_by {|lt| lt[4] }

    list_types.first
  end
  def handle_list_extensions(original, template_string)
    list_type = first_pack_list_type( template_string )

    return yield( split_template( template_string, list_type[0], list_type[1] ), list_type[2], list_type[3] ) if list_type
    send( original, template_string )
  end
  def split_template(template_string, left_bracket, right_bracket)
    parts = template_string.split(left_bracket, 2)
    parts[1], parts[2] = parts.last.split(right_bracket, 2) if right_bracket
    return parts
  end
  def unsigned_template_character_from_semisigned(match_char)
    case match_char when 'i' then 'n' when 'l' then 'N' end
  end
  def unsigned_template_character(match_char)
    '%' + match_char
  end
  def bit_size_of_unsigned_template_character(match_char)
    case match_char when 'S', 's', 'n' then 16 when 'N' then 32 end
  end
end

class Array
  include PackListExtensions
  alias original_pack pack
  def pack(template_string)
    handle_list_extensions :original_pack, template_string do |parts, size_format, special|
      # Ruby natively handles packing negative values into an unsigned,
      # so we just have to change it to use the right byte-order
      # character.
      parts[1].gsub!( /^[A-Za-z][0-9]*/ ) { |c| unsigned_template_character_from_semisigned( c ) || c }
      return pack(parts.join('')) unless size_format

      s = original_pack( parts[0] )
      a = s.unpack( parts[0] )
      rest = self[a.size, size]

      inner_value = rest.shift
      if special == :string
        s << [inner_value.size + 1, inner_value].pack( "#{size_format}a#{inner_value.size + 1}" )
      else
        inner_value = [inner_value] unless inner_value.is_a? Array
        s << [inner_value.size].pack(size_format)
        inner_value.each do |el|
          #puts "Packing inner #{((el.is_a? Array ) ? el : [el]).inspect} with #{parts[1].inspect}"
          s << ((el.is_a? Array ) ? el : [el]).pack( parts[1] )
        end
      end
      s << rest.pack( parts[2] )
    end
  end
end

class String
  include PackListExtensions
  alias original_unpack unpack
  def unpack(template_string)
    handle_list_extensions :original_unpack, template_string do |parts, size_format, special|
      s = dup

      unless size_format
        left = s.unpack!(parts[0])
        next_template = parts[1].slice!( /^[A-Za-z][0-9]*/ )
        bit_size = bit_size_of_unsigned_template_character( next_template )
        if bit_size
          value = s.unpack!( next_template ).first
          value -= 2 ** bit_size if value > 2 ** (bit_size - 1)
        else
          next_template = unsigned_template_character_from_semisigned( next_template )
          bit_size = bit_size_of_unsigned_template_character( next_template )
          value = s.unpack!( next_template ).first
          value = -1 if bit_size && value == 2 ** bit_size - 1
        end
        right = s.unpack(parts[1])
        return left + [value] + right
      end

      left_content = s.unpack!( parts[0] )
      middle_length = s.unpack!( size_format ).first
      middle_content = []
      middle_length.times do
        el = s.unpack!(parts[1])
        middle_content << (el.size == 1 ? el.first : el)
      end
      if special == :string
        middle_content = middle_content.join('')
        middle_content.chop! if !middle_content.empty? && middle_content[-1].zero?
      end
      right_content = s.unpack(parts[2])
      left_content + [middle_content] + right_content
    end
  end
  def unpack!(template_string)
    unpacked = unpack(template_string)
    slice! 0, unpacked.pack(template_string).size
    unpacked
  end
end

if $0 == __FILE__
  require 'test/unit'
  class PackTests < Test::Unit::TestCase
    def test_things
      t 'SZ*L$aZ*N', [17, 'xyzzy', 234125, 'whee whee', 'blah blah', 253523]
      t '[C]', ['foo foo'.split('').map{|c|c[0]}]
      t 'Z*%S', ['s', 1123]
      t '[Z*%S]', [[['s', 1123], ['xz', 3], ['--', 1789]]]
      t '[C][Z*%S]SZ*L$aZ*N', ['foo foo'.split('').map{|c|c[0]}, [['s', 1123], ['xz', -1], ['--', 1789]], 17, 'xyzzy', 234125, 'whee whee', 'blah blah', 253523]
      t 'a4[N]', ['abcd', [12, 34, 56, 78, 90, 123, 456, 789, 1234, 5687, 90123, 45678, 901234, 567890]]
      t 'a4[%N]', ['abcd', [12, -34, 56, -78, 90, -123, 456, -789, 1234, -5687, 90123, -45678, 901234, -567890]]
    end
    def t(f, a)
      s = a.pack(f)
      p s
      puts s.unpack('C*').map {|c| ('0' + c.to_s(16))[-2,2] }.join(' ').gsub(/ (..) /){|m|$1+' '}

      a2 = s.unpack(f)
      assert_equal a, a2

      s2 = a2.pack(f)
      assert_equal s, s2
    end
  end
end

