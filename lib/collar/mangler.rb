
module Collar
  module Mangler
    def unmangle(name)
      name.gsub(/__bang(~.+)?/, '!').gsub(/__quest(~.+)?/, '?')
    end
  end
end


