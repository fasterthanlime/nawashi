
require 'colorize'

module Nawashi
  module Logger
    DEBUG = ENV['NAWASHI_DEBUG']

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

