
require 'json'
require 'hashie'

require 'collar/prelude'
require 'collar/types'
require 'collar/mangler'
require 'collar/fool'

module Collar
  class Driver
    include Collar::Prelude
    include Collar::Types
    include Collar::Mangler

    TMP_DIR = '.collar-cache'
    MEMBERS_BLACKLIST = %w(init)

    def initialize(opts, universe)
      @opts = opts
      @universe = universe

      unless File.exist?(@universe)
        puts "Universe #{@universe} does not exist."
      end
    end

    def doall
      jsons = get_jsons

      all_bindings = []

      f = Collar::Fool.new("#{@opts[:output]}/autobindings.ooc")
      f.nl
      f << "//------------- Universe deps start"
      f.write File.read(@universe).strip
      f.nl
      f << "//------------- Universe deps end"
      f.nl

      f << PRELUDE

      jsons.select { |x| x.include? "math" }.each do |path|
        obj = Hashie::Mash.new(JSON.load(File.read(path)))
        puts "[Module] #{obj.entities[0][1].name}"

        f << "import #{obj.path}"
        f.nl

        classes = obj.entities.select do |en|
          en[1].type == "class"
        end

        classes.each do |cl|
          class_name = cl[1].fullName
          puts "[Class] #{class_name}"

          class_bindings = []

          cl[1].members.each do |mb|
            next if (mb[0].start_with?('__')) || MEMBERS_BLACKLIST.include?(mb[0])
            next unless (mb[1].type == 'method')

            mdef = mb[1]

            ooc_name = unmangle(mdef.name)
            mangled_name = mdef.name.gsub(/~/, '_')
            puts "[#{mdef.modifiers.join(" ")} method] #{mdef.name} -> #{mangled_name}"
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
              f << "  #{capture}#{cl[1].name} #{ooc_name}(#{arglist})"
            else
              f << "  duk pushThis()"
              f << "  __self := duk requireOoc(-1) as #{cl[1].name}"
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

          binder_name = "_bind_#{class_name}"
          all_bindings << binder_name
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

        break
      end

      f << "_bind_all: func (duk: DukContext) {"
      all_bindings.each do |bi|
        f << "  #{bi}(duk);"
      end
      f << "}"
      f.close

    end

    private

    def get_jsons
      unless File.exist?(TMP_DIR)
        puts "Launching rock..."
        cmd = %Q{rock -vv #{@universe} --backend=json --outpath=#{TMP_DIR}}
        unless system(cmd)
          puts "Error launching rock."
          exit 1
        end
      end
      puts "Alright, we got our nifty bindings :)"

      Dir["#{TMP_DIR}/**/*.json"]
    end

  end
end

