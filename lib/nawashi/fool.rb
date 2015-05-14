
require 'fileutils'

module Nawashi
  class Fool
    def initialize(path)
      @path = path

      dirname = File.dirname(@path)
      unless File.directory?(dirname)
        FileUtils.mkdir_p(dirname)
      end

      @buffer = ""
    end

    def close
      File.open(@path, 'w') do |f|
        f.write(@buffer)
      end
    end

    def << (x)
      @buffer << "#{x}"
      @buffer << "\n"
    end

    def nl
      @buffer << "\n"
    end

    def write (x)
      @buffer << x
    end

    def prepend (x)
      @buffer.prepend(x)
    end
  end
end

