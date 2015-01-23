lj-cdefdb — An auto-generated cdef database for LuaJIT
======================================================

Introduction
------------

This is a "cdef database" for the LuaJIT API.  It is automatically
generated from a collection of header files.  You can request specific
cdefs (e.g. by function, type, or constant name) and it will load them
(and only them) and all of their dependencies:

```lua
local C, ffi = require 'cdef' {
    functions = { 'puts', 'printf', 'clock_gettime', 'open', 'fstat' },
    constants = { 'O_RDONLY', 'CLOCK_*' }
}

local function ok(v) assert(v >= 0) return v end
local function tsfloat(ts)
    return tonumber(ts.tv_sec) + tonumber(ts.tv_nsec) / 1000000000
end

C.puts('Hello, world!')
local now = ffi.new('struct timespec')
ok(C.clock_gettime(C.CLOCK_REALTIME, now))
local sbuf = ffi.new('struct stat')
local fd = ok(C.open(arg[0], C.O_RDONLY))
ok(C.fstat(fd, sbuf))
C.printf('This script was last modified %f seconds ago.\n',
         ffi.cast('double', tsfloat(now) - tsfloat(sbuf.st_mtim)))
```

As an example of what gets loaded:

```c
$ luajit -e "require 'cdef' { verbose = true, functions = 'clock_gettime', constants = 'CLOCK_REALTIME' }"
local ffi = require 'ffi'
ffi.cdef[==[
typedef long __kernel_long_t;
typedef __kernel_long_t __kernel_time_t;
struct timespec {
 __kernel_time_t tv_sec;
 long tv_nsec;
};
typedef int __clockid_t;
typedef __clockid_t clockid_t;
extern int clock_gettime (clockid_t __clock_id, struct timespec *__tp) __attribute__ ((__nothrow__ ));
/* macro */ enum { CLOCK_REALTIME = 0 };
]==]
```

lj-cdefdb keeps track of what has been loaded and will not load the
same cdefs again in future calls.

This is intended to be used in self-contained LuaJIT codebases to both
make it easy to use low-level C APIs and avoid issues of incompatible
redefinitions of cdefs from multiple locations.

### Advantages

* cdefs are automatically generated from system header files.  There's
  little or no manual writing of cdefs required.

* Minimal overhead in both time and memory; only the necessary cdefs
  can be loaded, and the cdef database lives in a shared library so
  that it can be demand-paged and shared between multiple LuaJIT
  processes.

* No run-time dependencies, and it's careful not to load any
  unprefixed cdefs of its own, so your initial FFI namespace will be
  completely clean.

* It's "just C"; reading the manpages and understanding the LuaJIT FFI
  is all you need to know to use it — there's no "luafied" interface
  you additionally need to learn.

* You get the real header file definitions for your platform.  This
  ensures there's no architecture-specific (or other) errors in cdefs.
  Also if lj-cdefdb is used consistently there's no danger of
  "clashing" definitions which can happen with hand-written cdefs from
  different packages that are used together.

### Disadvantages

* There's only one database, so all header files for anything that
  might run need to have been built into that database.  This probably
  makes this unsuitable for general system packaging, but it can work
  fine for a restricted codebase (e.g. a embedded device or a
  self-contained application).

* It's "just C"; there's no helpful Lua shims on top of anything a la
  [ljsyscall](https://github.com/justincormack/ljsyscall).

* You get the real header file definitions for your platform.  This
  means they're likely FFI-definition incompatible with other
  FFI-using packages (again, such as ljsyscall).

* It's brand new and quite possibly buggy.

* It probably only works on Linux for now, and it probably needs a
  little bit of scripting/build-system work to be able to be
  cross-compiled, though that is a goal.

Prerequisites
-------------

lj-cdefdb uses [Clang](http://clang.llvm.org/) as its C parser.  This
will need to be installed to generate the cdef database.  (Clang is
_not_ required at runtime.)  Examples of installing it for some
distributions:

* Debian derivatives: `# apt-get install clang-3.5 libclang-3.5-dev`
* Fedora: `# yum install clang clang-devel`
* Arch: `# pacman -S clang`
* Gentoo: `# emerge clang`

Also obviously LuaJIT must be installed.

Database Generation
-------------------

The `gen-cdefdb` command is used to generate the database.  It takes
as input a C file that should include every header file whose
definitions are required in the database.  The usage of this is:

```
./gen-cdefdb (file.c|-) <cc args...>
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
cdefs that are being loaded.  You need not include types that are
arguments of loaded function calls or contained by other types, as
they will be pulled in automatically.  Note however that a `typedef`
for a loaded named `struct` will not itself be loaded unless it is
referenced by something else or specifically requested, even if they
were defined in a single statement in the header files!

If there is only one of a kind requested a string can be used instead
of a single-entry table.

Finally, a glob-style star can be used at the end (and only the end)
of a name:

```lua
require 'cdef' { constants = 'O_*' }
```

`require 'cdef'` always returns `ffi.C` and `ffi`, so you can save
some typing in common cases:

```lua
local C, ffi = require 'cdef' { ... }
```

Stability
---------

The `require 'cdef'` interface is unlikely to change incompatibly at
this point.  The database format, however, is not (and likely never
will be) stable and must be regerated each time lj-cdefdb is updated.

cdef Helper Utility
-------------------

`cdef-helper` is a tool to help convert `ffi.cdef` statements (as may
be seen in existing code) into `require 'cdef'` statements.  Its usage
is:

```
./cdef-helper (cdef_bodies.c|-) <cc args...>
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
