#!/usr/bin/env luajit

-- Copyright (C) 2014-2015 Brian Downing.  MIT License.

local arg = arg

assert(arg[1], "Usage: "..arg[0].." <filename> ...")

local cl = require("ljclang")

arg[0] = nil
local tu = cl.createIndex():parse(arg)

if (tu == nil) then
    print('TU is nil')
    os.exit(1)
end

local predefined = {
    __gnuc_va_list = true,
    va_list = true,
    ptrdiff_t = true,
    size_t = true,
    wchar_t = true,
    int8_t = true,
    int16_t = true,
    int32_t = true,
    int64_t = true,
    uint8_t = true,
    uint16_t = true,
    uint32_t = true,
    uint64_t = true,
    intptr_t = true,
    uintptr_t = true,
}

local syms = {
    functions = { },
    variables = { },
    structs = { },
    unions = { },
    typedefs = { },
    constants = { },
    unemitted = 0
}

local function emit_foo(kind)
    local to_emit = { }
    for sym, state in pairs(syms[kind]) do
        if state then
            table.insert(to_emit, sym)
            syms[kind][sym] = false
        end
    end
    table.sort(to_emit)
    if #to_emit > 0 then
        io.stdout:write('    '..kind..' = {\n')
        for _, sym in ipairs(to_emit) do
            io.stdout:write("        '"..sym.."',\n")
        end
        io.stdout:write('    },\n')
    end
end
local function emit()
    if syms.unemitted > 0 then
        io.stdout:write("require 'cdef' {\n")
        emit_foo('functions')
        emit_foo('variables')
        emit_foo('structs')
        emit_foo('unions')
        emit_foo('typedefs')
        emit_foo('constants')
        io.stdout:write("}\n")
        syms.unemitted = 0
    end
end
local function add_sym(kind, sym)
    if sym ~= '' and syms[kind][sym] == nil then
        syms[kind][sym] = true
        syms.unemitted = syms.unemitted + 1
    end
end

for _, stmt in ipairs(tu:cursor():children()) do
    if stmt:haskind("FunctionDecl") then
        if stmt:name() == '__emit__' then
            emit()
        else
            add_sym('functions', stmt:name())
        end
    elseif stmt:haskind("VarDecl") then
        add_sym('variables', stmt:name())
    elseif stmt:haskind("StructDecl") then
        add_sym('structs', stmt:name())
    elseif stmt:haskind("UnionDecl") then
        add_sym('unions', stmt:name())
    elseif stmt:haskind("TypedefDecl") then
        if not predefined[stmt:name()] then
            add_sym('typedefs', stmt:name())
        end
    elseif stmt:haskind("EnumDecl") then
        for _, field in ipairs(stmt:children()) do
            if field:haskind("EnumConstantDecl") then
                add_sym('constants', field:name())
            end
        end
    else
        print('-- unknown', stmt:kind(), stmt:name())
    end
end

emit()
