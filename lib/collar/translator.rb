
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

    def initialize(opts, spec, all_bindings, inheritance_chains, spec_paths)
      @opts = opts
      @spec = spec
      @all_bindings = all_bindings
      @inheritance_chains = inheritance_chains
      @spec_paths = spec_paths
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

      classes = @spec.entities.select do |en|
        en[1].type == "class"
      end

      classes.each do |cl|
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
            # TODO: handle properties :)
            next unless mb[1].propertyData.nil?
            translate_field(f, mb[1], cl, property_bindings)
          end
        end

        binder_name = "_bind_#{class_name}"
        @all_bindings << binder_name
        f << "#{binder_name}: func (duk: DukContext) {"
        f << "  objIdx := duk pushObject()"
        f.nl
        method_bindings.each do |bin|
          f << "  duk pushCFunction(#{bin.wrapper}, #{bin.nargs})"
          f << "  duk putPropString(objIdx, \"#{bin.name}\")"
          f.nl
        end
        property_bindings.each do |bin|
          f << "  {"
          f << "    propIdx := duk pushObject()"
          f << "    duk pushCFunction(#{bin.getter}, 0)"
          f << "    duk putPropString(propIdx, \"get\")"
          f << "    duk pushCFunction(#{bin.setter}, 1)"
          f << "    duk putPropString(propIdx, \"set\")"
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
        f << "  duk putGlobalString(\"#{class_name}\")"
        f << "  clazz := #{cl[0]}"
        f << "  DUK_PROTO_CACHE put(clazz, \"#{class_name}\")"
        f << "}"
        f.nl
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
        puts "Maybe import #{imp}"
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

          closure_arg_types = fun_type_arguments(arg[1])
          closure_arg_list = []
          closure_arg_types.each_with_index do |closure_arg_type, j|
            closure_arg_list << "__arg#{j}: #{type_to_ooc(closure_arg_type)}"
          end

          f.nl
          f << "  closureID := DukContext freshID()"
          f << "  duk dup(#{i})"
          f << "  duk putGlobalString(closureID)"
          f.nl
          f << "  #{arg[0]} := func (#{closure_arg_list.join(", ")}) {"
          f << "    duk getGlobalString(closureID)"
          closure_arg_types.each_with_index do |closure_arg_type, j|
          f << "    duk push#{type_to_duk(closure_arg_type)}(__arg#{j})"
          end
          f << "    if(duk pcall(#{closure_arg_list.length}) != 0) {"
          f << "      raise(\"Error in closure: \" + duk safeToString(-1))"
          f << "    }"
          f << "    duk pop()"
          f << "  }"
          f.nl
        else
          args << arg[0]
          puts "Arg full type: #{arg[3]}"
          f << "  #{arg[0]} := duk require#{type_to_duk(arg[3])}(#{i}) as #{type_to_ooc(arg[1])}"
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
        f << "  duk push#{type_to_duk(mdef.returnTypeFqn)}(__retval)"
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

      property_binding = Hashie::Mash.new(
        :getter => "_duk_#{cl[1].fullName}_#{ooc_name}_getter",
        :setter => "_duk_#{cl[1].fullName}_#{ooc_name}_setter",
        :name => mangled_name,
      )
      property_bindings << property_binding

      #######################
      # Getter
      #######################
      
      f << "#{property_binding.getter}: func (duk: DukContext) -> Int {"

      if static
        f << "  __self := #{cl[1].name}"
      else
        f << "  duk pushThis()"
        f << "  __self := duk requireOoc(-1) as #{cl[1].name}"
        f << "  duk pop()"
      end

      f << "  duk push#{type_to_duk(fdef.varTypeFqn)}(__self #{ooc_name})"
      f << "  return 1"

      f << "}"

      #######################
      # Setter
      #######################
      
      f << "#{property_binding.setter}: func (duk: DukContext) -> Int {"

      if static
        f << "  __self := #{cl[1].name}"
      else
        f << "  duk pushThis()"
        f << "  __self := duk requireOoc(-1) as #{cl[1].name}"
        f << "  duk pop()"
      end

      f << "  #{fdef.name} := duk require#{type_to_duk(fdef.varType)}(0) as #{type_to_ooc(fdef.varType)}"
      f << "  __self #{ooc_name} = #{fdef.name}"

      f << "  return 0"

      f << "}"
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
          type_path, type_name = tokens
          imp_path = type_path.gsub('_', '/')
          import_if_necessary(imp_path)
          type_to_duk(type_name)
        else
          "Ooc"
        end
      end
    end


  end
end

