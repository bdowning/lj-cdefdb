require 'cdefdb.cdefs'

local ffi = require 'ffi'

local function cdefdb_write(fh, stmts, constants)
    local stmt_i = { }
    for _, stmt in pairs(stmts) do
        stmt_i[stmt.idx] = stmt
    end
    local constants_i = { }
    for c, stmt in pairs(constants) do
        table.insert(constants_i, {
            name = c,
            stmt = stmt
        })
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

    table.sort(constants_i, function (a, b) return a.name < b.name end)
    for _, c in ipairs(constants_i) do
        -- so it's sorted/consistent
        c.name_i = intern_string(c.name)
    end

    local buf = { }
    buf.header = ffi.new('struct cdefdb_header')
    ffi.copy(buf.header.id, 'cdefdb 1.0.0')
    buf.header.num_stmts = #stmt_i
    buf.stmts = ffi.new('struct cdefdb_stmts_t [?]', #stmt_i)
    for i, stmt in ipairs(stmt_i) do
        buf.stmts[i-1].name = intern_string(stmt.name)
        buf.stmts[i-1].kind = intern_string(stmt.kind)
        buf.stmts[i-1].extent = intern_string(stmt.extent)
        buf.stmts[i-1].file = intern_string(stmt.file)

        for _, dep_type in ipairs{'deps', 'delayed_deps'} do
            local deps = { }
            for tag, _ in pairs(stmt[dep_type]) do
                if stmts[tag] then
                    deps[#deps + 1] = stmts[tag].idx - 1
                end
            end
            table.sort(deps)
            deps[#deps + 1] = -1
            buf.stmts[i-1][dep_type] = intern_dn(deps)
        end
    end

    function make_int32_array(t, key)
        key = key or function (e) return e end
        local buf = ffi.new('int32_t [?]', #t)
        for i = 1, #t do
            buf[i-1] = key(t[i])
        end
        return buf
    end
    buf.stmt_deps = make_int32_array(dns)

    buf.header.num_constants = #constants_i
    buf.constants_idx = ffi.new('struct cdefdb_constants_idx_t [?]', #constants_i)
    for i, c in ipairs(constants_i) do
        buf.constants_idx[i-1].name = c.name_i
        buf.constants_idx[i-1].stmt = c.stmt.idx - 1
    end

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
    local function make_stmt_idx(a, b, c)
        table.sort(stmt_i, sort3keys(a, b, c))
        return make_int32_array(stmt_i,
                                function (stmt) return stmt.idx-1 end)
    end
    buf.file_kind_name_idx = make_stmt_idx('file', 'kind', 'name')
    buf.file_name_kind_idx = make_stmt_idx('file', 'name', 'kind')
    buf.kind_file_name_idx = make_stmt_idx('kind', 'file', 'name')
    buf.kind_name_file_idx = make_stmt_idx('kind', 'name', 'file')
    buf.name_file_kind_idx = make_stmt_idx('name', 'file', 'kind')
    buf.name_kind_file_idx = make_stmt_idx('name', 'kind', 'file')

    buf.strings = ffi.new('char [?]', strings_i)
    local slen = 0
    for i, str in ipairs(strings) do
        ffi.copy(buf.strings + slen, ffi.cast('char *', str), #str + 1)
        slen = slen + #str + 1
    end

    local o = ffi.sizeof(buf.header)
    local function header_offset(name)
        buf.header[name..'_offset'] = o
        o = o + ffi.sizeof(buf[name])
    end
    header_offset('stmts')
    header_offset('stmt_deps')
    header_offset('constants_idx')
    header_offset('file_kind_name_idx')
    header_offset('file_name_kind_idx')
    header_offset('kind_file_name_idx')
    header_offset('kind_name_file_idx')
    header_offset('name_file_kind_idx')
    header_offset('name_kind_file_idx')
    header_offset('strings')

    local function emit(o, len)
        assert(fh:write(ffi.string(o, len or ffi.sizeof(o))))
    end

    emit(buf.header)
    emit(buf.stmts)
    emit(buf.stmt_deps)
    emit(buf.constants_idx)
    emit(buf.file_kind_name_idx)
    emit(buf.file_name_kind_idx)
    emit(buf.kind_file_name_idx)
    emit(buf.kind_name_file_idx)
    emit(buf.name_file_kind_idx)
    emit(buf.name_kind_file_idx)
    emit(buf.strings)
end

return cdefdb_write
