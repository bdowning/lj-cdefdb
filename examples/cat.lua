local ffi = require 'ffi'
local C = ffi.C

require 'cdef' {
    functions = { 'open', 'read', 'write', 'close' },
    constants = { 'O_RDONLY' },
}

local fd = C.open(arg[1], C.O_RDONLY)
assert(fd >= 0)
local buf = ffi.new('char[512]')
repeat
    local r = C.read(fd, buf, ffi.sizeof(buf))
    if r > 0 then
        C.write(1, buf, r)
    end
until r <= 0
C.close(fd)
