
require 'collar/prelude'
require 'collar/types'
require 'collar/mangler'
require 'collar/fool'

module Collar
  class Translator
    include Collar::Prelude
    include Collar::Types
    include Collar::Mangler

    MEMBERS_BLACKLIST = %w(init)

    attr_reader :import_path

    def initialize(opts, spec, all_bindings)
      @opts = opts
      @spec = spec
      @all_bindings = all_bindings
      @import_path = "duk/#{@spec.path}"
    end

    def translate
      f = Fool.new("#{@opts[:output]}/#{@import_path}.ooc")

      puts "[Module] #{@spec.path}"

      f << AUTOGEN_NOTICE
      f << "import duk/tape, collar/extensions"
      f << "import #{@spec.path}"
      f.nl

      classes = @spec.entities.select do |en|
        en[1].type == "class"
      end

      classes.each do |cl|
        class_name = cl[1].fullName
        puts "[Class] #{class_name}"

        class_bindings = []

        cl[1].members.each do |mb|
          next if (mb[0].start_with?('__')) || MEMBERS_BLACKLIST.include?(mb[0])

          case mb[1].type
          when 'method'
            translate_method(f, mb[1], cl[1].name, class_bindings)
          when 'field'
            # TODO: handle properties :)
            next unless mb[1].propertyData.nil?
            translate_field(f, mb[1], cl, class_bindings)
          end
        end

        binder_name = "_bind_#{class_name}"
        @all_bindings << binder_name
        f << "#{binder_name}: func (duk: DukContext) {"
        f << "  objIdx := duk pushObject()"
        f.nl
        class_bindings.each do |bin|
          f << "  duk pushCFunction(#{bin.wrapper}, #{bin.nargs})"
          f << "  duk putPropString(objIdx, \"#{bin.name}\")"
          f.nl
        end
        f << "  duk putGlobalString(\"#{class_name}\")"
        f << "  clazz := #{cl[0]}"
        f << "  DUK_PROTO_CACHE put(clazz, \"#{class_name}\")"
        f << "}"
        f.nl
      end

      f.close
    end

    private

    def translate_method(f, mdef, class_name, class_bindings)
      return if mdef.arguments.any? { |arg| arg[1] == '...' }

      ooc_name = unmangle(mdef.name)
      mangled_name = mdef.name.gsub(/~/, '_')
      static = mdef.modifiers.include? 'static'

      class_binding = Hashie::Mash.new(
        :wrapper => "_duk_#{mdef.fullName}",
        :nargs => mdef.arguments.length,
        :name => mangled_name,
      )
      class_bindings << class_binding

      f << "#{class_binding.wrapper}: func (duk: DukContext) -> Int {"

      args = []

      mdef.arguments.each_with_index do |arg, i|
        args << arg[0]
        f << "  #{arg[0]} := duk require#{type_to_duk(arg[1])}(#{i}) as #{type_to_ooc(arg[1])}"
      end
      f.nl

      arglist = args.join(", ")
      mvoid = mdef.returnType.nil?
      capture = mvoid ? "" : "__retval := "

      if static
        f << "  duk pushThis()"
        f << "  #{capture}#{class_name} #{ooc_name}(#{arglist})"
      else
        f << "  duk pushThis()"
        f << "  __self := duk requireOoc(-1) as #{class_name}"
        f << "  #{capture}__self #{ooc_name}(#{arglist})"
      end

      if mvoid
        f << "  0"
      else
        f << "  duk push#{type_to_duk(mdef.returnType)}(__retval)"
        f << "  1"
      end
      f << "}"
      f.nl
    end

    def translate_field(f, fdef, cl, class_bindings)
      # what of ooc arrays? :|
      return if fdef.varType.start_with? 'array('

      ooc_name = unmangle(fdef.name)
      mangled_name = fdef.name.gsub(/~/, '_')
      static = fdef.modifiers.include? 'static'

      class_binding = Hashie::Mash.new(
        :wrapper => "_duk_#{cl[1].fullName}_#{ooc_name}",
        :nargs => 1,
        :name => mangled_name,
      )
      class_bindings << class_binding

      f << "#{class_binding.wrapper}: func (duk: DukContext) -> Int {"

      f << "  duk pushThis()"
      f << "  __self := duk requireOoc(-1) as #{cl[1].name}"
      f << "  duk pop()"

      f << "  if (!duk isUndefined(0)) {"
      f << "    #{fdef.name} := duk require#{type_to_duk(fdef.varType)}(0) as #{type_to_ooc(fdef.varType)}"
      f << "    __self #{ooc_name} = #{fdef.name}"
      f << "  }"
      f.nl

      f << "  duk push#{type_to_duk(fdef.varType)}(__self #{ooc_name})"
      f << "  1"

      f << "}"

    end

  end
end

