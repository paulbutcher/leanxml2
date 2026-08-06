-- Copyright (c) 2026 Paul Butcher. All rights reserved.
-- Released under Apache 2.0 license as described in the file LICENSE.

import Leanxml2.FFI

namespace Leanxml2

structure XmlError where
  message : String
  domain : UInt32
  code : UInt32
  line : UInt32
deriving Repr, BEq

namespace XmlError

/-- Drain the errors and warnings libxml2 has reported since the last call to
`take`, via the structured error handler registered at startup. -/
def take : IO (Array XmlError) := do
  let n ← FFI.errorCount
  let errors ← (Array.range n.toNat).mapM fun i => do
    let i := i.toUInt32
    pure {
      message := ← FFI.errorMessage i
      domain := ← FFI.errorDomain i
      code := ← FFI.errorCode i
      line := ← FFI.errorLine i
      : XmlError
    }
  FFI.clearErrors
  return errors

end XmlError
end Leanxml2
