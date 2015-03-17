local ffi = require 'ffi'

ffi.cdef[[
struct cdefdb_header {
    char id[16];
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

int cdefdb_strcmp(const char *s1, const char *s2) asm("strcmp");
int cdefdb_open(const char *pathname, int flags) asm("open");
void *cdefdb_mmap(void *addr, size_t length, int prot, int flags,
                  int fd, int64_t offset) asm("mmap64");
int cdefdb_close(int fd) asm("close");

enum {
    CDEFDB_O_RDONLY = 0,
    CDEFDB_PROT_READ = 1,
    CDEFDB_MAP_SHARED = 1,
};
]]
