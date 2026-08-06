-- Copyright (c) 2026 Paul Butcher. All rights reserved.
-- Released under Apache 2.0 license as described in the file LICENSE.

import Leanxml2.Doc

namespace Leanxml2
namespace Doc

/-- Evaluate an XPath expression against `doc`'s root, with `namespaces` as
`(prefix, href)` pairs available to the expression. The matched node-set is
converted eagerly to `Node` values; an expression that evaluates to a number,
string or boolean rather than a node-set yields an empty array. -/
def xpath (doc : Doc) (expr : String) (namespaces : Array (String × String) := #[]) :
    IO (Except (Array XmlError) (Array Node)) := do
  let ctx ← FFI.xpathNewContext doc.handle
  if ctx == 0 then
    pure (.error (← XmlError.take))
  else
    for (nsPrefix, href) in namespaces do
      let _ ← FFI.xpathRegisterNs ctx nsPrefix href
    let obj ← FFI.xpathEval ctx expr
    let errors ← XmlError.take
    if obj == 0 then
      FFI.xpathFreeContext ctx
      pure (.error errors)
    else
      let nodes ←
        if ← FFI.xpathIsNodeSet obj then
          let count ← FFI.xpathNodeCount obj
          (Array.range count.toNat).mapM fun i => do buildNode (← FFI.xpathNodeAt obj i.toUInt32)
        else
          pure #[]
      FFI.xpathFreeObject obj
      FFI.xpathFreeContext ctx
      pure (if errors.isEmpty then .ok nodes else .error errors)

end Doc
end Leanxml2
