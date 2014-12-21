
require 'collar/fool'
require 'collar/blacklist'
require 'collar/types'
require 'collar/logger'

module Collar
  class TypeScriptor
    include Collar::Mangler
    include Collar::Blacklist
    include Collar::Types
    include Collar::Logger
  
    def initialize(opts, spec, registry)
      @opts = opts
      @spec = spec
      @registry = registry
      @imports = []
    end

    def typescriptize
      path = @spec.path

      f = Fool.new("#{@opts[:typescript]}/#{path}.ts")

      @spec.globalImports.each do |imp|
        import_if_necessary(imp)
      end
      f.nl

      @spec.entities.each do |en|
        case en[1].type
        when 'class'
          translate_class(f, en)
        when 'enum'
          translate_enum(f, en)
        when 'cover'
          translate_cover(f, en)
        end
      end

      import_tmp = []
      @imports.each do |imp|
        import_tmp << "import #{imp.gsub(/\//, '_')} = require('#{imp}');"
      end
      import_tmp << ""
      f.prepend(import_tmp.join("\n"))

      f.close
    end

    def translate_cover(f, cv)
      short_name = cv[1].name
      long_name = "#{@spec.path.gsub('/', '_')}__#{cv[1].name}"
      f << "class #{long_name} {};"
      f << "export class #{short_name} extends #{long_name} {};"
    end

    def translate_enum(f, en)
      short_name = en[1].name
      long_name = "#{@spec.path.gsub('/', '_')}__#{en[1].name}"
      f << "export interface #{long_name}_static {"
      en[1].elements.each do |mb|
        f << "  #{mb[0]}: number;"
      end
      f << "};"
      f << "declare var #{long_name}: #{long_name}_static;"
      f << "export var #{short_name} = #{long_name};"
    end

    def translate_class(f, cl)
      class_short_name = cl[1].name
      class_long_name = cl[1].nameFqn

      static_members = []
      nonstatic_members = []

      cl[1].members.each do |mb|
        next if (mb[0].start_with?('__')) || MEMBERS_BLACKLIST.include?(mb[0])
        if mb[1].modifiers.include? 'static'
          static_members << mb
        else
          nonstatic_members << mb
        end
      end

      f<< "export interface #{class_long_name}_static {"
      static_members.each { |mb| translate_member(f, mb) }
      f << "};"
      f.nl

      f.write "export interface #{class_long_name} "
      if cl[1].extendsFqn && viable_imported_type?(cl[1].extendsFqn)
        f.write "extends #{type_to_ts(cl[1].extendsFqn)} "
      end

      f << "{"
      nonstatic_members.each { |mb| translate_member(f, mb) }
      f << "};"
      f << "export interface #{class_short_name} extends #{class_long_name} {};"
      f << "declare var #{class_long_name}: #{class_long_name}_static;"
      f << "export var #{class_short_name} = #{class_long_name};"
      f.nl
    end

    def import_if_necessary(imp)
      return if imp.start_with?("lang/")
      return unless @registry.spec_paths.include?(imp)
      return if @imports.include?(imp)
      @imports << imp
    end

    private

    def translate_member(f, mb)
      case mb[1].type
      when 'method'
        translate_method(f, mb[1])
      when 'field'
        translate_field(f, mb[1])
      end
    end

    def translate_method(f, mdef)
      return unless mdef.arguments.all? { |arg| supported_type?(arg[1]) }
      unless mdef.returnType.nil?
        return unless supported_type?(mdef.returnType)
      end
      return unless mdef.genericTypes.empty?

      mangled_name = mdef.name.gsub(/~/, '_')

      arglist = []
      mdef.arguments.each do |arg|
        arglist << "#{arg[0]}: #{type_to_ts(arg[3])}"
      end

      if mdef.name == 'new'
        f.write "  #{mangled_name}: (#{arglist.join(', ')}) => "
      else
        f.write "  #{mangled_name}(#{arglist.join(', ')}): "
      end

      if mdef.returnTypeFqn
        f.write type_to_ts(mdef.returnTypeFqn)
      else
        f.write "void"
      end

      f.write ";"
      f.nl
    end

    def translate_field(f, fdef)
      return unless supported_type?(fdef.varType)
      mangled_name = fdef.name.gsub(/~/, '_')

      f.write "  "
      f.write mangled_name
      f.write ": "
      f.write type_to_ts(fdef.varTypeFqn)
      f.write ";"
      f.nl
    end

    def type_to_ts(type)
      case type
      when /^lang_String__/
        "string"
      when /^lang_Numbers__/
        "number"
      when /^Func\(/
        args = fun_type_parse(type).arguments

        arglist = []
        args.each_with_index do |arg, i|
          arglist << "arg#{i}: #{type_to_ts(arg)}"
        end

        "(#{arglist.join(", ")}) => any"
      when "lang_types__Bool"
        "boolean"
      when "Void", "void"
        "void"
      else
        td = @registry.type_catalog[type]
        if td && td[1].type == 'enum'
          return "number"
        end

        if td && td[1].type == 'cover'
          if td[1].fromFqn
            under = type_to_ts(td[1].fromFqn)
            if under != "any"
              # found primitive cover! use that :)
              return under
            end
          end
        end

        tokens = type.split('__')
        return "any" unless tokens.length == 2

        type_path, type_name = tokens
        imp_path = type_path.gsub('_', '/')

        if type_path == @spec.path.gsub('/', '_')
          type
        elsif @registry.spec_paths.include?(imp_path)
          import_if_necessary(imp_path)
          "#{type_path}.#{type_name}"
        else
          "any"
        end
      end
    end

    def viable_imported_type?(type)
      tokens = type.split('__')
      return false unless tokens.length == 2

      type_path, _ = tokens
      imp_path = type_path.gsub('_', '/')

      if type_path == @spec.path.gsub('/', '_')
        true
      elsif @registry.spec_paths.include?(imp_path)
        true
      else
        false
      end
    end

  end
end

