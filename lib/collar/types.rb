
module Collar
  module Types
    INT_TYPE_RE = /^U?(Int|Short|Long)(8|16|32|64|128)?$/
    NUM_TYPE_RE = /^(Float|Double)(32|64|128)?$/
    FUN_TYPE_RE = /^Func\(.*\)$/

    def presuf_test(type, prefixes, suffixes)
    end

    def type_to_duk(type)
      case type
      when INT_TYPE_RE
        "Int"
      when NUM_TYPE_RE
        "Number"
      when FUN_TYPE_RE
        "ObjectCoercible"
      when /^pointer\(.*\)$/
        "Pointer"
      when /C?String/
        "String"
      when "Bool"
        "Boolean"
      else
        "Ooc"
      end
    end

    def type_is_fun?(type)
      type =~ FUN_TYPE_RE
    end

    def fun_type_arguments(type)
      matches = /Func\(arguments\((.*)\)\)/.match(type)
      return [] unless matches
      raise "Couldn't retrieve function type arguments from '#{type}'" unless matches
      matches[1].split(',').map(&:strip)
    end

    def type_to_ooc(type)
      type
        .gsub(/pointer\((.+)\)/) { "#{type_to_ooc($1)}*" }
        .gsub(/array\((.+)\)/) { "#{type_to_ooc($1)}[]" }
        .gsub(/Func\(arguments\((.+)\)\)/) { "Func(#{$1})" }
    end

  end
end

