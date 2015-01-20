# Copyright (C) 2014-2015 Brian Downing.  MIT License.

script_dir="$(dirname "$0")"

llvm=/usr
for d in /usr/lib/llvm-3.4 /usr/lib/llvm-3.5 /usr /usr/local; do
    if [ -e "$d"/include/clang-c/Index.h -a -e "$d"/lib/libclang.so ]; then
        llvm="$d"
    fi
done

run_in_ljclang() (
    cd "$script_dir/ljclang"
    make inc="$llvm"/include libdir="$llvm"/lib libljclang_support.so >&2
    LD_LIBRARY_PATH=.:"$llvm"/lib:${LD_LIBRARY_PATH:-.} luajit "$@"
)
