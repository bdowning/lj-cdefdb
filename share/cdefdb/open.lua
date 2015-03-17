require 'cdefdb.cdefs'

local ffi = require 'ffi'
local C = ffi.C

local function cdefdb_open(filename, size)
    local db = { }

    if not size then
        local fh = assert(io.open(filename, 'r'))
        size = fh:seek('end')
        fh:close()
    end

    local fd = C.cdefdb_open(filename,
                             C.CDEFDB_O_RDONLY)
    assert(fd >= 0)
    local m = C.cdefdb_mmap(nil, size,
                            C.CDEFDB_PROT_READ,
                            C.CDEFDB_MAP_SHARED,
                            fd, 0)
    assert(m ~= ffi.cast('void *', -1), ffi.errno())
    C.cdefdb_close(fd)

    db.map_base = ffi.cast('char *', m)
    db.size = size
    db.header = ffi.cast('struct cdefdb_header *', db.map_base)

    local function db_add(name, ctype)
        db[name] = ffi.cast(ctype, db.map_base + db.header[name..'_offset'])
    end
    db_add('stmts', 'struct cdefdb_stmts_t *')
    db_add('stmt_deps', 'int32_t *')
    db_add('constants_idx', 'struct cdefdb_constants_idx_t *')
    db_add('file_kind_name_idx', 'int32_t *')
    db_add('file_name_kind_idx', 'int32_t *')
    db_add('kind_file_name_idx', 'int32_t *')
    db_add('kind_name_file_idx', 'int32_t *')
    db_add('name_file_kind_idx', 'int32_t *')
    db_add('name_kind_file_idx', 'int32_t *')
    db_add('strings', 'char *')

    return db
end

return cdefdb_open
