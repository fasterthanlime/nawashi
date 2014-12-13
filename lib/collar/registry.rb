
require 'versionomy'
require 'set'

require 'collar/logger'

module Collar
  class Registry
    include Collar::Logger

    attr_reader :specs
    attr_reader :all_specs
    attr_reader :spec_paths

    MIN_JSON_VERSION = Versionomy.parse("1.2.1")

    def initialize(opts, universe, all_specs)
      @opts = opts
      @universe = universe
      @all_specs = all_specs

      @specs = @all_specs.select { |spec| spec_chosen?(spec) }
      @spec_paths = Set.new(specs.map(&:path))
    end

    private

    def spec_chosen?(spec)
      return false if "#{spec.path}.ooc" == @universe
      return false unless @opts[:packages].any? { |x| spec.path.start_with?(x) }
      return false if @opts[:'exclude-packages'].any? { |x| spec.path.start_with?(x) }

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

