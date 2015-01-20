lj-cdefdb — An auto-generated cdef database for LuaJIT
======================================================

Introduction
------------

This is intended to be used in a self-contained LuaJIT codebase to
both make it easy to define and use low-level C APIs from LuaJIT, and
to avoid the issue of incompatible redefinitions of cdefs from
multiple locations.

Prerequisites
-------------

lj-cdefdb uses [Clang](http://clang.llvm.org/) as its C parser.  This
will need to be installed.  For Debian derivatives, something like
```
# apt-get install clang-3.5 libclang-3.5-dev
```
should work fine.  Also obviously LuaJIT must be installed.

Database Generation
-------------------

The `gen-cdefdb` command is used to generate the database.  It takes
as input a C file that should include every header file whose
definitions are required in the database.  The usage of this is:
```
./gen-cdefdb file.c <cc args...>
```
This generates `cdefdb.so` (and `cdefdb.c`) in the current directory.

Usage
-----

Copy `cdef.lua` to your lua share directory and `cdefdb.so` to your
lua lib directory.  Then you can do, for example:
```lua
require 'cdef' {
    functions = { 'open', 'read', 'write', 'close' },
    constants = { 'O_RDONLY' },
}
```
...which will import the requested cdefs, and all of their
dependencies, into the LuaJIT FFI C namespace.

In addition to `functions` and `constants`, you can also request
`variables`, `structs`, `unions`, `enums`, and `typedefs`.  (Structs,
unions, and enums should not include `struct`, `union`, or `enum` in
their names.)  Also, by adding `verbose = true`, it will print out the
cdefs that are occurring.

If there is only one of a type requested a string can be used instead
of a single-entry table.

Finally, a glob-style star can be used at the end (and only the end)
of a name:
```lua
require 'cdef' { constants = 'O_*' }
```

Thanks
------

Thanks to Philipp Kutin for [ljclang](https://github.com/helixhorned/ljclang).

Copyright and License
---------------------

Copyright © 2014–2015 [Brian Downing](https://github.com/bdowning).
[MIT License.](LICENSE)
