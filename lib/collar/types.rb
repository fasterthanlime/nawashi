
module Collar
  module Types
    INT_TYPE_RE = /^U?(Int|Short|Long)(8|16|32|64|128)?$/
    NUM_TYPE_RE = /^(Float|Double)(32|64|128)?$/
    FUN_TYPE_RE = /^Func\(.*\)$/

    def type_is_fun?(type)
      type =~ FUN_TYPE_RE
    end

    def fun_type_arguments(type)
      matches = /Func\(.*arguments\((.*)\)\)/.match(type)
      return [] unless matches
      matches[1].split(',').map(&:strip)
    end

    def fun_type_return(type)
      matches = /Func\(.*return\((.*)\)\)/.match(type)
      return "any" unless matches
      return matches[1]
    end

    def type_to_ooc(type)
      type
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

