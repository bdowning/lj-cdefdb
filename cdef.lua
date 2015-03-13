-- Copyright (C) 2014-2015 Brian Downing.  MIT License.

local ffi = require 'ffi'

local cdef, C, ffi_string, floor, min =
    ffi.cdef, ffi.C, ffi.string, math.floor, math.min

local dbg = function () end
-- dbg = print

cdef[[
struct cdefdb_header {
    int32_t num_stmts;
    int32_t num_constants;
    int32_t stmts_offset;
    int32_t stmt_deps_offset;
    int32_t constants_idx_offset;
    int32_t file_kind_name_idx_offset;
    int32_t file_name_kind_idx_offset;
    int32_t kind_file_name_idx_offset;
    int32_t kind_name_file_idx_offset;
    int32_t name_file_kind_idx_offset;
    int32_t name_kind_file_idx_offset;
    int32_t strings_offset;
};
struct cdefdb_stmts_t {
    int32_t name;
    int32_t kind;
    int32_t extent;
    int32_t file;
    int32_t deps;
    int32_t delayed_deps;
};
struct cdefdb_constants_idx_t {
    int32_t name;
    int32_t stmt;
};

int cdefdb_strcmp(const char *s1, const char *s2) asm("strcmp");
int cdefdb_open(const char *pathname, int flags) asm("open");
void *cdefdb_mmap(void *addr, size_t length, int prot, int flags,
                  int fd, int64_t offset) asm("mmap64");
int cdefdb_close(int fd) asm("close");

enum {
    CDEFDB_O_RDONLY = 0,
    CDEFDB_PROT_READ = 1,
    CDEFDB_MAP_SHARED = 1,
};
]]

local cdefdb_path, cdefdb_size
for p in package.cpath:gmatch('[^;]+') do
    local path = (p:match('^.*/') or '') .. 'cdefdb/'
    local fh = io.open(path .. 'cdef.db')
    if fh then
        cdefdb_path = path
        cdefdb_size = fh:seek('end')
        fh:close()
        break
    end
end
assert(cdefdb_size)

local map_base
do
    local fd = C.cdefdb_open(cdefdb_path .. 'cdef.db',
                             C.CDEFDB_O_RDONLY)
    assert(fd >= 0)
    local m = C.cdefdb_mmap(nil, cdefdb_size,
                            C.CDEFDB_PROT_READ,
                            C.CDEFDB_MAP_SHARED,
                            fd, 0)
    assert(m ~= ffi.cast('void *', -1), ffi.errno())
    C.cdefdb_close(fd)
    map_base = ffi.cast('char *', m)
end

local db = {
    header = ffi.cast('struct cdefdb_header *', map_base)
}
local function db_add(name, ctype)
    db[name] = ffi.cast(ctype, map_base + db.header[name..'_offset'])
end
db_add('stmts', 'struct cdefdb_stmts_t *')
db_add('stmt_deps', 'int32_t *')
db_add('constants_idx', 'struct cdefdb_constants_idx_t *')
db_add('file_kind_name_idx', 'int32_t *')
db_add('file_name_kind_idx', 'int32_t *')
db_add('kind_file_name_idx', 'int32_t *')
db_add('kind_name_file_idx', 'int32_t *')
db_add('name_file_kind_idx', 'int32_t *')
db_add('name_kind_file_idx', 'int32_t *')
db_add('strings', 'char *')

local db_num_stmts = db.header.num_stmts
local db_num_constants = db.header.num_constants
local db_stmts = db.stmts
local db_stmt_deps = db.stmt_deps
local db_constants_idx = db.constants_idx
local db_kind_name_file_idx = db.kind_name_file_idx
local db_strings = db.strings

local strcache = setmetatable({ }, { __mode = 'v' })
local function get_string(offset)
    local ret = strcache[offset]
    if not ret then
        ret = ffi_string(db_strings + offset)
        strcache[offset] = ret
    end
    return ret
end

local function foreach_dep(offset, fun)
    while db_stmt_deps[offset] ~= -1 do
        fun(db_stmt_deps[offset])
        offset = offset + 1
    end
end

local function string_lt(offset, str)
    return C.cdefdb_strcmp(db_strings + offset, str) < 0
end

local function string_ge(offset, str)
    return C.cdefdb_strcmp(db_strings + offset, str) >= 0
end

local function string_eq(offset, str)
    return C.cdefdb_strcmp(db_strings + offset, str) == 0
end

local function lt(a, b) return a < b end
local function gt(a, b) return a > b end
local function ge(a, b) return a > b end

local function identity(x) return x end
local function constantly(x)
    return function () return x end
end

local function lower_bound(arr, low, high, comp)
    local mid
    while true do
        if low > high then
            return low
        end
        mid = floor((high + low) / 2)
        if comp(arr[mid], mid) then -- arr[i] < search
            low = mid + 1
        else
            high = mid - 1
        end
    end
end

local function upper_bound(arr, low, high, comp)
    local mid
    while true do
        if low > high then
            return high
        end
        mid = floor((high + low) / 2)
        if comp(arr[mid], mid) then -- arr[i] > search
            high = mid + 1
        else
            low = mid - 1
        end
    end
end

local function cmp2fn(a, av, b, bv, cmp)
    return function (stmt)
        if string_eq(stmt[a], av) then
            return cmp(stmt[b], bv)
        end
        return cmp(stmt[a], av)
    end
end

local function string_plus_one(str)
    return str:sub(1, -2) .. string.char(str:byte(-1) + 1)
end

local function find_stmts(kind, name)
    local star
    if name:sub(-1) == '*' then
        name = name:sub(1, -2)
        star = true
    end
    local namf = star and string_plus_one(name)
    local cmp_lt_name = cmp2fn('kind', kind, 'name', name, string_lt)
    local cmp_ge_namf =
        star and cmp2fn('kind', kind, 'name', namf, string_ge) or constantly(false)
    local max = db.header.num_stmts
    local b = lower_bound(
        db_kind_name_file_idx,
        0, db.header.num_stmts,
        function (i, mid)
            local stmt = db_stmts[i]
            if cmp_ge_namf(stmt) then
                max = min(mid, max)
            end
            -- print(name, get_string(stmt.name), namf, mid, max)
            return cmp_lt_name(stmt)
        end)
    if not star then
        local i = db_kind_name_file_idx[b]
        if get_string(db_stmts[i].kind) == kind and
            get_string(db_stmts[i].name) == name
        then
            return b, b + 1
        else
            error("cdef: Couldn't find "..kind.." "..name)
        end
    end
    local cmp_lt_namf = cmp2fn('kind', kind, 'name', namf, string_lt)
    local t = lower_bound(
        db_kind_name_file_idx,
        b, max,
        function (i)
            return cmp_lt_namf(db_stmts[i])
        end)
    -- print('b', b, 'max', max, 't', t)
    if b >= t then
        error("cdef: No matching "..kind.." "..name.."*")
    end
    return b, t
end

local function find_constants(name)
    local star
    if name:sub(-1) == '*' then
        name = name:sub(1, -2)
        star = true
    end
    local namf = star and string_plus_one(name)
    local max = db_num_constants
    local b = lower_bound(
        db_constants_idx,
        0, db_num_constants,
        function (entry, mid)
            if star and string_ge(entry.name, namf) or false then
                max = min(mid, max)
            end
            -- print(name, name, namf, mid, max)
            return string_lt(entry.name, name)
            -- local entry_name = get_string(entry.name)
            -- if star and entry_name >= namf or false then
            --     max = min(mid, max)
            -- end
            -- -- print(name, name, namf, mid, max)
            -- return entry_name < name
        end)
    if not star then
        if get_string(db_constants_idx[b].name) == name then
            return b, b + 1
        else
            error("cdef: Couldn't find constant "..name)
        end
    end
    local t = lower_bound(
        db_constants_idx,
        b, max,
        function (entry) return string_lt(entry.name, namf) end)
    -- print('b', b, 'max', max, 't', t)
    if b >= t then
        error("cdef: No matching constants: "..name.."*")
    end
    return b, t
end

local visited = ffi.new('char [?]', db_num_stmts)

local keyword_for_kind = {
    StructDecl = 'struct',
    UnionDecl = 'union',
}

local function emit(to_dump, ldbg)
    ldbg = ldbg or dbg
    local macros = { }
    local function dump(idx)
        local v = visited[idx]
        if v > 0 and v ~= 2 then return end
        local stmt = db_stmts[idx]
        local kind = get_string(stmt.kind)
        if v == 2 then
            if kind == 'StructDecl' or kind == 'UnionDecl' then
                local s = '/* circular */ ' ..
                    keyword_for_kind[kind] .. ' '..get_string(stmt.name)..';'
                ldbg(s)
                cdef(s)
                visited[idx] = 3
                return
            else
                error('circular '..kind..' '..get_string(stmt.extent))
            end
        end
        visited[idx] = 2
        foreach_dep(stmt.deps, dump)
        foreach_dep(stmt.delayed_deps, function (dep)
            to_dump[#to_dump + 1] = dep
        end)
        if kind == 'MacroDefinition' then
            macros[#macros + 1] =
                string.format('/* macro */ enum { %s =%s };',
                              get_string(stmt.name),
                              get_string(stmt.extent))
        else
            if kind == 'StubRef' then
                local hash = get_string(stmt.name)
                ffi.load(cdefdb_path .. 'cdefdb_stubs_'..hash..'.so', true)
            end
            local s = get_string(stmt.extent)..';'
            ldbg(s)
            cdef(s)
        end
        visited[idx] = 1
    end

    ldbg("local ffi = require 'ffi'\nffi.cdef[==[")

    local i = 1
    while i <= #to_dump do
        dump(to_dump[i])
        i = i + 1
    end
    for i = 1, #macros do
        ldbg(macros[i])
        cdef(macros[i])
    end

    ldbg(']==]')
end

local function to_dump_constants(to_dump, name)
    local b, t = find_constants(name)
    for i = b, t-1 do
        to_dump[#to_dump + 1] = db_constants_idx[i].stmt
        -- print('constant', i, to_dump[#to_dump])
    end
end

local function to_dump_stmts(to_dump, kind, name)
    local b, t = find_stmts(kind, name)
    for i = b, t-1 do
        to_dump[#to_dump + 1] = db_kind_name_file_idx[i]
        -- print('stmt', i, to_dump[#to_dump])
    end
end

local kindmap = {
    functions = 'FunctionDecl',
    variables = 'VarDecl',
    structs = 'StructDecl',
    unions = 'UnionDecl',
    enums = 'EnumDecl',
    typedefs = 'TypedefDecl',
}

local loaded = { }
local function cdef_(spec)
    local to_dump = { }
    for k, v in pairs(spec) do
        if type(v) == 'string' then
            v = { v }
        end
        if k == 'constants' then
            for _, name in ipairs(v) do
                if not loaded[name] then
                    to_dump_constants(to_dump, name)
                    loaded[name] = true
                end
            end
        elseif kindmap[k] then
            for _, name in ipairs(v) do
                local kname = k..'\0'..name
                if not loaded[kname] then
                    to_dump_stmts(to_dump, kindmap[k], name)
                    loaded[kname]= true
                end
            end
        end
    end
    emit(to_dump, spec.verbose and print)
    return C, ffi
end

return cdef_

-- cdef_{ funcs = 'ev_*', constants = 'EV*' }
-- cdef_{ funcs = { 'open', 'close', 'read', 'write' }, constants = 'O_*' }

-- local to_dump = { i }
-- to_dump_constants(to_dump, 'EV')
-- emit(to_dump)

-- cdef_{ constants = 'DEFFILEMODE' }
-- cdef_{ constants = 'SQLITE_IOERR_*' }
-- cdef_{ constants = 'EV_READ' }
-- cdef_{ constants = 'EVLOOP_NONBLOCK' }
-- cdef_{ functions = 'ev_*' }
