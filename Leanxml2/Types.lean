-- Copyright (c) 2026 Paul Butcher. All rights reserved.
-- Released under Apache 2.0 license as described in the file LICENSE.

module

namespace Leanxml2

public structure Attribute where
  name : String
  namespaceUri : Option String
  value : String
deriving Repr, BEq

/-- An XML tree node, converted eagerly out of libxml2's C tree; see the
node-lifetime discussion in the README for why. `Node` carries no back-links
to its parent or previous sibling, since it is an ordinary immutable value:
callers that need parent context should track it while traversing. -/
public inductive Node where
  | element (name : String) (namespaceUri : Option String)
      (attributes : Array Attribute) (children : Array Node)
  | text (content : String)
  | cdata (content : String)
  | comment (content : String)
  | processingInstruction (target content : String)
deriving Repr, BEq

namespace Node

/-- Look up a named attribute on an element node, matching by name and (if
given) namespace URI. `none` for any other node kind. -/
public def attribute? (node : Node) (name : String) (namespaceUri : Option String := none) :
    Option String :=
  match node with
  | .element _ _ attributes _ =>
    attributes.find? (fun a => a.name == name && a.namespaceUri == namespaceUri)
      |>.map (·.value)
  | _ => none

public def children : Node → Array Node
  | .element _ _ _ children => children
  | _ => #[]

end Node
end Leanxml2
