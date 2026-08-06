-- Copyright (c) 2026 Paul Butcher. All rights reserved.
-- Released under Apache 2.0 license as described in the file LICENSE.

import Leanxml2

open Leanxml2

def assertTrue (msg : String) (cond : Bool) : IO Unit :=
  unless cond do throw (IO.userError msg)

def assertEq [BEq α] [Repr α] (msg : String) (expected actual : α) : IO Unit :=
  unless expected == actual do
    throw (IO.userError s!"{msg}: expected {repr expected}, got {repr actual}")

def wellFormedPath := "Test/fixtures/well_formed.xml"
def malformedPath := "Test/fixtures/malformed.xml"

def elementChildren (node : Node) (name : String) : Array Node :=
  node.children.filter fun
    | .element n _ _ _ => n == name
    | _ => false

def findChild (node : Node) (name : String) : Option Node :=
  (elementChildren node name)[0]?

def textOf (node : Node) : String :=
  match (node.children[0]? : Option Node) with
  | some (.text s) => s
  | _ => ""

def testParseWellFormed : IO Unit := do
  let .ok doc ← Doc.parseFile wellFormedPath
    | throw (IO.userError "expected well-formed document to parse")
  let root := doc.root
  match root with
  | .element name _ _ _ => assertEq "root name" "catalog" name
  | _ => throw (IO.userError "root is not an element")
  assertEq "root default namespace" (some "urn:example:catalog")
    (match root with | .element _ ns _ _ => ns | _ => none)
  assertEq "root meta:version attribute" (some "1")
    (root.attribute? "version" (some "urn:example:meta"))

  let books := elementChildren root "book"
  assertEq "book count" 2 books.size
  let some book1 := books[0]?
    | throw (IO.userError "missing first book")
  assertEq "book1 id" (some "b1") (book1.attribute? "id")
  assertEq "book1 meta:featured" (some "true")
    (book1.attribute? "featured" (some "urn:example:meta"))
  assertEq "book2 has no meta:featured" none
    ((books[1]?.getD book1).attribute? "featured" (some "urn:example:meta"))

  let some title1 := findChild book1 "title"
    | throw (IO.userError "missing title")
  assertEq "title1 text" "The Left Hand of Darkness" (textOf title1)

  let some description := findChild book1 "description"
    | throw (IO.userError "missing description")
  let cdata := description.children.filterMap fun
    | .cdata s => some s
    | _ => none
  assertEq "cdata content" #["A novel about <ambassador> diplomacy on Winter."] cdata

  let comments := book1.children.filterMap fun
    | .comment s => some s
    | _ => none
  assertEq "comment content" #[" price includes tax "] comments

  let pis := book1.children.filterMap fun
    | .processingInstruction t c => some (t, c)
    | _ => none
  assertEq "processing instruction" #[("example-hint", "priority=\"high\"")] pis

def testMalformed : IO Unit := do
  let result ← Doc.parseFile malformedPath
  match result with
  | .ok _ => throw (IO.userError "expected malformed document to fail to parse")
  | .error errors =>
    assertTrue "has at least one error" (errors.size > 0)
    let some err := errors[0]?
      | throw (IO.userError "no error present despite nonempty size")
    assertTrue "error has a message" !err.message.isEmpty
    assertTrue "error has a line number" (err.line > 0)

/-- `parse ∘ toString ∘ parse` should agree with `parse`. -/
def testRoundTrip : IO Unit := do
  let .ok doc ← Doc.parseFile wellFormedPath
    | throw (IO.userError "expected well-formed document to parse")
  let dumped ← Doc.toString doc
  let .ok doc2 ← Doc.parseMemory dumped
    | throw (IO.userError "expected round-tripped document to reparse")
  assertEq "round trip is stable" doc.root doc2.root

def testXPath : IO Unit := do
  let .ok doc ← Doc.parseFile wellFormedPath
    | throw (IO.userError "expected well-formed document to parse")
  let result ← doc.xpath "/c:catalog/c:book" #[("c", "urn:example:catalog")]
  match result with
  | .error errors => throw (IO.userError s!"xpath eval failed: {repr errors}")
  | .ok nodes =>
    assertEq "xpath book count" 2 nodes.size
    let ids := nodes.map (·.attribute? "id")
    assertEq "xpath book ids" #[some "b1", some "b2"] ids

/-- Exercises thin-layer primitives (`xmlSearchNs`, sibling/parent
navigation, namespaced attribute lookup) that the idiomatic layer doesn't
re-expose because they operate on raw node pointers, not the eagerly
converted `Node` tree. -/
partial def testLowLevelFFI : IO Unit := do
  let contents ← IO.FS.readFile wellFormedPath
  let h ← FFI.readMemory contents ""
  let _ ← XmlError.take
  assertTrue "doc parsed" !(← FFI.docIsNull h)
  let root ← FFI.docRoot h
  assertTrue "root non-null" (root != 0)

  let defaultNs ← FFI.searchNs h root ""
  assertEq "default namespace via xmlSearchNs" "urn:example:catalog" defaultNs

  let firstBook ← firstElement (← FFI.nodeFirstChild root)
  assertTrue "root has an element child" (firstBook != 0)
  let parent ← FFI.nodeParent firstBook
  assertTrue "book's parent is root" (parent == root)

  let rawNext ← FFI.nodeNext firstBook
  assertTrue "book has a following sibling" (rawNext != 0)
  let rawPrev ← FFI.nodePrev rawNext
  assertTrue "following sibling's prev is the book" (rawPrev == firstBook)

  assertTrue "book element has id attribute" (← FFI.hasProp firstBook "id")
  assertEq "id attribute value" "b1" (← FFI.getProp firstBook "id")
  assertTrue "book has meta:featured attribute"
    (← FFI.hasNsProp firstBook "featured" "urn:example:meta")
  assertEq "meta:featured value" "true" (← FFI.getNsProp firstBook "featured" "urn:example:meta")

  -- `h` must stay referenced until every raw pointer derived from it has
  -- been used: Lean's reference counting is precise, dropping `h` at its
  -- last syntactic use rather than at the end of the `do` block, and a
  -- dropped `Doc.Handle` runs `xmlFreeDoc` immediately. Without this, `h`'s
  -- last use above is `searchNs`, so the compiler is free to free the whole
  -- tree before the later calls that walk `root`/`firstBook` run.
  let _ ← FFI.docIsNull h
where
  /-- Walks a sibling chain to the first element node, since `nodeFirstChild`
  may land on whitespace-only text between tags. -/
  firstElement (n : USize) : IO USize := do
    if n == 0 then
      pure 0
    else if (← FFI.nodeType n) == ElementType.element then
      pure n
    else
      firstElement (← FFI.nodeNext n)

def main : IO Unit := do
  testParseWellFormed
  testMalformed
  testRoundTrip
  testXPath
  testLowLevelFFI
  IO.println "All tests passed."
