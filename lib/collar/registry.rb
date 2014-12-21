
require 'versionomy'
require 'set'

require 'collar/logger'

module Collar
  class Registry
    include Collar::Logger

    attr_reader :specs
    attr_reader :all_specs
    attr_reader :spec_paths
    attr_reader :type_catalog

    MIN_JSON_VERSION = Versionomy.parse("1.2.2")

    def initialize(opts, universe, all_specs)
      @opts = opts
      @universe = universe
      @all_specs = all_specs

      @specs = @all_specs.select { |spec| spec_chosen?(spec) }
      @spec_paths = Set.new(specs.map(&:path))
      @type_catalog = {}
      catalog_types!
    end

    private

    def catalog_types!
      all_specs.each do |spec|
        spec.entities.each do |en|
          if typelike?(en)
            full_name = "#{spec.path.gsub('/', '_')}__#{en[1].name}"
            @type_catalog[full_name] = en
          end
        end
      end
      info "Found #{@type_catalog.length} types in #{all_specs.length} specs."
    end

    TYPELIKES = %w(class cover enum)

    def typelike?(en)
      TYPELIKES.include?(en[1].type)
    end

    def spec_chosen?(spec)
      if "#{spec.path}.ooc" == @universe
        return false
      end

      unless @opts[:packages].any? { |x| spec.path.start_with?(x) }
        debug "#{spec.path} skipped (not in --packages)"
        return false 
      end

      @opts[:'exclude-packages'].each do |excl_pattern|
        if spec.path.start_with?(excl_pattern)
          debug "#{spec.path} skipped (matches #{excl_pattern})"
          return false
        end
      end

      if spec.version.nil?
        bail "#{path}: version-less JSON file. Update rock and try again.".red
      end

      version = Versionomy.parse(spec.version)
      if version < MIN_JSON_VERSION
        bail "#{path}: v#{version} but collar needs >= v#{MIN_JSON_VERSION}".red
      end

      true
    end
  end
end

