
require 'collar/fool'
require 'collar/blacklist'

module Collar
  class TypeScriptor
    include Collar::Mangler
    include Collar::Blacklist
  
    def initialize(opts, spec)
      @opts = opts
      @spec = spec
    end

    def typescriptize
      path = @spec.path

      f = Fool.new("#{@opts[:typescript]}/#{path}.ts")

      classes = @spec.entities.select do |en|
        en[1].type == "class"
      end

      classes.each do |cl|
        class_short_name = cl[1].name
        class_long_name = cl[1].fullName
        f << "declare class #{class_long_name} {"

        cl[1].members.each do |mb|
          next if (mb[0].start_with?('__')) || MEMBERS_BLACKLIST.include?(mb[0])

          case mb[1].type
          when 'method'
            translate_method(f, mb[1])
          when 'field'
            translate_field(f, mb[1])
          end
        end

        f << "};"
        f << "export class #{class_short_name} extends #{class_long_name} {};"
        f.nl
      end

      f.close
    end

    private

    def translate_method(f, mdef)
      mangled_name = mdef.name.gsub(/~/, '_')

      arglist = []
      mdef.arguments.each do |arg|
        arglist << "#{arg[0]}: any"
      end

      if mdef.modifiers.include? 'static'
        f << "  static #{mangled_name}: (#{arglist.join(', ')}) => any;"
      else
        f << "  #{mangled_name}(#{arglist.join(', ')}): any;"
      end
    end

    def translate_field(f, fdef)
      mangled_name = fdef.name.gsub(/~/, '_')

      f.write "  "
      f.write "static " if fdef.modifiers.include? 'static'
      f.write mangled_name
      f.write ": any;"
      f.nl
    end

  end
end

