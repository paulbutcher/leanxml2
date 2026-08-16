-- Copyright (c) 2026 Paul Butcher. All rights reserved.
-- Released under Apache 2.0 license as described in the file LICENSE.

import Lake
open Lake DSL

package leanxml2Test

require leanxml2 from ".."

@[test_driver]
lean_exe tests where
  root := `Main
