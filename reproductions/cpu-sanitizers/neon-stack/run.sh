#!/usr/bin/env bash
# macOS/Apple Silicon reproduction; all generated files stay outside the source tree.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo=${USEARCH_SOURCE_DIR:-$(cd "$here/../../.." && pwd)}
work=${REPRO_BUILD_DIR:-${TMPDIR:-/tmp}/usearch-neon-stack-repro}
mkdir -p "$work"
common=(-S "$repo" -G Ninja -D CMAKE_BUILD_TYPE=Debug -D USEARCH_BUILD_SHARED=ON
        -D USEARCH_BUILD_TEST=OFF -D USEARCH_MULTIVERSIONED=OFF -D USEARCH_MARCH=native
        -D USEARCH_BUILD_SANITIZERS=address)
if [[ -n ${YYJSON_SOURCE_DIR:-} ]]; then
    common+=(-D "FETCHCONTENT_SOURCE_DIR_YYJSON=$YYJSON_SOURCE_DIR")
fi
build() {
    cmake "${common[@]}" -B "$work/$1" -D "CMAKE_C_FLAGS_DEBUG=$2" -D "CMAKE_CXX_FLAGS_DEBUG=$2"
    cmake --build "$work/$1" --target usearch_shared --parallel 4
}
build o0 '-O0 -g'
build o1 '-O1 -g'
"${CC:-clang}" -std=c11 -g -fsanitize=address,undefined -fno-omit-frame-pointer \
    -I"$repo/c" "$here/insert.c" -L"$work/o0" -lusearch_shared \
    -Wl,-rpath,"$work/o0" -o "$work/insert"
export ASAN_OPTIONS=detect_leaks=0:halt_on_error=1
export UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1
run_case() {
    local library=$1 threads=$2 expected=$3 status=0
    DYLD_LIBRARY_PATH="$work/$library" "$work/insert" "$threads" >"$work/${library}-threads${threads}.log" 2>&1 || status=$?
    printf '%s threads=%s exit=%s (log: %s)\n' "$library" "$threads" "$status" "$work/${library}-threads${threads}.log"
    if [[ $expected == success ]]; then test "$status" -eq 0
    else
        test "$status" -ne 0
        grep -q 'ERROR: AddressSanitizer' "$work/${library}-threads${threads}.log"
    fi
}
run_case o0 1 success
run_case o0 2 failure
run_case o1 2 success
# Control: stop forced inlining at the two large dispatch boundaries, retaining -O0 and both sanitizers.
mkdir -p "$work/overlay/numkong/cast"
python3 - "$repo" "$work/overlay/numkong/cast/neon.h" <<'PY'
import pathlib, sys
text = (pathlib.Path(sys.argv[1]) / 'numkong/include/numkong/cast/neon.h').read_text()
for name in ('nk_cast_block_scaled_neon_', 'nk_cast_elementwise_neon_'):
    before = 'NUMKONG_INLINE void ' + name + '('
    assert text.count(before) == 1, name
    text = text.replace(before, 'static __attribute__((noinline)) void ' + name + '(')
pathlib.Path(sys.argv[2]).write_text(text)
PY
build split "-O0 -g -I$work/overlay"
run_case split 2 success
