
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
        :wrapper => "_duk_#{mdef.nameFqn}",
        :nargs => mdef.arguments.length,
        :name => mangled_name,
      )
      method_bindings << method_binding

      f << "#{method_binding.wrapper}: func (duk: DukContext) -> Int {"

      args = []
      raw = mdef.name =~ /~rawduk$/

      if raw
        if mdef.arguments.size != 1
          raise "Too many arguments for #{mdef.name} in #{class_name}"
        end
        _arg = mdef.arguments[0]

        if _arg[3] != "duk_tape__DukContext"
          raise "Wrong arg type for #{mdef.name} in #{class_name}"
        end

        if mdef.returnType != "Int"
          raise "Wrong return type for #{mdef.name} in #{class_name}"
        end

        args << "duk"
      else
        mdef.arguments.each_with_index do |arg, i|
          args << arg[0]
          f << require_something(arg[0], arg[3], :index => i)
        end
        f.nl
      end

      arglist = args.join(", ")
      mvoid = mdef.returnType.nil? || raw
      capture = mvoid ? "" : "__retval := "

      if static
        f << "  #{capture}#{class_name} #{ooc_name}(#{arglist})"
      else
        f << "  duk pushThis()"
        f << "  __self := duk requireOoc(-1) as #{class_name}"
        f << "  #{capture}__self #{ooc_name}(#{arglist})"
      end

      unless raw
        if mvoid
          f << "  return 0"
        else
          f << push_something("__retval", mdef.returnTypeFqn)
          f << "  return 1"
        end
      end
      f << "}"
      f.nl
    end

    def translate_field(f, fdef, cl, property_bindings)
      return unless supported_type?(fdef.varType)
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
      
      # No getters for closures.
      if hasGetter && !type_is_fun?(fdef.varTypeFqn)
        property_binding.getter = "_duk_#{cl[1].nameFqn}_#{ooc_name}_getter"

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
        property_binding.setter = "_duk_#{cl[1].nameFqn}_#{ooc_name}_setter"

        f << "#{property_binding.setter}: func (duk: DukContext) -> Int {"

        if static
          f << "  __self := #{cl[1].name}"
        else
          f << "  duk pushThis()"
          f << "  __self := duk requireOoc(-1) as #{cl[1].name}"
          f << "  duk pop()"
        end

        f << require_something(fdef.name, fdef.varTypeFqn)
        if type_is_fun?(fdef.varTypeFqn)
          # closures require special handling :((
          f << "  __self #{ooc_name} = #{fdef.name} as Func"
        else
          f << "  __self #{ooc_name} = #{fdef.name}"
        end

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
      elsif type_is_fun?(type)
        tmp << "\n"
        tmp << "duk requireObjectCoercible(#{index})\n"

        fun_type = fun_type_parse(type)
        closure_arg_types = fun_type.arguments
        closure_arg_list = []
        closure_arg_types.each_with_index do |closure_arg_type, j|
          closure_arg_list << "__arg#{j}: #{type_to_ooc(closure_arg_type)}"
        end

        closureID = "#{lhs}ClosureID"

        tmp << "\n"
        tmp << "#{closureID} := DukContext freshID()\n"
        tmp << "duk dup(#{index})\n"
        tmp << "duk putGlobalString(#{closureID})\n"
        tmp << "\n"
        ret = if fun_type.return
                "-> #{type_to_ooc(fun_type.return)}"
              else
                ""
              end
        tmp << "#{lhs} := func (#{closure_arg_list.join(", ")}) #{ret} {\n"
        tmp << "  duk getGlobalString(#{closureID})\n"
        closure_arg_types.each_with_index do |closure_arg_type, j|
          tmp << push_something("__arg#{j}", closure_arg_type, :level => level)
          tmp << "\n"
        end
        tmp << "  if(duk pcall(#{closure_arg_list.length}) != 0) { duk raise!() }\n"
        if fun_type.return
          tmp << require_something("__retval", fun_type.return, :level => 1, :index => -1)
          tmp << "\n"
        end
        tmp << "  duk pop()\n"
        if fun_type.return
          tmp << "  return __retval\n"
        end
        tmp << "}\n"
      elsif type_is_ptr?(type)
        inner = ptr_type_parse(type)
        tmp << "#{lhs}: #{type_to_ooc(inner)}*\n"
        tmp << "{ // array of #{inner}\n"
        tmp << "  duk requireObjectCoercible(#{index})\n"
        tmp << "  duk getPropString(#{index}, \"length\")\n"
        tmp << "  __len := duk requireInt(-1) as Int\n"
        tmp << "  duk pop() // pop length\n"
        tmp << "  #{lhs} = gc_malloc(__len * (#{type_to_ooc(inner)} size))\n"
        tmp << "  for (__i in 0..__len) {\n"
        tmp << "    duk getPropIndex(#{index}, __i)\n"
        tmp << require_something("__elm", inner, :level => 2, :index => -1)
        tmp << "\n"
        tmp << "    #{lhs}[__i] = __elm\n"
        tmp << "    duk pop() // pop elm\n"
        tmp << "  }\n"
        tmp << "}\n"
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
        case duked
        when 'Ooc'
          # Pass class name for reverse lookup
          tmp << "duk push#{duked}(#{rhs}, \"#{type}\")\n"
        when 'Int'
          # Enums might need casting to int
          tmp << "duk push#{duked}(#{rhs} as Int)\n"
        else
          # Should work out of the box
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
          if td && td[1].type == 'enum'
            return "Int"
          end

          if td && td[1].type == 'cover'
            if td[1].fromFqn
              under = type_to_duk(td[1].fromFqn)
              if under != "Ooc"
                # found primitive cover! use that :)
                return under
              end
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
      class_name = cl[1].nameFqn

      parent_class = cl[1].extendsFqn
      if parent_class != "lang_types__Object"
        @inheritance_chains << [class_name, parent_class]
      end

      method_bindings = []
      property_bindings = []

      generic_types = cl[1].genericTypes

      cl[1].members.each do |mb|
        next if (mb[0].start_with?('__')) || MEMBERS_BLACKLIST.include?(mb[0])

        case mb[1].type
        when 'method'
          next if method_has_generics?(generic_types, mb[1])
          translate_method(f, mb[1], cl[1].name, method_bindings)
        when 'field'
          next if field_has_generics?(generic_types, mb[1])
          translate_field(f, mb[1], cl, property_bindings)
        end
      end

      make_mimic(f, cl[0], class_name,
                 :methods => method_bindings,
                 :properties => property_bindings)
    end

    def method_has_generics?(generic_types, mdef)
      return true unless mdef.genericTypes.empty?
      return true if generic_types.include?(mdef.returnType)
      return true if mdef.arguments.any? do |arg|
        return true if generic_types.include?(arg[1])
        if type_is_fun?(arg[1])
          fun_type = fun_type_parse(arg[1])
          return true if fun_type.return && generic_types.include?(fun_type.return)
          return true if fun_type.arguments.any? { |iarg| generic_types.include?(iarg) }
        end
        false
      end
      false
    end

    def field_has_generics?(generic_types, fdef)
      type = fdef.varTypeFqn
      if type_is_fun?(type)
        fun_type = fun_type_parse(type)
        # bit of a peculiar case, but generic types in Func types end up as "any"
        # in this case it seems.
        return true if fun_type.return == "any"
        return true if fun_type.arguments.include?("any")
      end
      if type_is_ptr?(type)
        ptr_type = ptr_type_parse(type)
        return true if generic_types.include?(ptr_type)
        return true if ptr_type == "any"
      end
      false
    end

    def translate_enum(f, en)
      short_name = en[0]
      enum_name = "#{@spec.path.gsub(/\//, '_')}__#{en[0]}"

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
      end
      static_fields.each do |bin|
        f << "  duk pushInt((#{bin.value}) as Int)"
        f << "  duk putPropString(objIdx, \"#{bin.name}\")"
      end
      properties.each do |bin|
        f << "  duk pushString(\"#{bin.name}\")"
        flags = ""
        if bin.getter
          f << "  duk pushCFunction(#{bin.getter}, 0)"
          flags << "| PropFlags HAVE_GETTER "
        end
        if bin.setter
          f << "  duk pushCFunction(#{bin.setter}, 1)"
          flags << "| PropFlags HAVE_SETTER "
        end
        f << "  duk defProp(objIdx, 0 #{flags})"
      end
      f << "  duk putGlobalString(\"#{type_name}\")"
      f << "  clazz := #{short_name}"
      f << "  DukContext putClass(clazz, \"#{type_name}\")"
      f << "}"
      f.nl
    end

  end
end

