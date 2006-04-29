require 'pack'

PacketTypes = {}
PacketNames = {}
class Packet < Struct
  @@sequence = 0
  def to_wire
    prepare unless self.sequence
    to_a.pack(self.class.template)
  end
  def payload_size
    a = to_a
    self.class.header.keys.each { a.shift }
    t = self.class.template[self.class.header.template.size, self.class.template.size]
    a.pack(t).size
  end
  def prepare
    self.version = 'TP03'
    self.sequence = (@@sequence += 1)
    self.packet_type ||= find_packet_type(self.class)
    self.length = payload_size
  end
  def find_packet_type klass
    PacketTypes.each {|k,v| return k if v == klass }
    raise "Unknown packet type '#{klass}'"
  end
  def self.load wire_string
    header = self.header.from_wire( wire_string )
    packet_class = PacketTypes[header.packet_type]
    packet_class.from_wire( wire_string )
  end
  def self.from_wire wire_string
    raw_new *wire_string.unpack(template)
  end
  class << self
    attr_accessor :template
    attr_accessor :keys
    attr_accessor :header
  end
  def self.inherit name, parent, extra_template, *extra_keys
    return self.new( name, extra_template, *extra_keys ) unless parent

    c = new( name, parent.template + extra_template, *(parent.keys + extra_keys) )
    c.header = parent.header || parent
    c
  end
  def self.new name, template, *keys
    key_names = []
    keys.each do |k|
      if k.is_a? Hash
        children = k.values.first.map {|s| "#{k.keys.first}_#{s}" }
        key_names += children
        child_struct = Struct.new( "#{name}_#{k.keys.first}", *(k.values.first) )
        define_method( k.keys.first ) { child_struct.new( *(children.map {|c| send(c) }) ) }
        define_method( k.keys.first.to_s + '=' ) do |val| 
          if val.is_a?( Hash ) || val.is_a?( Struct )
            k.values.first.map {|s| send("#{k.keys.first}_#{s}=", val[s]) }
          elsif val.is_a?( Array )
            k.values.first.length.times { |i| send("#{k.keys.first}_#{k.values.first[i]}=", val[i]) }
          end
        end
      else
        key_names << k
      end
    end
    o = super(name, *key_names)
    class << o
      alias raw_new new
      def new *values
        a = values.dup
        header.keys.each { a.unshift nil }
        raw_new *a
      end
    end
    o.template = template
    o.keys = keys
    o.header = o
    o
  end
end

require 'rexml/document'

def translate_name_for_ruby name
  case name
  when :ID; :id
  when :type; :packet_type
  else name
  end
end

def define_enum_values klass, packet
  packet.each_element('structure/enumeration') do |enum|
    values = Module.new
    enum.each_element('values/value') do |v|
      values.const_set v.attribute('name').value, v.attribute('id').value.to_i
    end
    const_name = enum.elements['name'].text
    const_name = const_name[0,1].upcase + const_name[1,const_name.size]
    klass.const_set const_name, values
  end
end
def parse_template node
  case node.name
  when 'integer', 'enumeration'
    size = case (node.attribute('size').value.to_i rescue 32)
      when 16; ['%n', 'n', '%i']
      when 32; ['%N', 'N', '%l']
      when 64; ['q', 'Q', '%Q']
      end
    index_map = { 'signed' => 0, 'unsigned' => 1, 'semisigned' => 2 }
    type = node.attribute('type').value.to_s rescue 'signed'
    idx = index_map[type]
    size[idx]
  when 'string'
    '$a'
  when 'character'
    "a#{node.attribute('size').value.to_i.to_s rescue ''}"
  end
end
def parse_structure_def children
  template = ''; names = []
  children.each do |c|
    name = c.elements['name'].text.to_sym
    name = translate_name_for_ruby( name )
    if c.name == 'list'
      inner_template, inner_names = parse_structure_def( ( c.get_elements('structure')[0].get_elements('*') rescue [] ) )
      inner_template = "[#{inner_template}]"
    elsif c.name == 'group'
      inner_template, inner_names = parse_structure_def( ( c.get_elements('structure')[0].get_elements('*') rescue [] ) )
      name = { name => names }
    else
      inner_template = parse_template(c)
    end
    template << inner_template
    names << name
  end

  return template, names
end

def define_packets_from_xml xml_file
  doc = REXML::Document.new( File.read(xml_file) )
  klasses = []
  doc.root.each_element('packet') do |packet|
    name = packet.attribute('name').value.to_s
    next if PacketNames[name]
    parent = packet.attribute('base').value.to_s rescue nil
    parent_klass = PacketNames[parent]
    structure = packet.get_elements('structure')[0].get_elements('*') rescue []
    template_string, field_names = parse_structure_def(structure)
    klass = Packet.inherit( name, parent_klass, template_string, *field_names )
    define_enum_values klass, packet
    PacketNames[name] = klass
    PacketTypes[packet.attribute('code').value.to_i] = klass if packet.attribute('code')
    Object.const_set name, klass
    klasses << klass
  end
  klasses
end

