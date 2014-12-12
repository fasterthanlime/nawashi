
require 'json'
require 'hashie'

require 'collar/prelude'
require 'collar/fool'
require 'collar/translator'

module Collar
  class Driver
    include Collar::Prelude

    TMP_DIR = '.collar-cache'

    def initialize(opts, universe)
      @opts = opts
      @universe = universe

      unless File.exist?(@universe)
        puts "Universe #{@universe} does not exist."
      end
    end

    def doall
      jsons = get_jsons

      ext = Collar::Fool.new("#{@opts[:output]}/extensions.ooc")
      ext << AUTOGEN_NOTICE
      ext << PRELUDE
      ext.close

      f = Collar::Fool.new("#{@opts[:output]}/autobindings.ooc")

      f << AUTOGEN_NOTICE

      f << "//---- Universe deps start ----"
      f.write File.read(@universe).strip
      f.nl
      f << "//---- Universe deps end   ----"
      f.nl

      f << "use duktape"
      f << "import duk/tape, collar/extensions"

      all_bindings = []
      inheritance_chains = []

      jsons.each do |path|
        spec = Hashie::Mash.new(JSON.load(File.read(path)))
        next if "#{spec.path}.ooc" == @universe
        next unless @opts[:packages].any? { |x| spec.path.start_with?(x) }
        next if @opts[:'exclude-packages'].any? { |x| spec.path.start_with?(x) }

        tr = Collar::Translator.new(@opts, spec, all_bindings, inheritance_chains)
        tr.translate

        f << "import #{tr.import_path}"
      end

      f.nl
      f << "_bind_all: func (duk: DukContext) {"

      f.nl
      f << "  // All bindings"

      all_bindings.each do |bi|
        f << "  #{bi}(duk);"
      end

      f.nl
      f << "  // Inheritance chains"

      inheritance_chains.each do |chain|
        child, parent = chain
        f << "  duk setInheritance(\"#{child}\", \"#{parent}\")"
      end

      f << "}"
      f.close

    end

    private

    def get_jsons
      unless File.exist?(TMP_DIR)
        puts "Launching rock..."
        cmd = %Q{rock -q #{@universe} --backend=json --outpath=#{TMP_DIR}}
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

