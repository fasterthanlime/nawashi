
require 'fileutils'

module Collar
  class Fool
    def initialize(path)
      @path = path

      dirname = File.dirname(@path)
      unless File.directory?(dirname)
        FileUtils.mkdir_p(dirname)
      end

      @file = File.open(@path, 'w')
    end

    def close
      @file.close
    end

    def << (x)
      @file << "#{x}\n"
    end

    def nl
      self << ""
    end

    def write (x)
      @file << x
    end
  end
end

