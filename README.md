# leanxml2

A Lean 4 binding to [libxml2](http://xmlsoft.org/), covering DOM parsing,
tree navigation, attributes, namespaces, serialization and XPath.

## Two-layer design

- `Leanxml2.FFI`: a thin, near-1:1 binding to libxml2's C API. One `opaque`
  Lean function per C call, opaque handles, minimal translation. Anything
  libxml2 can do in this pass's scope, this layer can do.
- `Leanxml2.Doc` / `Leanxml2.Types` / `Leanxml2.Error` / `Leanxml2.XPath`: an
  idiomatic layer on top, with real Lean types (`Node`, `Attribute`,
  `XmlError`, `Except` for failure) instead of raw pointers and codes.

## Node lifetime

An `xmlDocPtr` owns its whole tree; every `xmlNodePtr` inside it is valid
only until `xmlFreeDoc` runs. This library converts eagerly: parsing walks
the C tree once and builds a plain, immutable `Node` value (see
`Leanxml2/Types.lean`), and no `xmlNodePtr` ever escapes the C shim as its
own long-lived Lean object. Only `Doc` retains a handle to the underlying
`xmlDocPtr`, kept alive solely so `Doc.toString`/`Doc.rootToString` can
re-serialize via libxml2's own writer later.

This costs a full tree copy into Lean memory at parse time, in exchange for
a much simpler ownership story than tracking individual node lifetimes
against their owning document. Revisit this if profiling ever shows the
copy is a real bottleneck for documents this library needs to handle.

One consequence worth knowing if you use `Leanxml2.FFI` directly: Lean's
reference counting is precise, dropping a value at its last syntactic use
rather than at the end of an enclosing block. A `Doc.Handle` must stay
referenced past the *last* raw pointer derived from it, or the tree can be
freed out from under a still-in-flight raw `USize` node pointer. The
idiomatic `Doc` API handles this for you (see `Leanxml2/FFI.lean`'s module
doc comment for the full argument).

## Scope

In scope for this pass: parsing into a DOM tree (`xmlReadMemory`/
`xmlReadFile`, safe-by-default: no network, no external DTD loading), tree
navigation, attributes, namespaces, serialization
(`xmlDocDumpMemory`/`xmlNodeDump`), a minimal XPath wrapper, and structured
error reporting.

Explicitly deferred to a later pass, with the C shim and `lakefile.lean`
structured so they can be added without rework: the HTML parser, XSD/
RelaxNG/DTD validation, XInclude, C14N, catalogs, the streaming
`xmlTextReader`/`xmlTextWriter` APIs, custom SAX2 handlers, URI parsing, and
non-default encoding handling.

## Usage

```lean
import Leanxml2

open Leanxml2

def main : IO Unit := do
  match ← Doc.parseFile "catalog.xml" with
  | .error errors => for e in errors do IO.eprintln e.message
  | .ok doc =>
    match doc.root with
    | .element name _ _ children =>
      IO.println s!"root: {name}, {children.size} children"
    | _ => pure ()
    match ← doc.xpath "//book[@id='b1']" with
    | .ok nodes => IO.println s!"matched {nodes.size} node(s)"
    | .error errors => for e in errors do IO.eprintln e.message
```

## Development

Requires `libxml2` (with headers) and `pkg-config`, discoverable via
`pkg-config libxml-2.0`. If they're missing, install them before building;
this project never installs OS packages itself.

```
lake build
lake test
```
