
require 'colorize'

module Collar
  module Logger
    def bail(msg)
      puts "☂ #{msg}".red
      exit 1
    end

    def info(msg)
      puts "★ #{msg}".yellow
    end
    
    def oyea(msg)
      puts "☃ #{msg}".green
    end
  end
end

