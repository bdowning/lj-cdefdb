-- Copyright (C) 2014-2015 Brian Downing.  MIT License.

local ffi = require 'ffi'

local cdef, C, ffi_string, floor, min =
    ffi.cdef, ffi.C, ffi.string, math.floor, math.min

local dbg = function () end
-- dbg = print

cdef[[
struct cdefdb_header {
    int32_t num_stmts;
    int32_t num_constants;
    int32_t stmts_offset;
    int32_t stmt_deps_offset;
    int32_t constants_idx_offset;
    int32_t file_kind_name_idx_offset;
    int32_t file_name_kind_idx_offset;
    int32_t kind_file_name_idx_offset;
    int32_t kind_name_file_idx_offset;
    int32_t name_file_kind_idx_offset;
    int32_t name_kind_file_idx_offset;
    int32_t strings_offset;
};
struct cdefdb_stmts_t {
    int32_t name;
    int32_t kind;
    int32_t extent;
    int32_t file;
    int32_t deps;
    int32_t delayed_deps;
};
struct cdefdb_constants_idx_t {
    int32_t name;
    int32_t stmt;
};

int open(const char *pathname, int flags);
void *mmap(void *addr, size_t length, int prot, int flags,
           int fd, int64_t offset);
int close(int fd);

enum {
    O_RDONLY = 0,
    PROT_READ = 1,
    MAP_SHARED = 1,
};
]]

local db_names = {...}

local dbs = { }
for _, name in ipairs(db_names) do
    local fh = assert(io.open(name, 'r'))
    local size = fh:seek('end')
    fh:close()
    local fd = C.open(name, C.O_RDONLY)
    assert(fd >= 0)
    local m = C.mmap(nil, size, C.PROT_READ, C.MAP_SHARED, fd, 0)
    assert(m ~= ffi.cast('void *', -1))
    C.close(fd)
    local db = {
        map_base = ffi.cast('char *', m),
        size = size,
        header = ffi.cast('struct cdefdb_header *', m)
    }
    local function db_add(name, ctype)
        db[name] = ffi.cast(ctype, db.map_base + db.header[name..'_offset'])
    end
    db_add('stmts', 'struct cdefdb_stmts_t *')
    db_add('stmt_deps', 'int32_t *')
    db_add('constants_idx', 'struct cdefdb_constants_idx_t *')
    db_add('strings', 'char *')
    dbs[name] = db
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
        if not stmts[stmt.tag] then
            -- print('name', stmt.name)
            -- print('kind', stmt.kind)
            -- print('extent', stmt.extent)
            -- print('file', stmt.file)
            -- print('db_name', stmt.db_name)
            -- print('deps')
            -- for _, dep in ipairs(stmt.deps) do
            --     print('', dep)
            -- end
            -- print('delayed_deps')
            -- for _, dep in ipairs(stmt.delayed_deps) do
            --     print('', dep)
            -- end
            stmts[stmt.tag] = stmt
            stmt_idx = stmt_idx + 1
        end
    end

    for i = 0, db.header.num_constants - 1 do
        local name = get_string(db, db.constants_idx[i].name)
        if not constants[name] then
            constants[name] = stmts[get_tag(db, db.constants_idx[i].stmt)]
        end
    end
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
table.sort(constants_i, function (a, b) return a.name < b.name end)
for _, c in ipairs(constants_i) do
    -- so it's sorted/consistent
    c.name_i = intern_string(c.name)
end

local buf = { }
buf.header = ffi.new('struct cdefdb_header')
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

local slen = 0
for i, str in ipairs(strings) do
    slen = slen + #str + 1
end
buf.strings = ffi.new('char [?]', slen)
slen = 0
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

local function emit(f, o, len)
    assert(f:write(ffi.string(o, len or ffi.sizeof(o))))
end

local f = assert(io.open('cdef.db', 'w'))
emit(f, buf.header)
emit(f, buf.stmts)
emit(f, buf.stmt_deps)
emit(f, buf.constants_idx)
emit(f, buf.file_kind_name_idx)
emit(f, buf.file_name_kind_idx)
emit(f, buf.kind_file_name_idx)
emit(f, buf.kind_name_file_idx)
emit(f, buf.name_file_kind_idx)
emit(f, buf.name_kind_file_idx)
emit(f, buf.strings)
f:close()
