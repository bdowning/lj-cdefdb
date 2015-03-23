llvm_incdir = /usr/include
llvm_libdir = /usr/lib

prefix = /usr

bindir = $(prefix)/bin
libdir = $(prefix)/lib
datadir = $(prefix)/share

lj_cdefdb_dir = $(libdir)/lj-cdefdb
luashare_dir = $(datadir)/lua/5.1

.PHONY: all
all: ljclang

.PHONY: ljclang
ljclang:
	cd ljclang && make inc="$(llvm_incdir)" libdir="$(llvm_libdir)"

BINS = cdefdb-helper gen-cdefdb
LIBS = functions.sh cdefdb-helper.lua gen-cdefdb.lua

.PHONY: install
install: all
	mkdir -p $(DESTDIR)$(luashare_dir)
	cp -r share/* $(DESTDIR)$(luashare_dir)
	echo "return { dir = '$(lj_cdefdb_dir)' }" \
	    > $(DESTDIR)$(luashare_dir)/cdefdb/config.lua
	mkdir -p $(DESTDIR)$(lj_cdefdb_dir)
	cp -r $(LIBS) $(DESTDIR)$(lj_cdefdb_dir)
	mkdir -p $(DESTDIR)$(bindir)
	cp -r $(BINS) $(DESTDIR)$(bindir)
	mkdir -p $(DESTDIR)$(lj_cdefdb_dir)/ljclang
	cp -r ljclang/ljclang*.lua ljclang/libljclang_support.so \
	    $(DESTDIR)$(lj_cdefdb_dir)/ljclang
	mkdir -p $(DESTDIR)$(lj_cdefdb_dir)/cdefdb.d
	mkdir -p $(DESTDIR)$(lj_cdefdb_dir)/stubs

.PHONY: clean
clean:
	cd ljclang && make clean
