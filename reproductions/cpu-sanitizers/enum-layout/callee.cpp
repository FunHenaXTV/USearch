/**
 *  @file reproductions/cpu-sanitizers/enum-layout/callee.cpp
 *  @author Zubkov Dmitrii
 *  @date November 17, 2026
 *  @brief Exercises the actual layout guard and a representation-validation control.
 */
#include <bit>
#include <type_traits>

#include "src/basic_punned.cuh"

extern "C" int accepts_layout(usearch_tape_view_t const* tape) {
#ifdef VALIDATE_REPRESENTATION
    // Control: validate the integer representation before evaluating an enum value.
    auto const raw = std::bit_cast<std::underlying_type_t<usearch_tape_layout_t>>(tape->layout);
    if (raw != usearch_tape_u32_k && raw != usearch_tape_u64_k) return 0;
#endif
    return known_layout(tape->layout);
}
