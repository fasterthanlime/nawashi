
require 'json'
require 'hashie'

require 'nawashi/prelude'
require 'nawashi/fool'
require 'nawashi/translator'
require 'nawashi/type_scriptor'
require 'nawashi/logger'
require 'nawashi/registry'

module Nawashi
  class Driver
    include Nawashi::Prelude
    include Nawashi::Logger

    TMP_DIR = '.nawashi-cache'

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
      ext << "use nawashi"
      ext << "import nawashi"
      ext.close

      f = Fool.new("#{@opts[:output]}/autobindings.ooc")
      f << AUTOGEN_NOTICE

      f << "//---- Universe deps start ----"
      f.write File.read(@universe).strip
      f.nl
      f << "//---- Universe deps end   ----"
      f.nl

      f << "use duktape"
      f << "import duk/tape, nawashi/extensions"
      
      all_specs = jsons.map do |path|
        Hashie::Mash.new(JSON.load(File.read(path)))
      end

      registry = Registry.new(@opts, @universe, all_specs)

      info "Binding #{registry.specs.length} specs...".yellow

      all_bindings = []
      inheritance_chains = []

      registry.specs.each do |spec|
        tr = Nawashi::Translator.new(@opts, spec, all_bindings, inheritance_chains, registry)
        tr.translate

        if @opts[:typescript]
          ts = Nawashi::TypeScriptor.new(@opts, spec, registry)
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
      toplevels = Set.new()
      packages = {}
      registry.specs.each do |spec|
        path = spec.path.split("/").first
        toplevels << path
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
      toplevels.each do |name|
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

