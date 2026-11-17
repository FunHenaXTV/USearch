/**
 *  @file reproductions/cpu-sanitizers/neon-stack/insert.c
 *  @author Zubkov Dmitrii
 *  @date November 17, 2026
 *  @brief Reproduces NEON conversion stack usage during BF16 insertion.
 */
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>

#include "usearch/usearch.h"
static int insert(size_t threads) {
    usearch_outcome_t outcome = {0};
    usearch_dense_index_t index = NULL;
    usearch_executor_t executor = NULL;
    float rows[11 * 83];
    usearch_key_t keys[11] = {0};
    for (size_t i = 0; i < 11 * 83; i++) rows[i] = (float)(i % 23);
    for (size_t i = 0; i < 11; i++) keys[i].bytes[15] = (unsigned char)i;
    usearch_executor_for_ram(
        &(usearch_executor_for_ram_t) {.executor = &executor, .outcome = &outcome, .threads = threads});
    if (outcome.status) {
        fprintf(stderr, "executor: %s\n", outcome.message);
        return 1;
    }
    usearch_dense_init_ram(&(usearch_dense_init_ram_t) {.index = &index,
                                                        .outcome = &outcome,
                                                        .dimensions = 83,
                                                        .metric = usearch_dense_metric_angular_k,
                                                        .quantization = usearch_scalar_bf16_k,
                                                        .connectivity = 16});
    if (outcome.status) {
        fprintf(stderr, "index: %s\n", outcome.message);
        return 1;
    }
    printf("insert threads=%zu caller_stack_size=%zu caller_stack_top=%p\n", threads,
           pthread_get_stacksize_np(pthread_self()), pthread_get_stackaddr_np(pthread_self()));
    fflush(stdout);
    usearch_dense_insert(&(usearch_dense_insert_t) {.index = index,
                                                    .executor = executor,
                                                    .outcome = &outcome,
                                                    .count = 11,
                                                    .keys = {keys, sizeof(keys[0])},
                                                    .vectors = {rows, 83 * sizeof(float), 83, usearch_scalar_f32_k}});
    fprintf(stderr, "insert status=%d %s\n", outcome.status, outcome.message ? outcome.message : "");
    usearch_dense_free(index);
    usearch_executor_free(executor);
    return outcome.status != 0;
}
int main(int argc, char** argv) { return insert(argc > 1 ? strtoul(argv[1], NULL, 10) : 1); }
