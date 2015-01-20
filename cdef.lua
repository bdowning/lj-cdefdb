-- Copyright (C) 2014-2015 Brian Downing.  MIT License.

local ffi = require 'ffi'

local cdef, C, floor, min = ffi.cdef, ffi.C, math.floor, math.min

local dbg = function () end
-- dbg = print

cdef[[
const int cdefdb_num_stmts;
const struct {
    int name;
    int kind;
    int extent;
    int file;
    int deps;
    int delayed_deps;
} cdefdb_stmts[];
const char *cdefdb_stmt_strings;
const int cdefdb_stmt_deps[];
const int cdefdb_num_constants;
const struct {
    int name;
    int stmt;
} cdefdb_constants_idx[];
const int cdefdb_stmt_index_file_kind_name[];
const int cdefdb_stmt_index_file_name_kind[];
const int cdefdb_stmt_index_kind_file_name[];
const int cdefdb_stmt_index_kind_name_file[];
const int cdefdb_stmt_index_name_file_kind[];
const int cdefdb_stmt_index_name_kind_file[];
int cdefdb_strcmp(const char *s1, const char *s2) asm("strcmp");
]]

local cdefdb_so_path
for p in package.cpath:gmatch('[^;]+') do
    local path = (p:match('^.*/') or '') .. 'cdefdb.so'
    local fh = io.open(path)
    if fh then
        cdefdb_so_path = cdefdb_so_path or path
        fh:close()
    end
end
local lC = ffi.load(cdefdb_so_path or 'cdefdb.so')

local strcache = setmetatable({ }, { __mode = 'v' })
local function get_string(offset)
    local ret = strcache[offset]
    if not ret then
        ret = ffi.string(lC.cdefdb_stmt_strings + offset)
        strcache[offset] = ret
    end
    return ret
end

local function foreach_dep(offset, fun)
    while lC.cdefdb_stmt_deps[offset] ~= -1 do
        fun(lC.cdefdb_stmt_deps[offset])
        offset = offset + 1
    end
end

local function string_lt(offset, str)
    return C.cdefdb_strcmp(lC.cdefdb_stmt_strings + offset, str) < 0
end

local function string_ge(offset, str)
    return C.cdefdb_strcmp(lC.cdefdb_stmt_strings + offset, str) >= 0
end

local function string_eq(offset, str)
    return C.cdefdb_strcmp(lC.cdefdb_stmt_strings + offset, str) == 0
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
    local max = lC.cdefdb_num_stmts
    local b = lower_bound(
        lC.cdefdb_stmt_index_kind_name_file,
        0, lC.cdefdb_num_stmts,
        function (i, mid)
            local stmt = lC.cdefdb_stmts[i]
            if cmp_ge_namf(stmt) then
                max = min(mid, max)
            end
            -- print(name, get_string(stmt.name), namf, mid, max)
            return cmp_lt_name(stmt)
        end)
    if not star then
        local i = lC.cdefdb_stmt_index_kind_name_file[b]
        if get_string(lC.cdefdb_stmts[i].kind) == kind and
            get_string(lC.cdefdb_stmts[i].name) == name
        then
            return b, b + 1
        else
            error("cdef: Couldn't find "..kind.." "..name)
        end
    end
    local cmp_lt_namf = cmp2fn('kind', kind, 'name', namf, string_lt)
    local t = lower_bound(
        lC.cdefdb_stmt_index_kind_name_file,
        b, max,
        function (i)
            return cmp_lt_namf(lC.cdefdb_stmts[i])
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
    local max = lC.cdefdb_num_constants
    local b = lower_bound(
        lC.cdefdb_constants_idx,
        0, lC.cdefdb_num_constants,
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
        if get_string(lC.cdefdb_constants_idx[b].name) == name then
            return b, b + 1
        else
            error("cdef: Couldn't find constant "..name)
        end
    end
    local t = lower_bound(
        lC.cdefdb_constants_idx,
        b, max,
        function (entry) return string_lt(entry.name, namf) end)
    -- print('b', b, 'max', max, 't', t)
    if b >= t then
        error("cdef: No matching constants: "..name.."*")
    end
    return b, t
end

local visited = ffi.new('char [?]', lC.cdefdb_num_stmts)

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
        local stmt = lC.cdefdb_stmts[idx]
        local kind = get_string(stmt.kind)
        if v == 2 then
            if kind == 'StructDecl' or kind == 'UnionDecl' then
                local s = '/* circular */ ' ..
                    keyword_for_kind[kind] .. ' '..get_string(stmt.name)..';'
                ldbg(s)
                ffi.cdef(s)
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
            local s = get_string(stmt.extent)..';'
            ldbg(s)
            ffi.cdef(s)
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
        ffi.cdef(macros[i])
    end

    ldbg(']==]')
end

local function to_dump_constants(to_dump, name)
    local b, t = find_constants(name)
    for i = b, t-1 do
        to_dump[#to_dump + 1] = lC.cdefdb_constants_idx[i].stmt
        -- print('constant', i, to_dump[#to_dump])
    end
end

local function to_dump_stmts(to_dump, kind, name)
    local b, t = find_stmts(kind, name)
    for i = b, t-1 do
        to_dump[#to_dump + 1] = lC.cdefdb_stmt_index_kind_name_file[i]
        -- print('stmt', i, to_dump[#to_dump])
    end
end

local kindmap = {
    functions = 'FunctionDecl',
    structs = 'StructDecl',
    unions = 'UnionDecl',
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
