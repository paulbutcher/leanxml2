-- Copyright (c) 2026 Paul Butcher. All rights reserved.
-- Released under Apache 2.0 license as described in the file LICENSE.

/-!
Thin, near-1:1 bindings to libxml2's C API. One function per C call, minimal
translation: strings, `Bool`s and scalars only, no algebraic data types built
in C.

`xmlNodePtr`, `xmlXPathContextPtr` and `xmlXPathObjectPtr` values are passed
across the boundary as raw addresses boxed in a `USize`, with `0` standing in
for `NULL`. They are never wrapped in their own `external_class` handle: only
`Doc.Handle` is a long-lived GC-managed object, and every node/context/object
pointer used here stays valid only as long as the `Doc.Handle` that produced
it is still reachable.

Callers using this layer directly (rather than through the idiomatic `Doc`
API, which handles this correctly) must keep a `Doc.Handle` referenced past
the *last* use of any raw pointer derived from it, not merely somewhere in
the same `do` block: Lean's reference counting is precise and drops a value
at its last syntactic use, so `xmlFreeDoc` can run as soon as the handle's
own last use passes, even while later statements still hold raw pointers
into the tree it just freed. A trailing no-op use of the handle (or, better,
storing it alongside the derived data, as `Doc` does) keeps it alive for as
long as needed.
-/

namespace Leanxml2.FFI

namespace Doc
private opaque HandleImpl : NonemptyType.{0}
def Handle : Type := HandleImpl.type
instance : Nonempty Handle := HandleImpl.property
end Doc

@[extern "lean_xml_global_init"]
private opaque globalInit : IO Unit

initialize globalInit

@[extern "lean_xml_read_memory"]
opaque readMemory (contents url : @& String) : IO Doc.Handle

@[extern "lean_xml_read_file"]
opaque readFile (path : @& String) : IO Doc.Handle

@[extern "lean_xml_doc_is_null"]
opaque docIsNull (h : @& Doc.Handle) : IO Bool

@[extern "lean_xml_doc_root"]
opaque docRoot (h : @& Doc.Handle) : IO USize

@[extern "lean_xml_doc_dump"]
opaque docDump (h : @& Doc.Handle) : IO String

@[extern "lean_xml_node_dump"]
opaque nodeDump (h : @& Doc.Handle) (n : USize) : IO String

@[extern "lean_xml_node_type"]
opaque nodeType (n : USize) : IO UInt32

@[extern "lean_xml_node_name"]
opaque nodeName (n : USize) : IO String

@[extern "lean_xml_node_content"]
opaque nodeContent (n : USize) : IO String

@[extern "lean_xml_node_first_child"]
opaque nodeFirstChild (n : USize) : IO USize

@[extern "lean_xml_node_next"]
opaque nodeNext (n : USize) : IO USize

@[extern "lean_xml_node_prev"]
opaque nodePrev (n : USize) : IO USize

@[extern "lean_xml_node_parent"]
opaque nodeParent (n : USize) : IO USize

@[extern "lean_xml_node_ns_href"]
opaque nodeNsHref (n : USize) : IO String

@[extern "lean_xml_node_ns_prefix"]
opaque nodeNsPrefix (n : USize) : IO String

@[extern "lean_xml_node_attr_count"]
opaque nodeAttrCount (n : USize) : IO UInt32

@[extern "lean_xml_node_attr_name"]
opaque nodeAttrName (n : USize) (i : UInt32) : IO String

@[extern "lean_xml_node_attr_ns_href"]
opaque nodeAttrNsHref (n : USize) (i : UInt32) : IO String

@[extern "lean_xml_node_attr_value"]
opaque nodeAttrValue (n : USize) (i : UInt32) : IO String

@[extern "lean_xml_has_prop"]
opaque hasProp (n : USize) (name : @& String) : IO Bool

@[extern "lean_xml_get_prop"]
opaque getProp (n : USize) (name : @& String) : IO String

@[extern "lean_xml_has_ns_prop"]
opaque hasNsProp (n : USize) (name namespaceHref : @& String) : IO Bool

@[extern "lean_xml_get_ns_prop"]
opaque getNsProp (n : USize) (name namespaceHref : @& String) : IO String

/-- `prefix = ""` searches for the default namespace, matching libxml2's own
`NULL`-means-default convention. -/
@[extern "lean_xml_search_ns"]
opaque searchNs (h : @& Doc.Handle) (n : USize) (nsPrefix : @& String) : IO String

@[extern "lean_xml_error_count"]
opaque errorCount : IO UInt32

@[extern "lean_xml_error_message"]
opaque errorMessage (i : UInt32) : IO String

@[extern "lean_xml_error_domain"]
opaque errorDomain (i : UInt32) : IO UInt32

@[extern "lean_xml_error_code"]
opaque errorCode (i : UInt32) : IO UInt32

@[extern "lean_xml_error_line"]
opaque errorLine (i : UInt32) : IO UInt32

@[extern "lean_xml_clear_errors"]
opaque clearErrors : IO Unit

@[extern "lean_xml_xpath_new_context"]
opaque xpathNewContext (h : @& Doc.Handle) : IO USize

@[extern "lean_xml_xpath_free_context"]
opaque xpathFreeContext (ctx : USize) : IO Unit

@[extern "lean_xml_xpath_register_ns"]
opaque xpathRegisterNs (ctx : USize) (nsPrefix href : @& String) : IO Bool

@[extern "lean_xml_xpath_eval"]
opaque xpathEval (ctx : USize) (expr : @& String) : IO USize

@[extern "lean_xml_xpath_free_object"]
opaque xpathFreeObject (obj : USize) : IO Unit

@[extern "lean_xml_xpath_is_nodeset"]
opaque xpathIsNodeSet (obj : USize) : IO Bool

@[extern "lean_xml_xpath_node_count"]
opaque xpathNodeCount (obj : USize) : IO UInt32

@[extern "lean_xml_xpath_node_at"]
opaque xpathNodeAt (obj : USize) (i : UInt32) : IO USize

end Leanxml2.FFI
