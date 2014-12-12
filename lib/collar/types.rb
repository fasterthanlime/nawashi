
module Collar
  module Types
    INT_TYPES = %w(Int UInt Short)
    NUMBER_TYPES = %w(Float Double)

    def type_to_duk(type)
      case
      when INT_TYPES.any? { |x| type.start_with?(x) }
        "Int"
      when NUMBER_TYPES.any? { |x| type.start_with?(x) }
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

