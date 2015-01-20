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
    local f, b, e = cur:location('offset')
    return string.format('%s:%d:%d', f or '?', b or 0, e or 0)
end

function store_stmts(tu_cursor)
    local curs = tu_cursor:children()
    local extra_tag
    for i, cur in ipairs(curs) do
        if not cur:kind():match('^Macro') and not cur:haskind('InclusionDirective') and not (cur:haskind('FunctionDecl') and cur:isDefinition()) then
            local tag = cursor_tag(cur)
            local next_cur = curs[i + 1]
            local skip = false
            if next_cur and next_cur:haskind('TypedefDecl') then
                local next_kids = next_cur:children()
                if next_kids[1] then
                    local next_kid_tag = cursor_tag(next_kids[1])
                    if next_kid_tag == tag then
                        extra_tag = tag
                        skip = true
                    end
                end
            end
            if not skip then
                local file = cur:presumedLocation()
                local slot = #stmts + 1
                local stmt = { cur:kind(), getExtent(cur:location('offset')), file = file, tag = tag, deps = { } }
                local deps = { }
                find_deps(cur, deps)
                for t, _ in pairs(deps) do
                    if t ~= tag then
                        stmt.deps[#stmt.deps + 1] = t
                    end
                end
                stmts[slot] = stmt
                stmts_by_tag[tag] = slot
                if extra_tag then
                    stmts_by_tag[extra_tag] = slot
                    extra_tag = nil
                end
            end
        end
    end
end

function find_deps(cur, deps)
    if cur:haskind('TypeRef') then
        local decl = cur:type():declaration()
        deps[cursor_tag(decl)] = true
    else
        for i, kid in ipairs(cur:children()) do
            find_deps(kid, deps)
        end
    end
end

store_stmts(cur)

local to_dump = { }
for i, s in ipairs(stmts) do
    if s[2]:match(
        'struct ev_loop.*ev_default_loop%s*%('
        --'^struct ev_loop%s*{'
    ) or s.file == '/usr/include/sqlite3.h' then
        to_dump[#to_dump + 1] = s.tag
    end
end

local visited = { }
local function dump(cur)
    local slot = stmts_by_tag[cur]
    if visited[slot] then return end
    visited[slot] = true
    if not slot then
        print('null stmt for', cur)
        return
    end
    local stmt = stmts[slot]
    for i, d in ipairs(stmt.deps) do
        dump(d)
    end
    print('#'..cur)
    print(stmt[2]..';')
end

io.stdout:write[[
local ffi = require 'ffi'
ffi.cdef[==[
]]
for i, tag in ipairs(to_dump) do
    dump(tag)
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
    print(string.format("%s[%12s%s] %50s <- %s (%s:%d:%d - %s)", indent, cur:kind(),
                        isdef and " (def)" or "", tostring(cur), tostring(cur:type()),
                        file or '?', row or 0, col or 0, tag))
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
