
module Collar
  module Prelude
    PRELUDE = %Q{
use duktape
import structs/HashMap

DUK_PROTO_CACHE := HashMap<Class, String> new()

extend DukContext {
    requireOoc: func (index: Int) -> Object {
        getPropString(index, "pointer")
        res := requirePointer(-1)
        pop()
        res
    }

    pushOoc: func (obj: Object)  {
        objIdx := pushObject()
        clazz := obj class
        protoName := DUK_PROTO_CACHE get(clazz)

        if (!protoName) {
            raise("No duk bindings for " + (clazz name))
        }

        getGlobalString(protoName)
        setPrototype(objIdx)

        pushPointer(obj)
        putPropString(objIdx, "pointer")
    }
}

// Auto-generated code starts here
    }
  end
end
