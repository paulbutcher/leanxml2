-- Copyright (c) 2026 Paul Butcher. All rights reserved.
-- Released under Apache 2.0 license as described in the file LICENSE.

import Lake
open Lake DSL System

package leanxml2 where
  version := v!"0.1.3"

def pkgConfigFlags (args : Array String) (lib : String) : IO (Array String) := do
  let out ← IO.Process.run { cmd := "pkg-config", args := args.push lib }
  return out.trimAscii.toString.splitOn " " |>.filter (· ≠ "") |>.toArray

target xmlShimDynlib pkg : Dynlib := do
  let srcJob ← inputTextFile <| pkg.dir / "c" / "xml_shim.c"
  srcJob.mapM fun srcFile => do
    addPlatformTrace
    let cflags ← pkgConfigFlags #["--cflags"] "libxml-2.0"
    let libs ← pkgConfigFlags #["--libs"] "libxml-2.0"
    -- -fPIC: this object is linked into a shared library. Some architectures
    -- (observed: aarch64) tolerate non-PIC relocations there; x86_64 does not.
    let cArgs := #["-fPIC", "-I", (← getLeanIncludeDir).toString] ++ cflags
    let oFile := pkg.buildDir / "c" / "xml_shim.o"
    let libFile := pkg.sharedLibDir / (nameToSharedLib "leanxml2_shim")
    let art ← buildArtifactUnlessUpToDate libFile (ext := sharedLibExt) (restore := true) do
      compileO oFile srcFile cArgs "cc"
      let undefinedArgs := if System.Platform.isOSX then #["-undefined", "dynamic_lookup"] else #[]
      compileSharedLib libFile (#[oFile.toString] ++ libs ++ undefinedArgs) "cc"
    return { path := art.path, name := "leanxml2_shim" : Dynlib }

@[default_target]
lean_lib Leanxml2 where
  precompileModules := true
  moreLinkLibs := #[xmlShimDynlib]

-- Tests live in a subproject so that nothing they need, including their
-- dependencies, is resolved by a downstream consumer of this package.
@[test_driver]
script tests do
  let child ← IO.Process.spawn
    { cmd := "lake", args := #["test"], cwd := __dir__ / "test" }
  child.wait
