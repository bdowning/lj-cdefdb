local ffi = require 'ffi'
ffi.cdef[[
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
]]

local lC = ffi.load('./cdefdb.so')

local function get_string(offset)
    return ffi.string(lC.cdefdb_stmt_strings + offset)
end

local function foreach_dep(offset, fun)
    while lC.cdefdb_stmt_deps[offset] ~= -1 do
        fun(lC.cdefdb_stmt_deps[offset])
        offset = offset + 1
    end
end

local function lower_bound(arr, low, high, comp)
    local mid
    while true do
        if low > high then
            return low
        end
        mid = math.floor((high + low) / 2)
        if comp(arr[mid]) then -- arr[i] < search
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
        mid = math.floor((high + low) / 2)
        if comp(arr[mid]) then -- arr[i] > search
            high = mid + 1
        else
            low = mid - 1
        end
    end
end

local function cmpfn(key, a, av, cmp)
    return function (el)
        local stmt = key(el)
        local m = get_string(stmt[a])
        return cmp(m, av)
    end
end

local function cmp2fn(key, a, av, b, bv, cmp)
    return function (el)
        local stmt = key(el)
        local m = get_string(stmt[a])
        if m == av then
            local n = get_string(stmt[b])
            return cmp(n, bv)
        end
        return cmp(m, av)
    end
end

local function lt(a, b) return a < b end
local function gt(a, b) return a > b end

local function find_stmt(name, kind)
    local idx = lower_bound(
        lC.cdefdb_stmt_index_name_kind_file,
        0, lC.cdefdb_num_stmts,
        cmp2fn(function (el) return lC.cdefdb_stmts[el] end,
               'name', name, 'kind', kind, lt))
    return lC.cdefdb_stmt_index_name_kind_file[idx]
end

local function identity(x) return x end
local function string_plus_one(str)
    return str:sub(1, -2) .. string.char(str:byte(-1) + 1)
end

local function find_constants(prefix)
    local b = lower_bound(
        lC.cdefdb_constants_idx,
        0, lC.cdefdb_num_constants,
        cmpfn(identity, 'name', prefix, lt))
    local t = lower_bound(
        lC.cdefdb_constants_idx,
        b, lC.cdefdb_num_constants,
        cmpfn(identity, 'name', string_plus_one(prefix), lt))
    return b, t
end

-- print(lC.cdefdb_stmts)
-- print(lC.cdefdb_stmt_strings)
-- print(lC.cdefdb_stmt_deps)

-- for i = 0, lC.cdefdb_num_stmts-1 do
--     print(get_string(lC.cdefdb_stmts[i].name),
--           get_string(lC.cdefdb_stmts[i].kind),
--           get_string(lC.cdefdb_stmts[i].file))
-- end

local i = find_stmt('ev_run', 'FunctionDecl')
-- print(i)
-- print(get_string(lC.cdefdb_stmts[i].name),
--       get_string(lC.cdefdb_stmts[i].kind),
--       get_string(lC.cdefdb_stmts[i].file),
--       get_string(lC.cdefdb_stmts[i].extent))

local visited = { }

local function emit(to_dump)
    local macros = { }
    local function dump(idx)
        local stmt = lC.cdefdb_stmts[idx]
        local kind = get_string(stmt.kind)
        if visited[idx] == 'temporary' then
            if kind == 'StructDecl' then
                print('/* circular */ struct '..get_string(stmt.name)..';')
                visited[idx] = 'circular'
            else
                error('circular '..kind..' '..get_string(stmt.extent))
            end
        end
        if visited[idx] then return end
        visited[idx] = 'temporary'
        foreach_dep(stmt.deps, dump)
        foreach_dep(stmt.delayed_deps, function (dep)
                        to_dump[#to_dump + 1] = dep
        end)
        if kind == 'MacroDefinition' then
            macros[#macros + 1] =
                string.format('    %s =%s,',
                              get_string(stmt.name),
                              get_string(stmt.extent))
        else
            print(get_string(stmt.extent)..';')
        end
        visited[idx] = true
    end

    print[[
local ffi = require 'ffi'
ffi.cdef[==[
]]

    local i = 1
    while i <= #to_dump do
        dump(to_dump[i])
        i = i + 1
    end
    if #macros > 0 then
        print('/* macro */ enum {')
        for i = 1, #macros do
            print(macros[i])
        end
        print('};')
    end

    print(']==]')
end

local function to_dump_constants(to_dump, prefix)
    local b, t = find_constants(prefix)
    for i = b, t-1 do
        table.insert(to_dump, lC.cdefdb_constants_idx[i].stmt)
    end
end

-- local to_dump = { i }
-- to_dump_constants(to_dump, 'EV')
-- emit(to_dump)

local to_dump = { }
to_dump_constants(to_dump, 'O_')
to_dump_constants(to_dump, 'MSG_')
to_dump_constants(to_dump, 'SEEK_')
to_dump_constants(to_dump, 'SIG')
emit(to_dump)
