
require 'slop'
require 'collar'

module Collar
  class CLI
    def initialize
      opts = Slop.parse(:strict => true, :help => true) do
        banner 'Usage: collar [options] [universefile]'

        on 'o=', 'output', 'Output directory', :default => "source/collar/"
        on 'V', 'version', 'Print version and exit'
      end

      if opts.version?
        puts "Collar, version #{Collar::VERSION}"
        exit 0
      end

      tr = Collar::Translator.new(opts)
      tr.translate
      puts "Success!"
    end
  end
end

