
require 'colorize'

module Collar
  module Logger
    DEBUG = ENV['COLLAR_DEBUG']

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

    def debug(msg)
      puts "♥ #{msg}".blue if DEBUG
    end
  end
end

