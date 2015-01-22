#!/usr/bin/env luajit

-- Copyright (C) 2014-2015 Brian Downing.  MIT License.

local function tmap(t, f)
    local r = { }
    for i = 1, #t do
        r[#r+1] = f(t[i])
    end
    return r
end

local function tappend(r, ...)
    local ts = {...}
    for _, t in ipairs(ts) do
        for i = 1, #t do
            r[#r+1] = t[i]
        end
    end
    return r
end

local function tjoin(...)
    return tappend({ }, ...)
end

local function noprint() end
local function errprint(...)
    io.stderr:write(table.concat(tmap({...}, tostring), ' ')..'\n')
end
local function errprintf(...)
    io.stderr:write(string.format(...))
end
local dbg = noprint
-- dbg = errprint

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

local function children_attrs(cur)
    local non_attrs, attrs = { }, { }
    for _, kid in ipairs(cur:children()) do
        if kid:kind():match('Attr$') then
            table.insert(attrs, kid)
        else
            table.insert(non_attrs, kid)
        end
    end
    return non_attrs, attrs
end

local function struct_fields(cur)
    local fields = 0
    for i, kid in ipairs(cur:children()) do
        if kid:haskind('FieldDecl') then
            -- dbg('  FieldDecl', kit)
            fields = fields + 1
        end
    end
    return fields
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

function strip_hashes(str)
    repeat
        local old = str
        str = old:gsub('\n#[^\n]*\n', '\n')
    until old == str
    return str
end

local redef_tag = '__LJ_CDEFDB_REDEFINED__'

local stmts = { }
local stmt_idx = 1
local kind_name_map = { }

local struct_dep_mode = 'delayed_deps'
local typedef_ends = { }
local enums = { }
local macros = { }

function haskind_structish(decl)
    return decl:haskind('StructDecl') or decl:haskind('UnionDecl')
end

function store_stmt(cur)
    if not cur:location() then return end

    if haskind_structish(cur) then
        cur = cur:type():declaration()
    end

    local tag = cursor_tag(cur)
    if stmts[tag] then return end

    local realfile, rr1, rc1, _, _, b, e = cur:location()
    local file, pr1, pc1 = cur:presumedLocation()
    if realfile == '???' then return end
    local stmt = {
        name = cur:name(),
        kind = cur:kind(),
        extent = strip_hashes(getExtent(cur:location('offset'))),
        file = file,
        pr1 = pr1, pc1 = pc1,
        tag = tag,
        deps = { },
        delayed_deps = { },
        no_deps = { },
        idx = stmt_idx,
        outside_attrs = { }
    }

    local _, attrs = children_attrs(cur)
    for _, attr in ipairs(attrs) do
        local f, ab, ae = attr:location('offset')
        if not f then
            errprintf('Warning: Likely UNSUPPORTED pragma: %s "%s" %s:%d:%d\n',
                      stmt.kind, stmt.name, file, pr1, pc1)
        elseif ab < b or ae > e then
            table.insert(stmt.outside_attrs, strip_hashes(getExtent(f, ab, ae)))
        end
    end

    if stmt.name:match(redef_tag) then
        stmt.name = stmt.name:gsub(redef_tag, '')
        stmt.extent = stmt.extent:gsub(redef_tag, '')
    end
    local redefined = false
    if stmt.name ~= '' and not cur:haskind('MacroDefinition') then
        local kindname = stmt.kind..','..stmt.name
        if kind_name_map[kindname] then
            local old_tag = kind_name_map[kindname]
            local old_stmt = stmts[old_tag]
            if not cur:name():match(redef_tag) then
                errprintf('Warning: %s "%s" redefined:\n' ..
                              '    Old %s:%d:%d\n' ..
                              '    New %s:%d:%d\n',
                          stmt.kind, stmt.name,
                          old_stmt.file, old_stmt.pr1, old_stmt.pc1,
                          file, pr1, pc1)
            end
            tag = old_tag
            stmt.tag = old_tag
            stmt.idx = old_stmt.idx
            if old_stmt.inner_structish then
                stmts[old_stmt.inner_structish.tag] = stmt
            end
            redefined = true
        end
        kind_name_map[kindname] = tag
    end

    if cur:haskind('MacroDefinition') then
        stmt.extent = stmt.extent:sub(#stmt.name + 1)
        if stmt.extent == ' '..stmt.name then
            dbg('ignore self-defined '..stmt.name, macros[stmt.name])
            macros[stmt.name] = nil
            return
        end
        local _, tokens = cur:_tokens()
        table.remove(tokens, 1)
        stmt.tokens = tokens
        local params = stmt.extent:match('^%(([^)]*)%)')
        stmt.expansion = stmt.extent:match(' (.*)')
        if params then
            stmt.params = { }
            for p in params:gmatch('[^,]+') do
                table.insert(stmt.params, p)
            end
            local ps = #stmt.params
            local ptokens = 2 + (ps > 1 and ps * 2 - 1 or ps)
            for i = 1, ptokens do
                table.remove(stmt.tokens, 1)
            end
        end
        macros[stmt.name] = stmt.tag
        -- don't need more cleanup (more spaces, backslash-newlines)
        -- because clang -E -dD takes care of that
    end

    stmts[tag] = stmt
    if not redefined then
        stmt_idx = stmt_idx + 1
    end
    -- dbg('tag', tag)

    find_deps(cur, nil, struct_dep_mode, stmt)
    -- kill any self dependencies
    stmt.deps[stmt.tag] = nil
    stmt.delayed_deps[stmt.tag] = nil

    --dbg(tag, stmt.kind, stmt.name, stmt.tag, stmt.tag == tag)

    if cur:haskind('TypedefDecl') then
        -- deal with inline-defined structs
        local f, b, e = cur:location('offset')
        local td_starttag = f..','..b
        local td_basetype = base_type(cur:typedefType())
        local decl = td_basetype:declaration()
        local _, kb, ke = decl:location('offset')
        dbg('\ntypedef', f, b, kb, ke, e, decl:kind(), decl:name())
        if haskind_structish(decl) and kb and b <= kb and e >= ke then
            dbg('\ntypedef', stmt.kind, 'inner', f, b, kb, ke, e, decl:name(), struct_fields(decl))
            if decl:name() == '' or struct_fields(decl) == 0 then
                -- eat anon or empty structs defined inside typedefs
                if typedef_ends[td_starttag] then
                    error("UNSUPOPRTED: multiply-defined typedefs for " ..
                          "anonymous structs (for typedef "..cur:name()..")!")
                end
                local old_stmt = stmts[cursor_tag(decl)]
                stmt.idx = old_stmt.idx
                stmt_idx = stmt_idx - 1
                for k, v in pairs(old_stmt.deps) do
                    stmt.deps[k] = v
                end
                for k, v in pairs(old_stmt.delayed_deps) do
                    stmt.delayed_deps[k] = v
                end
                stmt.inner_structish = old_stmt
                stmt.outside_attrs = tjoin(old_stmt.outside_attrs,
                                           stmt.outside_attrs)
                stmts[old_stmt.tag] = stmt
            else
                -- generate a new typedef referencing out the struct
                -- by name; this avoid several kinds of circular
                -- dependencies that are hard to work around otherwise
                local orig = getExtent(f, b, e)
                local struct = getExtent(f, kb, ke)
                local pre = orig:sub(1, kb - b)
                local post = orig:sub(ke - b + 1, e - b)
                local old_e = typedef_ends[td_starttag]
                if old_e then
                    post = orig
                        :sub(old_e - b + 1, e - b)
                        :match('^%s*,%s*(%s.*)$')
                end
                stmt.extent = '/* generated */ ' .. strip_hashes(pre .. tostring(td_basetype) .. post)
                dbg('typedef', tag, 'decl', cursor_tag(decl), stmt.extent)
            end
            typedef_ends[td_starttag] = e
        end
    end

    if #stmt.outside_attrs > 0 then
        stmt.extent = stmt.extent
            .. ' /* fabricated */ __attribute__ (('
            .. table.concat(stmt.outside_attrs, ',') .. '))'
    end
end

function find_deps(cur, parent, struct_ptr_mode, stmt)
    if cur:haskind('EnumConstantDecl') then
        dbg('EnumConstantDecl', cur:name())
        enums[cur:name()] = stmt.tag
    end
    if cur:haskind('DeclRefExpr') then
        dbg('DeclRefExpr', cur:name())
        if enums[cur:name()] then
            stmt.deps[enums[cur:name()]] = true
        else
            dbg(cur:name(), 'used before defined')
        end
    end
    if cur:haskind('ParmDecl') then
        -- structs in parameter lists are local, so they need to be
        -- defined (or at least forward-declared) first
        -- dbg('ParmDecl', cur, cursor_tag(cur))
        for i, kid in ipairs(cur:children()) do
            find_deps(kid, cur, 'deps', stmt)
        end
    elseif cur:haskind('TypeRef') then
        local typedecl = cur:type():declaration()
        local mode = 'deps'
        local parent_type = parent:type()
        -- dbg(cur:type(), cur:type():declaration(), cursor_tag(cur:type():declaration()))
        if parent:haskind('FunctionDecl') then
            parent_type = parent:resultType()
        end
        if haskind_structish(typedecl) and is_pointer(parent_type) then
            mode = struct_ptr_mode
        end
        -- dbg(mode, cursor_tag(typedecl))
        stmt[mode][cursor_tag(typedecl)] = true
        local canonical = cur:type():canonical()
        local parent_canonical = parent_type:canonical()
        -- dbg('CANONICAL', cur:type(), cur:type():canonical(), parent_type, parent_canonical)
        if haskind_structish(canonical:declaration()) and not is_pointer(parent_canonical) then
            -- dbg('CCCC')
            stmt.deps[cursor_tag(canonical:declaration())] = true
        end
    elseif cur:haskind('TypedefDecl') then
        local typedecl = base_type(cur:typedefType()):declaration()
        if haskind_structish(typedecl) then
            -- dbg('crawl (Struct/Union)Decl', typedecl)
            -- skip first child (the typeref), any attached structs
            -- are crawled extra above; otherwise we get an
            -- unneccessarily-strong dependency on the struct
            for i, kid in ipairs(children_attrs(cur)) do
                if i == 1 then
                    stmt[struct_dep_mode][cursor_tag(typedecl)] = true
                else
                    find_deps(kid, cur, struct_ptr_mode, stmt)
                end
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
    if not cur:haskind('MacroExpansion') 
        and not cur:haskind('InclusionDirective') 
        and not (cur:haskind('FunctionDecl') and cur:isDefinition())
    then
        store_stmt(cur)
    end
end

local consts = { }
local test_num = 0
local function const_test(token, indent)
    indent = indent or ''
    if consts[token] == 'testing' then
        dbg(indent..'const_test', token, 'recursed, therefore false')
        consts[token] = false
        return consts[token]
    end
    if consts[token] ~= nil then
        dbg(indent..'const_test', token, 'cached', not not consts[token])
        return consts[token]
    end
    dbg(indent..'const_test', token)
    local tag = macros[token]
    if not tag then return consts[token] end
    local stmt = stmts[tag]
    consts[token] = 'testing'
    dbg(indent..'  <'..stmt.extent..'>')
    if stmt.params then
        dbg(indent..'  false due to unhandled params')
        consts[token] = false
    else
        local deps = { }
        local tokens = tmap(stmt.tokens, function(x) return x.extent end)
        for i, t in ipairs(tokens) do
            if macros[t] then
                table.insert(deps, macros[t])
            end
            if enums[t] then
                table.insert(deps, enums[t])
                dbg(indent..'  is enum', t, 'replacing with 1')
                tokens[i] = '1'
            end
            const_test(t, indent..'  ')
            if consts[t] == false then
                dbg(indent..'  false due to non-const token', t)
                consts[token] = false
                return consts[token]
            end
            if consts[t] then
                tokens[i] = consts[t].test_sym
            end
        end
        test_num = test_num + 1
        local test_sym = string.format('__TEST_%d', test_num);
        local test = string.format('enum { %s = (%s) };',
                                   test_sym, table.concat(tokens, ' '))
        dbg(indent..'  test:', test)
        local is_const, err = pcall(function ()
            require'ffi'.cdef(test)
        end)
        if is_const then
            dbg(indent..'  true due to successful test')
            consts[token] = { deps = deps, test_sym = test_sym }
        else
            dbg(indent..'  false due to failed test', err)
            consts[token] = false
        end
    end
    return consts[token]
end

for m, tag in pairs(macros) do
    local stmt = stmts[tag]
    local c = const_test(m)
    if c then
        for _, d in ipairs(c.deps) do
            stmt.deps[d] = true
        end
    end
end

if dbg ~= noprint then
    for tag, stmt in pairs(stmts) do
        print(stmt.idx, tag, stmt.kind, stmt.name, stmt.tag, stmt.tag == tag)
        for _, m in ipairs{'deps', 'delayed_deps'} do
            for t, _ in pairs(stmt[m]) do
                print('', m, t)
            end
        end
    end
end

local function to_c_string_literal(str)
    return '"' .. str
        :gsub('\\', '\\\\')
        :gsub('"', '\\"')
        :gsub('\n', '\\n"\n"')
        .. '\\0"'
end

local dns = { -1 }
local dns_i = 1
local dnmap = { ['-1'] = 0 }
local function intern_dn(dn)
    local key = table.concat(dn, ',')
    if not dnmap[key] then
        for i = 1, #dn do
            dns[#dns + 1] = dn[i]
        end
        dnmap[key] = dns_i
        dns_i = dns_i + #dn
    end
    return dnmap[key]
end
local strings = { }
local strings_n = { }
local strings_i = 0
local stringmap = { }
local function intern_string(str)
    str = str
    if not stringmap[str] then
        strings[#strings + 1] = str
        stringmap[str] = strings_i
        strings_n[#strings_n + 1] = strings_i
        strings_i = strings_i + #str + 1
    end
    return stringmap[str]
end

local stmt_i = { }
for tag, stmt in pairs(stmts) do
    local deps, delayed_deps = { }, { }
    for tag, _ in pairs(stmt.deps) do
        if stmts[tag] then
            deps[#deps + 1] = stmts[tag].idx - 1
        end
    end
    for tag, _ in pairs(stmt.delayed_deps) do
        if stmts[tag] then
            delayed_deps[#delayed_deps + 1] = stmts[tag].idx - 1
        end
    end
    table.sort(deps)
    table.sort(delayed_deps)
    deps[#deps + 1] = -1
    delayed_deps[#delayed_deps + 1] = -1
    stmt.deps_dn = intern_dn(deps)
    stmt.delayed_deps_dn = intern_dn(delayed_deps)
    stmt_i[stmt.idx] = stmt
end

local constants = { }
for e, tag in pairs(enums) do
    constants[e] = stmts[tag]
end
for m, tag in pairs(macros) do
    if not constants[m] and consts[m] then
        constants[m] = stmts[tag]
    end
end
local constants_i = { }
for c, stmt in pairs(constants) do
    table.insert(constants_i, {
        name = c,
        stmt = stmt
    })
end
table.sort(constants_i, function (a, b) return a.name < b.name end)
for _, c in ipairs(constants_i) do
    -- so it's sorted/consistent
    c.name_i = intern_string(c.name)
end

io.stdout:write('const int cdefdb_num_stmts = '..#stmt_i..';\n')
io.stdout:write([[
const struct {
    int name;
    int kind;
    int extent;
    int file;
    int deps;
    int delayed_deps;
} cdefdb_stmts[] = {]], '\n')
for i, stmt in ipairs(stmt_i) do
    local t = {
        intern_string(stmt.name),
        intern_string(stmt.kind),
        intern_string(stmt.extent),
        intern_string(stmt.file),
        stmt.deps_dn,
        stmt.delayed_deps_dn,
    }
    io.stdout:write('    /* '..(i-1)..' */ { '..table.concat(t, ', ')..' },\n')
end
io.stdout:write('};\n')

io.stdout:write('const char *cdefdb_stmt_strings =')
for i, str in ipairs(strings) do
    io.stdout:write('\n    /* '..strings_n[i]..' */ ', to_c_string_literal(str))
end
io.stdout:write(';\n')

local function emit_int_array(name, t, key)
    key = key or function (e) return e end
    io.stdout:write('const int '..name..'[] = {')
    for i = 1, #t do
        if (i - 1) % 8 == 0 then
            io.stdout:write('\n    /* '..(i - 1)..' */')
        end
        io.stdout:write(' '..key(t[i])..',')
    end
    io.stdout:write('\n};\n')
end
emit_int_array('cdefdb_stmt_deps', dns)

io.stdout:write('const int cdefdb_num_constants = '..#constants_i..';\n')
io.stdout:write([[
const struct {
    int name;
    int stmt;
} cdefdb_constants_idx[] = {]], '\n')
for i, c in ipairs(constants_i) do
    io.stdout:write(string.format('    /* %d */ { %d, %d }, /* %s */\n',
                                  i-1, c.name_i, c.stmt.idx-1, c.name))
end
io.stdout:write('};\n')

local function sort3keys(a, b, c)
    return function (x, y)
        if x[a] == y[a] then
            if x[b] == y[b] then
                return x[c] < y[c]
            end
            return x[b] < y[b]
        end
        return x[a] < y[a]
    end
end
local function emit_stmt_idx(a, b, c)
    table.sort(stmt_i, sort3keys(a, b, c))
    emit_int_array(string.format('cdefdb_stmt_index_%s_%s_%s',
                                 a, b, c),
                   stmt_i,
                   function (stmt) return stmt.idx-1 end)
end
emit_stmt_idx('file', 'kind', 'name')
emit_stmt_idx('file', 'name', 'kind')
emit_stmt_idx('kind', 'file', 'name')
emit_stmt_idx('kind', 'name', 'file')
emit_stmt_idx('name', 'file', 'kind')
emit_stmt_idx('name', 'kind', 'file')
