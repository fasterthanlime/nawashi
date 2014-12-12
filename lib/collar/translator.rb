
require 'json'
require 'hashie'

require 'collar/prelude'
require 'collar/types'

module Collar
  class Translator
    include Collar::Prelude
    include Collar::Types

    TMP_DIR = '.collar-cache'
    UNIVERSE = 'source/lestac/universe.ooc'
    MEMBERS_BLACKLIST = %w(init)

    def initialize(opts, universe)
      @opts = opts
      @universe = universe

      unless File.exist?(@universe)
        puts "Universe #{@universe} does not exist."
      end
    end

    def translate
      puts "Translator#translate: stub!"
      def unmangle(name)
        name.gsub(/__bang(~.+)?/, '!').gsub(/__quest(~.+)?/, '?')
      end

      puts "Launching rock..."

      unless File.exist?(TMP_DIR)
        unless system %Q{rock -vv #{@universe} --backend=json --outpath=#{TMP_DIR}}
          puts "Error launching rock."
          exit 1
        end
      end
      puts "Alright, we got our nifty bindings :)"

      jsons = Dir["#{TMP_DIR}/**/*.json"]

      all_bindings = []

      File.open('source/lestac/autobindings.ooc', 'w') do |f|
        f << "\n"
        f << "//------------- Universe deps start \n"
        f << File.read(@universe).strip
        f << "\n"
        f << "//------------- Universe deps end \n\n"

        f << PRELUDE

        jsons.select { |x| x.include? "math" }.each do |path|
          obj = Hashie::Mash.new(JSON.load(File.read(path)))
          puts "[Module] #{obj.entities[0][1].name}"

          f << "import #{obj.path}\n\n"

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

              f << "#{class_binding.wrapper}: func (duk: DukContext) -> Int {\n"

              args = []

              mdef.arguments.each_with_index do |arg, i|
                args << arg[0]
                f << "  #{arg[0]} := duk require#{type_to_duk(arg[1])}(#{i}) as #{type_to_ooc(arg[1])}\n"
              end
              f << "\n"

              arglist = args.join(", ")
              mvoid = mdef.returnType.nil?
              capture = mvoid ? "" : "__retval := "

              if static
                f << "  // static\n"
                f << "  duk pushThis()\n"
                f << "  #{capture}#{cl[1].name} #{ooc_name}(#{arglist})\n"
              else
                f << "  // non-static\n"
                f << "  duk pushThis()\n"
                f << "  __self := duk requireOoc(-1) as #{cl[1].name}\n"
                f << "  #{capture}__self #{ooc_name}(#{arglist})\n"
              end

              if mvoid
                f << "  0\n"
              else
                # TODO: return that stuff.
                f << "  duk push#{type_to_duk(mdef.returnType)}(__retval)\n"
                f << "  1\n"
              end
              f << "}\n\n"
            end

            binder_name = "_bind_#{class_name}"
            all_bindings << binder_name
            f << "#{binder_name}: func (duk: DukContext) {\n"
            f << "  objIdx := duk pushObject()\n"
            f << "\n"
            class_bindings.each do |bin|
              f << "  duk pushCFunction(#{bin.wrapper}, #{bin.nargs})\n"
              f << "  duk putPropString(objIdx, \"#{bin.name}\")\n\n"
            end
            f << "  duk putGlobalString(\"#{class_name}\")\n"
            f << "  clazz := #{cl[0]}\n"
            f << "  DUK_PROTO_CACHE put(clazz, \"#{class_name}\")\n"
            f << "}\n\n"
          end

          break
        end

        f << "_bind_all: func (duk: DukContext) {\n"
        all_bindings.each do |bi|
          f << "  #{bi}(duk);\n"
        end
        f << "}\n"
      end

    end
  end
end

