// Copyright (c) 2026 Open Neom / SAIA. All rights reserved.

#ifndef SAIA_TURBOVEC_H_
#define SAIA_TURBOVEC_H_

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct IdMapIndexOpaque IdMapIndexOpaque;

IdMapIndexOpaque* turbovec_create_index(size_t dim, size_t bit_width);

IdMapIndexOpaque* turbovec_create_lazy_index(size_t bit_width);

bool turbovec_add_with_ids_2d(
    IdMapIndexOpaque* index,
    const float* vectors,
    size_t dim,
    const uint64_t* ids,
    size_t count);

size_t turbovec_search(
    const IdMapIndexOpaque* index,
    const float* query,
    size_t k,
    const uint64_t* allowlist,
    size_t allowlist_len,
    float* scores_out,
    uint64_t* ids_out);

bool turbovec_remove(IdMapIndexOpaque* index, uint64_t id);

bool turbovec_write(const IdMapIndexOpaque* index, const char* path);

IdMapIndexOpaque* turbovec_load(const char* path);

void turbovec_free_index(IdMapIndexOpaque* index);

size_t turbovec_len(const IdMapIndexOpaque* index);

size_t turbovec_dim(const IdMapIndexOpaque* index);

#ifdef __cplusplus
}
#endif

#endif  // SAIA_TURBOVEC_H_
