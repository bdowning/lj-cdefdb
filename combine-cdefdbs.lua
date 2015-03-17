-- Copyright (C) 2014-2015 Brian Downing.  MIT License.

local ffi = require 'ffi'

local cdef, C, ffi_string =
    ffi.cdef, ffi.C, ffi.string

local dbg = function () end
-- dbg = print

local cdefdb_open = require 'cdefdb.open'
local cdefdb_write = require 'cdefdb.write'

local db_names = {...}

local dbs = { }
for _, name in ipairs(db_names) do
    dbs[name] = cdefdb_open(name)
end

table.sort(db_names, function (a, b)
    return dbs[a].size > dbs[b].size
end)

local function get_string(db, offset)
    return ffi_string(db.strings + offset)
end

local stmt_idx = 1
local stmts = { }
local constants = { }

local function get_tag(db, stmt_idx)
    local db_stmt = db.stmts[stmt_idx]
    local name = get_string(db, db_stmt.name)
    local kind = get_string(db, db_stmt.kind)
    return kind..','..name
end

for _, db_name in ipairs(db_names) do
    local db = dbs[db_name]
    for i = 0, db.header.num_stmts - 1 do
        local db_stmt = db.stmts[i]
        local stmt = {
            name = get_string(db, db_stmt.name),
            kind = get_string(db, db_stmt.kind),
            extent = get_string(db, db_stmt.extent),
            file = get_string(db, db_stmt.file),
            tag = get_tag(db, i),
            idx = stmt_idx,
            deps = { },
            delayed_deps = { },
            db_name = db_name
        }
        for _, dep_type in ipairs{'deps', 'delayed_deps'} do
            local deps = { }
            local d = db_stmt[dep_type]
            while db.stmt_deps[d] ~= -1 do
                stmt[dep_type][get_tag(db, db.stmt_deps[d])] = true
                d = d + 1
            end
        end
        if not stmts[stmt.tag] or stmts[stmt.tag].db_name == db_name then
            -- print('name', stmt.name)
            -- print('kind', stmt.kind)
            -- print('extent', stmt.extent)
            -- print('file', stmt.file)
            -- print('db_name', stmt.db_name)
            -- print('deps', db_stmt.deps)
            -- for dep, _ in pairs(stmt.deps) do
            --     print('', dep)
            -- end
            -- print('delayed_deps', db_stmt.delayed_deps)
            -- for dep, _ in pairs(stmt.delayed_deps) do
            --     print('', dep)
            -- end
            if stmts[stmt.tag] and stmts[stmt.tag].db_name == db_name then
                stmt.idx = stmts[stmt.tag].idx
            else
                stmt_idx = stmt_idx + 1
            end
            stmts[stmt.tag] = stmt
        end
    end

    for i = 0, db.header.num_constants - 1 do
        local name = get_string(db, db.constants_idx[i].name)
        if not constants[name] then
            constants[name] = stmts[get_tag(db, db.constants_idx[i].stmt)]
        end
    end
end

local f = assert(io.open('cdef.db', 'w'))
cdefdb_write(f, stmts, constants)
f:close()
