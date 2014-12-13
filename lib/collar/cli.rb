
require 'slop'
require 'collar'

module Collar
  class CLI
    def initialize
      opts = Slop.parse(:strict => true, :help => true) do
        banner 'Usage: collar [options] [universefile]'

        on 'o=', 'output', 'Output directory', :default => "source/collar/"
        on 't=', 'typescript', 'Typescript output directory'
        on 'p=', 'packages', 'Whitelisted packages', :as => Array, :default => []
        on 'x=', 'exclude-packages', 'Blacklisted packages', :as => Array, :default => []
        on 'V', 'version', 'Print version and exit'
      end

      if opts.version?
        puts "Collar, version #{Collar::VERSION}"
        exit 0
      end

      if ARGV.length < 1
        puts "collar: needs universe source path"
        exit 1
      end

      universe = ARGV[0]

      tr = Collar::Driver.new(opts, universe)
      tr.doall
      puts "Success!"
    end
  end
end

