
module Collar
  module Types
    INT_TYPE_RE = /^U?(Int|Short|Long)(8|16|32|64|128)?$/
    NUM_TYPE_RE = /^(Float|Double)(32|64|128)?$/

    def presuf_test(type, prefixes, suffixes)
    end

    def type_to_duk(type)
      case type
      when INT_TYPE_RE
        "Int"
      when NUM_TYPE_RE
        "Number"
      else
        "Ooc"
      end
    end

    def type_to_ooc(type)
      type
        .gsub(/pointer\((.+)\)/) { "#{type_to_ooc($1)}*" }
        .gsub(/array\((.+)\)/) { "#{type_to_ooc($1)}[]" }
    end

  end
end

