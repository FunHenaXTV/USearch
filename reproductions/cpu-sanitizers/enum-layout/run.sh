#!/usr/bin/env bash
# Uses the real public enum and real private validation helper from this checkout.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo=${USEARCH_SOURCE_DIR:-$(cd "$here/../../.." && pwd)}
work=${REPRO_BUILD_DIR:-${TMPDIR:-/tmp}/usearch-enum-layout-repro}
mkdir -p "$work"
if [[ -z ${YYJSON_SOURCE_DIR:-} ]]; then
    cmake -S "$repo" -B "$work/configure" -G Ninja -D USEARCH_MULTIVERSIONED=OFF -D USEARCH_MARCH=native
    YYJSON_SOURCE_DIR="$work/configure/_deps/yyjson-src"
fi
includes=(-iquote "$repo" -I"$repo/include" -I"$repo/c" -I"$repo/numkong/include" -I"$repo/numkong/c"
          -I"$repo/forkunion/include" -I"$repo/forkunion/c" -I"$repo/stringzilla/include"
          -I"$repo/stringzilla/c" -I"$repo/smashtable/include" -I"$YYJSON_SOURCE_DIR/src")
"${CC:-clang}" -std=c11 -g -I"$repo/c" -c "$here/caller.c" -o "$work/caller.o"
"${CXX:-clang++}" -std=c++20 -O1 -g -fsanitize=undefined "${includes[@]}" "$here/callee.cpp" "$work/caller.o" -o "$work/ubsan"
"${CXX:-clang++}" -std=c++20 -O2 -fstrict-enums "${includes[@]}" "$here/callee.cpp" "$work/caller.o" -o "$work/strict"
"${CXX:-clang++}" -std=c++20 -O2 -fstrict-enums -fsanitize=undefined -DVALIDATE_REPRESENTATION \
    "${includes[@]}" "$here/callee.cpp" "$work/caller.o" -o "$work/guarded"
for value in 0 1; do "$work/ubsan" "$value"; "$work/strict" "$value"; "$work/guarded" "$value"; done
for value in 2 7; do
    status=0
    UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 "$work/ubsan" "$value" >"$work/ubsan-$value.log" 2>&1 || status=$?
    test "$status" -ne 0
    grep -q 'not a valid value for type' "$work/ubsan-$value.log"
    printf 'UBSan detected unknown layout %s (log: %s)\n' "$value" "$work/ubsan-$value.log"
    status=0
    "$work/strict" "$value" || status=$?
    test "$status" -eq 1 # Current guard incorrectly accepts this value under strict enum optimization.
    UBSAN_OPTIONS=halt_on_error=1 "$work/guarded" "$value"
done
