#!/usr/bin/env luajit

local arg = arg

local assert = assert
local print = print
local require = require
local tostring = tostring

local string = require("string")
local os = require("os")

----------

assert(arg[1], "Usage: "..arg[0].." <filename> ...")

local cl = require("ljclang")

arg[0] = nil
local tu = cl.createIndex():parse(arg, {"DetailedPreprocessingRecord"})

-- NOTE: we don't need to keep the Index_t reference around, test this.
collectgarbage()

if (tu == nil) then
    print('TU is nil')
    os.exit(1)
end

local cur = tu:cursor()
assert(cur==cur)
assert(cur ~= nil)
assert(cur:kindnum() == "CXCursor_TranslationUnit")
assert(cur:haskind("TranslationUnit"))

-- print("TU: "..cur:name()..", "..cur:displayName())
-- local fn = arg[1]:gsub(".*/","")
-- print(fn.." in TU: "..tu:file(fn)..", "..tu:file(arg[1]))

-- local diags = tu:diagnostics()
-- for i=1,#diags do
--     local d = diags[i]
--     print("diag "..i..": "..d.category..", "..d.text)
-- end

-- local V = cl.ChildVisitResult

-- local ourtab = {}

-- local visitor = cl.regCursorVisitor(
-- function(cur, parent)
--     ourtab[#ourtab+1] = cl.Cursor(cur)

--     if (cur:haskind("EnumConstantDecl")) then
--         print(string.format("%s: %d", cur:name(), cur:enumval()))
--     end

--     local isdef = (cur:haskind("FunctionDecl")) and cur:isDefinition()

-- --    print(string.format("[%3d] %50s <- %s", tonumber(cur:kindnum()), tostring(cur), tostring(parent)))
--     print(string.format("%3d [%12s%s] %50s <- %s %s", #ourtab, cur:kind(),
--                         isdef and " (def)" or "", tostring(cur), tostring(parent), tostring(cur:type())))

--     if (cur:haskind("CXXMethod")) then
--         print("("..cur:access()..")")
--     end

--     return V.Continue
-- end)

-- cur:children(visitor)
if false then
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

local stmts = { }
local stmts_by_tag = { }

local function cursor_tag(cur)
    -- local f, b, e = cur:location('offset')
    -- return string.format('%s:%d:%d', f or '?', b or 0, e or 0)
    local f, r1, c1, r2, c2 = cur:location()
    return string.format('%s:%d:%d:%d:%d', f or '?', r1 or 0, c1 or 0, r2 or 0, c2 or 0)
end

function store_stmts(tu_cursor)
    local curs = tu_cursor:children()
    local typedef_inner
    for i, cur in ipairs(curs) do
        if not cur:kind():match('^Macro') and not cur:haskind('InclusionDirective') and not (cur:haskind('FunctionDecl') and cur:isDefinition()) then
            local f, b, e = cur:location()
            local tag = cursor_tag(cur)
            local next_cur = curs[i + 1]
            local skip = not f
            if b and next_cur and next_cur:haskind('TypedefDecl') then
                local next_kids = next_cur:children()
                if next_kids[1] then
                    local _, nb, ne = next_kids[1]:location()
                    if nb and nb <= b and ne >= e then
                        typedef_inner = cur
                        skip = true
                    end
                end
            end
            if not skip then
                local file = cur:presumedLocation()
                local slot = #stmts + 1
                local stmt = { cur:kind(), getExtent(cur:location('offset')), name = cur:name(),
                               file = file, tag = tag,
                               deps = { }, delayed_deps = { } }
                local deps = { deps = { }, delayed_deps = { } }
                local stack = { }
                find_deps(cur, stack, 1, deps, 'delayed_deps')
                for m, d in pairs(deps) do
                    for t, _ in pairs(d) do
                        -- print(tag, m, t)
                        if t ~= tag then
                            stmt[m][#stmt[m] + 1] = t
                        end
                    end
                end
                stmts[slot] = stmt
                stmts_by_tag[tag] = slot
                if typedef_inner then
                    local itag = cursor_tag(typedef_inner)
                    stmt.typedef_inner = { typedef_inner:kind(), name = typedef_inner:name() }
                    stmts_by_tag[itag] = slot
                    typedef_inner = nil
                end
            end
        end
    end
end

function find_deps(cur, stack, level, deps, delayed_mode)
    -- print('find_deps', cur:kind(), cur, level, cursor_tag(cur))
    stack[level] = cur
    if not cur:location() then
        -- skip
    elseif cur:haskind('FunctionDecl') then
        for i, kid in ipairs(cur:children()) do
            find_deps(kid, stack, level + 1, deps, 'deps')
        end
    -- elseif cur:haskind('FieldDecl') then
    --     local type = cur:type()
    --     local ctype = type:canonical()
    --     -- print(type, type:kindnum())
    --     -- print(ctype, ctype:kindnum())
    --     if type:haskind('Typedef') then
    --         local decl = type:declaration()
    --         if decl:location() then
    --             deps.deps[cursor_tag(decl)] = true
    --         end
    --     end
    --     if ctype:haskind('Record') then
    --         local decl = ctype:declaration()
    --         if decl:location() then
    --             deps.deps[cursor_tag(decl)] = true
    --         end
    --     else
    --         for i, kid in ipairs(cur:children()) do
    --             find_deps(kid, stack, level + 1, deps, delayed_mode)
    --         end
    --     end
    elseif cur:haskind('TypedefDecl') then
        -- print('typedef', cur, 'type tag', cursor_tag(cur:typedefType():declaration()))
        local decl = cur:typedefType():declaration()
        local mode = 'deps'
        if decl:haskind('StructDecl') then
            mode = delayed_mode
        end
        deps[mode][cursor_tag(decl)] = true
        for i, kid in ipairs(cur:children()) do
            find_deps(kid, stack, level + 1, deps, delayed_mode)
        end
    elseif cur:haskind('TypeRef') then
        local mode = 'deps'
        local type = cur:type()
        if type:haskind('Record') then
            -- print('type:kind', type:kindnum())
            -- print('stack[level - 1]:kind', stack[level - 1]:kind(), ':type:kind', stack[level - 1]:type():kindnum())
            if stack[level - 1]:type():haskind('Pointer') then
                mode = delayed_mode
            end
        end
        -- if level == 2 and stack[level - 1]:haskind('TypedefDecl') then
        --     mode = 'delayed_deps'
        -- end
        -- if stack[level - 1]:type()
        local decl = cur:type():declaration()
        if decl:location() then
            deps[mode][cursor_tag(decl)] = true
        end
    else
        for i, kid in ipairs(cur:children()) do
            find_deps(kid, stack, level + 1, deps, delayed_mode)
        end
    end
    stack[level] = nil
end

store_stmts(cur)

local to_dump = { }
for i, s in ipairs(stmts) do
    -- print(s[1], s.name)
    if s[2]:match(
        '^struct foffo {'
        --'^typedef struct .* CXIdxEntityInfo$'
        --'struct ev_loop.*ev_default_loop%s*%('
        --'^struct ev_loop%s*{'
    ) or (s[1] == 'FunctionDecl' and s.name == 'sqlite3_vfs_register') then
        local slot = stmts_by_tag[s.tag]
        if slot then
            to_dump[#to_dump + 1] = slot
        end
    end
end

local visited = { }
local function dump(slot, indent)
    indent = indent or ''
    local stmt = stmts[slot]
    local cur = stmt.tag
    -- print(indent..'dumpin', stmt[1], stmt.name)
    if visited[slot] == 'temporary' then
        -- if stmt[1] == 'TypedefDecl' then
        --     print('temp typedef inner', stmt.typedef_inner)
        --     print('temp typedef inner kind', stmt.typedef_inner[1])
        --     print('temp typedef inner name', stmt.typedef_inner.name)
        -- end
        if stmt[1] == 'TypedefDecl' and stmt.typedef_inner and stmt.typedef_inner[1] == 'StructDecl' then
            print('# circular struct breaker (in typedef)')
            print('struct '..stmt.typedef_inner.name..';')
        elseif stmt[1] == 'StructDecl' then
            print('# circular struct breaker')
            print('struct '..stmt.name..';')
        else
            error('circular! '.. stmt[1] ..' '.. stmt.name)
        end
    end
    if visited[slot] then return end
    visited[slot] = 'temporary'
    if not slot then
        print('# null stmt for', cur)
        return
    end
    -- print(indent..'dump', stmt[2])
    for i, d in ipairs(stmt.deps) do
        -- print(indent..'dump deps', i, d)
        if stmts_by_tag[d] then
            dump(stmts_by_tag[d], indent..'  ')
        end
    end
    for i, d in ipairs(stmt.delayed_deps) do
        -- print(indent..'dump delayed_deps', d)
        if stmts_by_tag[d] then
            table.insert(to_dump, stmts_by_tag[d])
        end
    end
    print('# '..cur)
    print(stmt[2]..';\n')
    visited[slot] = true
end

io.stdout:write[[
local ffi = require 'ffi'
ffi.cdef[==[
]]
local i = 1
while i <= #to_dump do
    -- print('dump', i, #to_dump)
    dump(to_dump[i])
    i = i + 1
end
io.stdout:write[[
]==]
]]

os.exit(0)
end
function recurse(cur, indent, visited)
    if cur:haskind("MacroExpansion") then
        return
    end
    indent = indent or ''
    local f, b, e = cur:location('offset')
    local tag = string.format('%s:%d:%d', f or '?', b or 0, e or 0)
    if visited then
        if visited[tag] then
            print(indent..'CYCLE')
            return
        end
        visited[tag] = true
    end
    local isdef = (cur:haskind("FunctionDecl")) and cur:isDefinition()
    local file, row, col = cur:presumedLocation()
    local type = cur:type()
    print(string.format("%s[%12s%s] %50s <- %s <%s> (%s:%d:%d - %s)", indent, cur:kind(),
                        isdef and " (def)" or "", tostring(cur), tostring(type), type and tonumber(type:kindnum()),
                        file or '?', row or 0, col or 0, tag))
    if cur:haskind("TypedefDecl") then
        local tdtype = cur:typedefType()
        local name = tdtype:name()
        local ptr, arr = name:match('^[^*]*([^[]*)(%[.*)')
        local pre, post = '', ''
        while true do
            print(string.format("%sTypedef type: %s <%s>", indent..'  ', tdtype, tonumber(tdtype:kindnum())))
            print('postfix', ptr, arr)
            if tdtype:haskind('ConstantArray') then
                post = post .. '['..tdtype:arraySize()..']'
                tdtype = tdtype:arrayElementType()
            elseif tdtype:haskind('Pointer') then
                local ptr = '*'
                if tdtype:isConstQualified() then
                    ptr = ptr .. 'const '
                end
                pre = ptr .. pre
                tdtype = tdtype:pointee()
            else
                break
            end
        end
        local typedecl = tdtype:declaration()
        if typedecl:haskind('StructDecl') then
            if typedecl:name() ~= '' then
                print('typedef struct '..typedecl:name()..' '..(ptr or '')..cur:name()..(arr or '')..';')
            end
        end
        if not visited then
            recurse(tdtype:declaration(), indent .. '  TYPEDEFTYPE-> ', { [tag] = true })
        end
    end
    if cur:haskind("MacroDefinition") then
        local indent = indent..'  '
        local toks = cur:_tokens()
        if toks then
            for k, v in pairs(toks) do
                print(string.format("%s%s: %s", indent, k, v))
            end
        end
    end
    if cur:haskind("TypeRef") and not visited then
        local visited = { [tag] = true }
        recurse(cur:type():declaration(), indent .. '  TYPE-> ', visited)
    end
    local kids = cur:children()
    for i, k in ipairs(kids) do
        recurse(k, indent .. '  ', visited)
    end
end

recurse(cur)
