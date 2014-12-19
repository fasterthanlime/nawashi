
require 'collar/prelude'
require 'collar/types'
require 'collar/mangler'
require 'collar/fool'
require 'collar/blacklist'
require 'collar/logger'

module Collar
  class Translator
    include Collar::Prelude
    include Collar::Types
    include Collar::Mangler
    include Collar::Blacklist
    include Collar::Logger

    attr_reader :import_path

    def initialize(opts, spec, all_bindings, inheritance_chains, registry)
      @opts = opts
      @spec = spec
      @all_bindings = all_bindings
      @inheritance_chains = inheritance_chains
      @registry = registry
      @import_path = "duk/#{@spec.path}"
      @imports = []
    end

    def translate
      f = Fool.new("#{@opts[:output]}/#{@import_path}.ooc")

      f << AUTOGEN_NOTICE
      f << "import duk/tape, collar/extensions"
      f << "import #{@spec.path}"
      f.nl

      @spec.uses.each do |uze|
        f << "use #{uze}"
      end
      f.nl

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
        end
      end

      import_tmp = []
      @imports.each do |imp|
        import_tmp << "import #{imp}"
      end
      import_tmp << ""
      f.prepend(import_tmp.join("\n"))

      f.close
      oyea "#{@spec.path}"
    end

    private

    def import_if_necessary(imp)
        return if imp.start_with?("lang/")
        return if @imports.include?(imp)

        @imports << imp
    end

    def translate_method(f, mdef, class_name, method_bindings)
      return unless mdef.arguments.all? { |arg| supported_type?(arg[1]) }
      unless mdef.returnType.nil?
        return unless supported_type?(mdef.returnType)
      end
      return unless mdef.genericTypes.empty?

      ooc_name = unmangle(mdef.name)
      mangled_name = mdef.name.gsub(/~/, '_')
      static = mdef.modifiers.include? 'static'

      method_binding = Hashie::Mash.new(
        :wrapper => "_duk_#{mdef.fullName}",
        :nargs => mdef.arguments.length,
        :name => mangled_name,
      )
      method_bindings << method_binding

      f << "#{method_binding.wrapper}: func (duk: DukContext) -> Int {"

      args = []

      mdef.arguments.each_with_index do |arg, i|
        if type_is_fun?(arg[1])
          args << arg[0]
          f.nl
          f << "  duk requireObjectCoercible(#{i})"

          fun_type = fun_type_parse(arg[3])
          closure_arg_types = fun_type.arguments
          closure_arg_list = []
          closure_arg_types.each_with_index do |closure_arg_type, j|
            closure_arg_list << "__arg#{j}: #{type_to_ooc(closure_arg_type)}"
          end

          f.nl
          f << "  closureID := DukContext freshID()"
          f << "  duk dup(#{i})"
          f << "  duk putGlobalString(closureID)"
          f.nl
          ret = if fun_type.return
                  "-> #{type_to_ooc(fun_type.return)}"
                else
                  ""
                end
          f << "  #{arg[0]} := func (#{closure_arg_list.join(", ")}) #{ret} {"
          f << "    duk getGlobalString(closureID)"
          closure_arg_types.each_with_index do |closure_arg_type, j|
            f << push_something("__arg#{j}", closure_arg_type, :level => 2)
          end
          f << "    if(duk pcall(#{closure_arg_list.length}) != 0) { duk raise!() }"
          if fun_type.return
            f << require_something("__retval", fun_type.return, :level => 2, :index => -1)
          end
          f << "    duk pop()"
          if fun_type.return
            f << "    return __retval"
          end
          f << "  }"
          f.nl
        else
          args << arg[0]
          f << require_something(arg[0], arg[3], :index => i)
        end
      end
      f.nl

      arglist = args.join(", ")
      mvoid = mdef.returnType.nil?
      capture = mvoid ? "" : "__retval := "

      if static
        f << "  #{capture}#{class_name} #{ooc_name}(#{arglist})"
      else
        f << "  duk pushThis()"
        f << "  __self := duk requireOoc(-1) as #{class_name}"
        f << "  #{capture}__self #{ooc_name}(#{arglist})"
      end

      if mvoid
        f << "  return 0"
      else
        f << push_something("__retval", mdef.returnTypeFqn)
        f << "  return 1"
      end
      f << "}"
      f.nl
    end

    def translate_field(f, fdef, cl, property_bindings)
      return unless supported_type?(fdef.varType)
      return if type_is_fun?(fdef.varType)
      static = fdef.modifiers.include? 'static'

      ooc_name = unmangle(fdef.name)
      mangled_name = fdef.name.gsub(/~/, '_')

      hasGetter = true
      hasSetter = true
      if fdef.propertyData
        hasGetter = fdef.propertyData.hasGetter
        hasSetter = fdef.propertyData.hasSetter
      end

      property_binding = Hashie::Mash.new(:name => mangled_name)

      #######################
      # Getter
      #######################
      
      if hasGetter
        property_binding.getter = "_duk_#{cl[1].fullName}_#{ooc_name}_getter"

        f << "#{property_binding.getter}: func (duk: DukContext) -> Int {"

        if static
          f << "  __self := #{cl[1].name}"
        else
          f << "  duk pushThis()"
          f << "  __self := duk requireOoc(-1) as #{cl[1].name}"
          f << "  duk pop()"
        end

        f << push_something("__self #{ooc_name}", fdef.varTypeFqn)
        f << "  return 1"

        f << "}"
      end

      #######################
      # Setter
      #######################
      
      if hasSetter
        property_binding.setter = "_duk_#{cl[1].fullName}_#{ooc_name}_setter"

        f << "#{property_binding.setter}: func (duk: DukContext) -> Int {"

        if static
          f << "  __self := #{cl[1].name}"
        else
          f << "  duk pushThis()"
          f << "  __self := duk requireOoc(-1) as #{cl[1].name}"
          f << "  duk pop()"
        end

        f << require_something(fdef.name, fdef.varTypeFqn)
        f << "  __self #{ooc_name} = #{fdef.name}"

        f << "  return 0"

        f << "}"
      end

      property_bindings << property_binding
    end

    def indent(tmp, level)
      tmp.split("\n").map { |x| ("  " * level) + x }.join("\n")
    end

    def require_something(lhs, type, level: 1, index: 0, mode: :declare)
      tmp = ""

      td = @registry.type_catalog[type]
      if td && compound_cover?(td)
        tmp << "#{lhs}: #{type_to_ooc(type)}\n"
        fields = td[1].members.select { |x| x[1].type == 'field' }
        tmp << "{ // #{type} {#{fields.map(&:first).join(', ')}}\n"
        tmp << "  duk requireObjectCoercible(#{index})\n"
        fields.each do |fd|
          tmp << "  duk getPropString(#{index}, \"#{fd[0]}\")\n"
          tmp << require_something("#{lhs} #{fd[0]}", fd[1].varTypeFqn, :index => -1, :mode => :assign) << "\n"
          tmp << "  duk pop()\n"
        end
        tmp << "}"
      else
        op = case mode
             when :declare
               ':='
             when :assign
               '='
             else
               raise "Unknown mode: #{mode}"
             end
        tmp << "#{lhs} #{op} duk require#{type_to_duk(type)}(#{index}) as #{type_to_ooc(type)}"
      end

      indent(tmp, level)
    end 

    def push_something(rhs, type, level: 1)
      tmp = ""
      td = @registry.type_catalog[type]
      if td && compound_cover?(td)
        fields = td[1].members.select { |x| x[1].type == 'field' }
        tmp << "{ // #{type} {#{fields.map(&:first).join(', ')}}\n"
        tmp << "  objIdx := duk pushObject()\n"

        fields.each do |fd|
          tmp << push_something("#{rhs} #{fd[0]}", fd[1].varTypeFqn) + "\n"
          tmp << "  duk putPropString(objIdx, \"#{fd[0]}\")\n"
        end

        tmp << "}"
      else
        duked = type_to_duk(type)
        if duked == "Ooc"
          tmp << "duk push#{duked}(#{rhs}, \"#{type}\")\n"
        else
          tmp << "duk push#{duked}(#{rhs})\n"
        end
      end

      indent(tmp, level)
    end

    def type_to_duk(type)
      case type
      when INT_TYPE_RE
        "Int"
      when NUM_TYPE_RE
        "Number"
      when FUN_TYPE_RE
        "ObjectCoercible"
      when /^pointer\(.*\)$/
        "Pointer"
      when /C?String/
        "String"
      when "Bool"
        "Boolean"
      else
        tokens = type.split('__')
        
        if tokens.length == 2
          td = @registry.type_catalog[type]
          if td && td[1].type == 'cover'
            if compound_cover?(td)
              fields = td[1].members.select { |x| x[1].type == 'field' }
              info "#{type}: cover from #{td[1].from} with fields #{fields.map(&:first).join(", ")}"
            end
          end

          type_path, type_name = tokens
          imp_path = type_path.gsub('_', '/')
          import_if_necessary(imp_path)
          type_to_duk(type_name)
        else
          "Ooc"
        end
      end
    end

    def translate_class(f, cl)
      class_name = cl[1].fullName

      parent_class = cl[1].extendsFullName
      if parent_class != "lang_types__Object"
        @inheritance_chains << [class_name, parent_class]
      end

      method_bindings = []
      property_bindings = []

      cl[1].members.each do |mb|
        next if (mb[0].start_with?('__')) || MEMBERS_BLACKLIST.include?(mb[0])

        case mb[1].type
        when 'method'
          translate_method(f, mb[1], cl[1].name, method_bindings)
        when 'field'
          translate_field(f, mb[1], cl, property_bindings)
        end
      end

      make_mimic(f, cl[0], class_name,
                 :methods => method_bindings,
                 :properties => property_bindings)
    end

    def translate_enum(f, en)
      short_name = en[0]
      enum_name = "#{@spec.path.gsub(/\//, '_')}__#{en[0]}"
      info "Enum name: #{enum_name}"

      field_bindings = []
      en[1].elements.each do |mb|
        name = mb[0]
        field_bindings << Hashie::Mash.new(
          :name => name,
          :value => "#{short_name} #{name}"
        )
      end

      make_mimic(f, short_name, enum_name,
                 :static_fields => field_bindings)
    end

    def make_mimic(f, short_name, type_name, methods: [], properties: [], static_fields: [])
      binder_name = "_bind_#{type_name}"
      @all_bindings << binder_name
      f << "#{binder_name}: func (duk: DukContext) {"
      f << "  objIdx := duk pushObject()"
      f.nl
      methods.each do |bin|
        f << "  duk pushCFunction(#{bin.wrapper}, #{bin.nargs})"
        f << "  duk putPropString(objIdx, \"#{bin.name}\")"
        f.nl
      end
      static_fields.each do |bin|
        f << "  duk pushInt((#{bin.value}) as Int)"
        f << "  duk putPropString(objIdx, \"#{bin.name}\")"
        f.nl
      end
      properties.each do |bin|
        f << "  {"
        f << "    propIdx := duk pushObject()"
        if bin.getter
          f << "    duk pushCFunction(#{bin.getter}, 0)"
          f << "    duk putPropString(propIdx, \"get\")"
        end
        if bin.setter
          f << "    duk pushCFunction(#{bin.setter}, 1)"
          f << "    duk putPropString(propIdx, \"set\")"
        end
        f << "    duk getGlobalString(\"Object\")"
        f << "    duk getPropString(-1, \"defineProperty\")"
        f << "    duk dup(objIdx)"
        f << "    duk pushString(\"#{bin.name}\")"
        f << "    duk dup(propIdx)"
        f << "    if (duk pcall(3) != 0) {"
        f << "      raise(\"Failed to define property #{bin.name}: \#{duk safeToString(-1)}\")"
        f << "    }"
        f << "    duk pop3() // discard return value, Object and property handler"
        f << "  }"
        f.nl
      end
      f << "  duk putGlobalString(\"#{type_name}\")"
      f << "  clazz := #{short_name}"
      f << "  DukContext putClass(clazz, \"#{type_name}\")"
      f << "}"
      f.nl
    end

  end
end

