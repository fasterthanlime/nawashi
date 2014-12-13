
require 'json'
require 'hashie'
require 'versionomy'
require 'set'

require 'collar/prelude'
require 'collar/fool'
require 'collar/translator'
require 'collar/type_scriptor'
require 'collar/logger'

module Collar
  class Driver
    include Collar::Prelude
    include Collar::Logger

    TMP_DIR = '.collar-cache'

    def initialize(opts, universe)
      @opts = opts
      @universe = universe

      unless File.exist?(@universe)
        bail "Universe #{@universe} does not exist."
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
      specs = []

      min_version = Versionomy.parse("1.2.0")
      
      jsons.each do |path|
        spec = Hashie::Mash.new(JSON.load(File.read(path)))
        next if "#{spec.path}.ooc" == @universe
        next unless @opts[:packages].any? { |x| spec.path.start_with?(x) }
        next if @opts[:'exclude-packages'].any? { |x| spec.path.start_with?(x) }

        if spec.version.nil?
          bail "#{path}: version-less JSON file. Update rock and try again.".red
        end

        version = Versionomy.parse(spec.version)
        if version < min_version
          bail "#{path}: v#{version} but collar needs >= v#{min_version}".red
        end

        specs << spec
      end

      spec_paths = Set.new(specs.map(&:path))

      info "Binding #{specs.length} specs...".yellow

      specs.each do |spec|
        tr = Collar::Translator.new(@opts, spec, all_bindings, inheritance_chains)
        tr.translate

        if @opts[:typescript]
          ts = Collar::TypeScriptor.new(@opts, spec, spec_paths)
          ts.typescriptize
        end

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
      if File.exist?(TMP_DIR)
        info "JSONs already there :) Remove #{TMP_DIR} to force refresh.".yellow
      else
        info "Generating JSONs with rock...".yellow
        cmd = %Q{rock -q #{@universe} --backend=json --outpath=#{TMP_DIR}}
        unless system(cmd)
          bail "Error launching rock."
        end
      end

      Dir["#{TMP_DIR}/**/*.json"]
    end

  end
end

