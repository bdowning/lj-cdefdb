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
