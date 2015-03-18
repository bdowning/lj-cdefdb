# Copyright (C) 2014-2015 Brian Downing.  MIT License.

lj_cdefdb_dir=${LJ_CDEFDB_DIR:-$(luajit -e "print(require('cdefdb.config').dir)")}

prefixes="/usr/lib/llvm-3.4 /usr/lib/llvm-3.5 /usr /usr/local"
llvminc=/usr/include
for d in $prefixes; do
    if [ -e "$d"/include/clang-c/Index.h ]; then
        llvminc="$d/include"
    fi
done
llvmlib=/usr/lib
for d in $prefixes; do
    for p in lib64/llvm lib/llvm lib64 lib; do
        if [ -e "$d"/"$p"/libclang.so ]; then
            llvmlib="$d/$p"
        fi
    done
done

run_in_ljclang() (
    cd "$lj_cdefdb_dir/ljclang"
    LD_LIBRARY_PATH=.:"$llvmlib":${LD_LIBRARY_PATH:-.} luajit "$@"
)
