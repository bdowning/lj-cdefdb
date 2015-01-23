# Copyright (C) 2014-2015 Brian Downing.  MIT License.

script_dir="$(dirname "$0")"

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
    cd "$script_dir/ljclang"
    makeout_tmp="/tmp/ljcdefdb-make$$.out"
    if ! make inc="$llvminc" libdir="$llvmlib" libljclang_support.so >"$makeout_tmp" 2>&1; then
        cat "$makeout_tmp" >&2
        rm -f "$makeout_tmp"
        false
    else
        rm -f "$makeout_tmp"
    fi
    LD_LIBRARY_PATH=.:"$llvmlib":${LD_LIBRARY_PATH:-.} luajit "$@"
)
