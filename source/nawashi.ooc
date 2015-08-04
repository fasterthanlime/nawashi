
use duktape
import structs/HashMap

DUK_PROTO_CACHE := HashMap<Class, String> new()
DUK_REVERSE_PROTO_CACHE := HashMap<String, Class> new()
DUK_ID_SEED := 2424

extend DukContext {
    putClass: static func (clazz: Class, name: String) {
      DUK_PROTO_CACHE put(clazz, name)
      DUK_REVERSE_PROTO_CACHE put(name, clazz)
    }

    freshID: static func -> String {
      DUK_ID_SEED += 1
      "_duk_seeded_" + DUK_ID_SEED
    }

    setInheritance: func (child, parent: String) {
      getGlobalString(child)
      getGlobalString(parent)
      if (isUndefined(-1) || isUndefined(-2)) {
        "Can't set up inheritance #{child} => #{parent}" println()
      } else {
        setPrototype(-2)
      }
      pop()
    }

    requireOoc: func (index: Int) -> Object {
        if (isNull(index)) { return null; }
        getPropString(index, "pointer")
        res := requirePointer(-1)
        pop()
        res
    }

    pushOoc: func (ptr: Pointer, protoName: String = null)  {
        obj := ptr as Object
        objIdx := pushObject()

        if (obj != null) {
          // if specified, check it exists
          if (protoName) {
            if (!DUK_REVERSE_PROTO_CACHE contains?(protoName)) {
              // that won't do then - probably a subclass or something.
              protoName = null
            }
          }

          if (!protoName) {
            // try looking it up then.
            clazz := obj class
            protoName = DUK_PROTO_CACHE get(clazz)

            if (!protoName) {
                // couldn't find it by any means :(
                raise("No duk bindings for %s (class address: %p)" format(clazz name, clazz))
            }
          }

          getGlobalString(protoName)
          setPrototype(objIdx)
        }

        pushPointer(obj)
        putPropString(objIdx, "pointer")
    }
}

