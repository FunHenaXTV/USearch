/**
 *  @file reproductions/cpu-sanitizers/enum-layout/caller.c
 *  @author Zubkov Dmitrii
 *  @date November 17, 2026
 *  @brief Passes numeric tape-layout values across the C ABI.
 */
#include <stdio.h>
#include <stdlib.h>

#include "usearch/types.h"

int accepts_layout(usearch_tape_view_t const* tape);

int main(int argc, char** argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s <layout-number>\n", argv[0]);
        return 2;
    }
    int const value = atoi(argv[1]);
    usearch_tape_view_t tape = {0};
    tape.layout = (usearch_tape_layout_t)value;
    int const accepted = accepts_layout(&tape);
    printf("layout=%d accepted=%d\n", value, accepted);
    return accepted != (value == 0 || value == 1);
}
