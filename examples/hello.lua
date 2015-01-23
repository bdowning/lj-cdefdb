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
