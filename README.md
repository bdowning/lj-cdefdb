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

cdef Helper Utility
-------------------

`cdef-helper` is a tool to help convert `ffi.cdef` statements (as may
be seen in existing code) into `require 'cdef'` statements.  Its usage
is:

```
./cdef-helper cdef_bodies.c <cc args...>
```

Its input should consist of the bodies of the ffi.cdef you'd like to
convert.  For example:

```
$ cat /tmp/foo.c
void *malloc(size_t sz);
void *realloc(void*ptr, size_t size);
void free(void *ptr);
int sprintf(char *str, const char *format, ...);
int printf(const char *format, ...);
$ ./cdef-helper /tmp/foo.c
require 'cdef' {
    functions = {
        'free',
        'malloc',
        'printf',
        'realloc',
        'sprintf',
    },
}
```

Additionally, you can add `__emit__();` in the input file to cause a
`require 'cdef'` statement to be emitted immediately; this is useful
for files that have multiple sequential `ffi.cdef` statements mixed
with other code:

```
$ cat /tmp/foo.c
void *malloc(size_t sz);
void *realloc(void*ptr, size_t size);
void free(void *ptr);
__emit__();
int socket(int domain, int type, int protocol);
int bind(int fd, const struct sockaddr *addr, socklen_t len);
int listen(int fd, int backlog);
$ ./cdef-helper /tmp/foo.c
require 'cdef' {
    functions = {
        'free',
        'malloc',
        'realloc',
    },
}
require 'cdef' {
    functions = {
        'bind',
        'listen',
        'socket',
    },
}
```

Thanks
------

Thanks to Philipp Kutin for [ljclang](https://github.com/helixhorned/ljclang).

Copyright and License
---------------------

Copyright © 2014–2015 [Brian Downing](https://github.com/bdowning).
[MIT License.](LICENSE)
