
require 'json'
require 'hashie'

require 'collar/prelude'
require 'collar/fool'
require 'collar/translator'
require 'collar/type_scriptor'
require 'collar/logger'
require 'collar/registry'

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

      ext = Fool.new("#{@opts[:output]}/extensions.ooc")
      ext << AUTOGEN_NOTICE
      ext << PRELUDE
      ext.close

      f = Fool.new("#{@opts[:output]}/autobindings.ooc")

      f << AUTOGEN_NOTICE

      f << "//---- Universe deps start ----"
      f.write File.read(@universe).strip
      f.nl
      f << "//---- Universe deps end   ----"
      f.nl

      f << "use duktape"
      f << "import duk/tape, collar/extensions"
      
      all_specs = jsons.map do |path|
        Hashie::Mash.new(JSON.load(File.read(path)))
      end

      registry = Registry.new(@opts, @universe, all_specs)

      info "Binding #{registry.specs.length} specs...".yellow

      all_bindings = []
      inheritance_chains = []

      registry.specs.each do |spec|
        tr = Collar::Translator.new(@opts, spec, all_bindings, inheritance_chains, registry)
        tr.translate

        if @opts[:typescript]
          ts = Collar::TypeScriptor.new(@opts, spec, registry)
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

      make_packages!(registry) if @opts[:typescript]
    end

    private

    def make_packages!(registry)
      packages = {}
      registry.specs.each do |spec|
        path = spec.path.split("/").first
        next if registry.spec_paths.include?(path)

        packages[path] ||= []
        packages[path] << spec.path
      end
      info "Packages: #{packages.keys.join(", ")}"

      tspath = @opts[:typescript]
      tsdir = tspath.split("/").last

      packages.each do |name, components|
        f = Fool.new("#{tspath}/#{name}.ts")
        components.each do |comp|
          name = comp.split('/').drop(1).join('_')
          f << "export import #{name} = require(\"./#{comp}\");"
        end
        f.close
      end

      f = Fool.new("#{tspath}.ts")
      packages.each do |name, components|
        f << "export import #{name} = require(\"#{tsdir}/#{name}\")"
      end
      f.close
    end

    def get_jsons
      if File.exist?(TMP_DIR)
        info "JSONs already there :) Remove #{TMP_DIR} to force refresh.".yellow
      else
        info "Generating JSONs with rock...".yellow
        cmd = %Q{rock -q #{@universe} --backend=json --outpath=#{TMP_DIR}}
        debug "> #{cmd}"
        unless system(cmd)
          bail "Error launching rock."
        end
      end

      Dir["#{TMP_DIR}/**/*.json"]
    end

  end
end

