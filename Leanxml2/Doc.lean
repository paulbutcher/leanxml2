-- Copyright (c) 2026 Paul Butcher. All rights reserved.
-- Released under Apache 2.0 license as described in the file LICENSE.

import Leanxml2.FFI
import Leanxml2.Types
import Leanxml2.Error

namespace Leanxml2

-- The `xmlElementType` values this library interprets when converting a
-- node; matches the C enum in `libxml/tree.h`.
namespace ElementType
def element : UInt32 := 1
def text : UInt32 := 3
def cdata : UInt32 := 4
def pi : UInt32 := 7
def comment : UInt32 := 8
end ElementType

private def optionalString (s : String) : Option String :=
  if s.isEmpty then none else some s

private def buildAttributes (n : USize) : IO (Array Attribute) := do
  let count ← FFI.nodeAttrCount n
  (Array.range count.toNat).mapM fun i => do
    let i := i.toUInt32
    pure {
      name := ← FFI.nodeAttrName n i
      namespaceUri := optionalString (← FFI.nodeAttrNsHref n i)
      value := ← FFI.nodeAttrValue n i
      : Attribute
    }

/-- Recursion follows `xmlNodePtr` sibling/child links, which carry no
structural termination evidence Lean can see, so this must be `partial`. -/
partial def buildNode (n : USize) : IO Node := do
  let ty ← FFI.nodeType n
  if ty == ElementType.element then
    let name ← FFI.nodeName n
    let ns ← optionalString <$> FFI.nodeNsHref n
    let attributes ← buildAttributes n
    let children ← buildChildren (← FFI.nodeFirstChild n)
    pure (.element name ns attributes children)
  else if ty == ElementType.cdata then
    pure (.cdata (← FFI.nodeContent n))
  else if ty == ElementType.comment then
    pure (.comment (← FFI.nodeContent n))
  else if ty == ElementType.pi then
    pure (.processingInstruction (← FFI.nodeName n) (← FFI.nodeContent n))
  else
    pure (.text (← FFI.nodeContent n))
where
  /-- Walks a sibling chain starting at `n`, keeping only node kinds `Node`
  represents (so a stray DTD or entity-declaration node, say, is dropped
  rather than misrepresented as text). -/
  buildChildren (n : USize) : IO (Array Node) := do
    if n == 0 then
      pure #[]
    else
      let ty ← FFI.nodeType n
      let known := ty == ElementType.element || ty == ElementType.text
        || ty == ElementType.cdata || ty == ElementType.comment || ty == ElementType.pi
      let rest ← buildChildren (← FFI.nodeNext n)
      if known then
        let node ← buildNode n
        pure (#[node] ++ rest)
      else
        pure rest

/-- A parsed document: an eagerly-converted `Node` tree plus the underlying
handle, kept alive only so `toString`/`rootToString` can re-serialize via
libxml2's own writer. See the README for why node pointers themselves never
escape the C shim. -/
structure Doc where
  handle : FFI.Doc.Handle
  root : Node

namespace Doc

private def afterParse (h : FFI.Doc.Handle) : IO (Except (Array XmlError) Doc) := do
  let errors ← XmlError.take
  if ← FFI.docIsNull h then
    pure (.error errors)
  else
    let root ← buildNode (← FFI.docRoot h)
    pure (.ok { handle := h, root })

def parseMemory (contents : String) (url : String := "") : IO (Except (Array XmlError) Doc) := do
  afterParse (← FFI.readMemory contents url)

def parseFile (path : String) : IO (Except (Array XmlError) Doc) := do
  afterParse (← FFI.readFile path)

/-- Serialize the whole document, as parsed, via `xmlDocDumpMemory`. -/
def toString (doc : Doc) : IO String :=
  FFI.docDump doc.handle

/-- Serialize just the root element, via `xmlNodeDump`. -/
def rootToString (doc : Doc) : IO String := do
  FFI.nodeDump doc.handle (← FFI.docRoot doc.handle)

end Doc
end Leanxml2
