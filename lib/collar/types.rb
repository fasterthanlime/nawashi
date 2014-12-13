
require 'hashie'

module Collar
  module Types
    INT_TYPE_RE = /^U?(Int|Short|Long)(8|16|32|64|128)?$/
    NUM_TYPE_RE = /^(Cp)?(Float|Double)(32|64|128)?$/
    FUN_TYPE_RE = /^Func\(.*\)$/

    def type_is_fun?(type)
      type =~ FUN_TYPE_RE
    end

    FUN_ABOMINATION_RE = %r{
    (?<result>
     (?<kind>arguments|return)
     \(
     (?<args>
      (?<type>
       (Func|arguments|return|pointer|array)
       \(\g<type>(?:,\s\g<type>)*\)
       |
       ([^\(]*?)
      )
      (,\s\g<type>)*
     )
     \)
    )
    }x

    def fun_type_parse(type)
      inner = /^Func\((.*)\)$/.match(type)
      raise "Not a func type: #{type}" unless inner
      hash = Hashie::Mash.new(Hash[inner[1].scan(FUN_ABOMINATION_RE).map { |x| x[1..2] }])
      if hash.arguments
        hash.arguments = hash.arguments.split(",").map(&:strip)
      else
        hash.arguments = []
      end
      puts "Fun type: #{hash.to_h.to_s}"
      hash
    end

    def type_to_ooc(type)
      type
        .gsub(/^(.+)__(.+)$/) { type_to_ooc($2) }
        .gsub(/pointer\((.+)\)/) { "#{type_to_ooc($1)}*" }
        .gsub(/array\((.+)\)/) { "#{type_to_ooc($1)}[]" }
        .gsub(/Func\(arguments\((.+)\)\)/) { "Func(#{$1})" }
    end

    def supported_type?(type)
      return false if type == '...'
      return false if type.start_with?('array(')
      return false if type.start_with?('reference(')
      return false if type.start_with?('pointer(')
      true
    end

    def compound_cover?(td)
      return false unless td[1].type == 'cover'

      td[1].members.each do |mb|
        return true if mb[1].type == 'field'
      end
      false 
    end

  end
end

