#!/usr/bin/env luajit

assert(arg[1], "Usage: "..arg[0].." <filename> ...")

local cl = require("ljclang")

arg[0] = nil
local tu = cl.createIndex():parse(arg, {"DetailedPreprocessingRecord"})

if (tu == nil) then
    print('TU is nil')
    os.exit(1)
end

local tu_cur = tu:cursor()

do
    local cacheF = setmetatable({}, {__mode="k"})
    function getExtent(file, fromOffs, toOffs)
        if not file then return '' end
        local f = cacheF[file]
        if not f then
            f = assert(io.open(file))
            cacheF[file] = f
        end
        f:seek('set', fromOffs)
        local r = f:read(toOffs - fromOffs)
        return r
    end
end

local function cursor_tag(cur)
    -- local f, b, e = cur:location('offset')
    -- return string.format('%s:%d:%d', f or '?', b or 0, e or 0)
    local f, r1, c1, r2, c2 = cur:location()
    return string.format('%s:%d:%d:%d:%d', f or '?', r1 or 0, c1 or 0, r2 or 0, c2 or 0)
end

local stmts = { }

local struct_dep_mode = 'no_deps'

function store_stmt(cur)
    if not cur:location() then return end

    if cur:haskind('StructDecl') then
        cur = cur:type():declaration()
    end

    local tag = cursor_tag(cur)
    if stmts[tag] then return end

    local file = cur:presumedLocation()
    if file:match('^<.*>$') then return end
    local stmt = {
        name = cur:name(),
        kind = cur:kind(),
        extent = getExtent(cur:location('offset')),
        file = file,
        tag = tag,
        deps = { },
        delayed_deps = { },
        no_deps = { },
    }

    stmts[tag] = stmt
    -- print('tag', tag)

    find_deps(cur, nil, struct_dep_mode, stmt)

    --print(tag, stmt.kind, stmt.name, stmt.tag, stmt.tag == tag)

    if cur:haskind('TypedefDecl') then
        -- eat structs defined inside typedefs
        local _, b, e = cur:location('offset')
        local decl = cur:typedefType():declaration()
        local _, kb, ke = decl:location('offset')
        if decl:haskind('StructDecl') and kb and b <= kb and e >= ke then
            if decl:name() == '' then
                local old_stmt = stmts[cursor_tag(decl)]
                for k, v in pairs(old_stmt.deps) do
                    stmt.deps[k] = v
                end
                for k, v in pairs(old_stmt.delayed_deps) do
                    stmt.delayed_deps[k] = v
                end
                stmts[cursor_tag(decl)] = stmt
            else
                stmt.extent = '/*FAKE*/ typedef ' .. tostring(cur:typedefType()) .. ' ' .. stmt.name
            end
        end
        -- if kid and kid:haskind('StructDecl') and kid:name() ~= '' then
        --     find_deps(kid, nil, struct_dep_mode, stmt)
        --     stmts[kid_tag] = stmt
        -- end
        -- if kid and kid:haskind('TypeRef') then
        --     local _, b, e = cur:location('offset')
        --     local _, kb, ke = cur:typedefType():declaration():location('offset')
        --     if kb and b <= kb and e >= ke then
        --         local kid_tag = cursor_tag(cur:typedefType():declaration())
        --         -- print('OVERRIDE', kid, kid_tag, stmts[kid_tag], stmt)
        --         stmts[kid_tag] = stmt
        --     end
        -- end
    end
end

function base_type(type)
    if type:haskind('ConstantArray') or type:haskind('VariableArray') then
        return base_type(type:arrayElementType())
    elseif type:haskind('Pointer') then
        return base_type(type:pointee())
    else
        return type
    end
end

function is_pointer(type)
    if type:haskind('ConstantArray') or type:haskind('VariableArray') then
        return is_pointer(type:arrayElementType())
    elseif type:haskind('Pointer') then
        return true
    else
        return false
    end
end

function find_deps(cur, parent, struct_ptr_mode, stmt)
    if cur:haskind('ParmDecl') then
        -- print('ParmDecl', cur, cursor_tag(cur))
        for i, kid in ipairs(cur:children()) do
            find_deps(kid, cur, 'deps', stmt)
        end
    elseif cur:haskind('TypeRef') then
        local typedecl = cur:type():declaration()
        local mode = 'deps'
        local parent_type = parent:type()
        -- print(cur:type(), cur:type():declaration(), cursor_tag(cur:type():declaration()))
        if parent:haskind('FunctionDecl') then
            parent_type = parent:resultType()
        end
        if typedecl:haskind('StructDecl') and is_pointer(parent_type) then
            mode = struct_ptr_mode
        end
        -- print(mode, cursor_tag(typedecl))
        stmt[mode][cursor_tag(typedecl)] = true
        local canonical = cur:type():canonical()
        local parent_canonical = parent_type:canonical()
        -- print('CANONICAL', cur:type(), cur:type():canonical(), parent_type, parent_canonical)
        if canonical:declaration():haskind('StructDecl') and not is_pointer(parent_canonical) then
            -- print('CCCC')
            stmt.deps[cursor_tag(canonical:declaration())] = true
        end
    elseif cur:haskind('TypedefDecl') then
        local typedecl = cur:typedefType():declaration()
        if typedecl:haskind('StructDecl') then
            -- print('crawl StructDecl', typedecl)
            -- nada, any attached structs are crawled extra above
            local fields = 0
            for i, kid in ipairs(typedecl:children()) do
                if kid:haskind('FieldDecl') then
                    -- print('  FieldDecl', kit)
                    fields = fields + 1
                end
            end
            if fields > 0 then
                stmt[struct_dep_mode][cursor_tag(typedecl)] = true
            end
        else
            for i, kid in ipairs(cur:children()) do
                find_deps(kid, cur, struct_ptr_mode, stmt)
            end
        end
    else
        for i, kid in ipairs(cur:children()) do
            find_deps(kid, cur, struct_ptr_mode, stmt)
        end
    end
end

for _, cur in ipairs(tu_cur:children()) do
    if not cur:kind():match('^Macro') 
        and not cur:haskind('InclusionDirective') 
        and not (cur:haskind('FunctionDecl') and cur:isDefinition())
    then
        store_stmt(cur)
    end
end
-- for tag, stmt in pairs(stmts) do
--     print(tag, stmt.kind, stmt.name, stmt.tag, stmt.tag == tag)
--     for _, m in ipairs{'deps', 'delayed_deps'} do
--         for t, _ in pairs(stmt[m]) do
--             print('', m, t)
--         end
--     end
-- end

local to_dump = { }
local visited = { }
local struct_breakers = { }
local function dump(tag, indent)
    indent = indent or ''
    local stmt = stmts[tag]
    print('## '..indent..'dumping', stmt.kind, stmt.name)
    if visited[stmt.tag] == 'temporary' then
        -- if stmt[1] == 'TypedefDecl' then
        --     print('temp typedef inner', stmt.typedef_inner)
        --     print('temp typedef inner kind', stmt.typedef_inner[1])
        --     print('temp typedef inner name', stmt.typedef_inner.name)
        -- end
        if stmt.kind == 'StructDecl' then
            if not struct_breakers[stmt.name] then
                print('# circular struct breaker')
                print('struct '..stmt.name..';')
                struct_breakers[stmt.name] = true
            end
        else
            error('circular! '.. stmt.kind ..' '.. stmt.name)
        end
    end
    if visited[stmt.tag] then return end
    visited[stmt.tag] = 'temporary'
    -- print(indent..'dump', stmt[2])
    for dep, _ in pairs(stmt.deps) do
        -- print(indent..'dump deps', i, d)
        if stmts[dep] and stmts[dep].tag ~= tag then
            dump(dep, indent..'  ')
        end
    end
    for dep, _ in pairs(stmt.delayed_deps) do
        -- print(indent..'dump delayed_deps', d)
        to_dump[#to_dump + 1] = dep
    end
    -- print('# '..stmt.tag)
    print(stmt.extent..';')
    visited[stmt.tag] = true
end

for tag, stmt in pairs(stmts) do
    if false
      or (stmt.kind == 'FunctionDecl' and stmt.name == 'sqlite3_open')
      -- or (stmt.kind == 'FunctionDecl' and stmt.name:match('ev_.*_start'))
      -- or (stmt.kind == 'FunctionDecl' and stmt.name:match('ev_.*_stop'))
      -- or (stmt.kind == 'FunctionDecl' and stmt.name == 'close') 
      -- or (stmt.kind == 'FunctionDecl' and stmt.name == 'read') 
      -- or (stmt.kind == 'FunctionDecl' and stmt.name == 'write') 
      -- or (stmt.kind == 'FunctionDecl' and stmt.name == 'lseek') 
      -- or (stmt.kind == 'StructDecl' and stmt.name == '_IO_FILE') 
    then
    --if stmt.file == '/usr/include/sqlite3.h' then
        to_dump[#to_dump + 1] = stmt.tag
    end
end

io.stdout:write[[
local ffi = require 'ffi'
ffi.cdef[==[
]]
local i = 1
while i <= #to_dump do
    -- print('dump', i, #to_dump, to_dump[i])
    dump(to_dump[i])
    i = i + 1
end
io.stdout:write[[
]==]
]]
