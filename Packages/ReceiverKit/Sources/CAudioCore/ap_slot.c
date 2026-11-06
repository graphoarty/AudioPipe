#include "ap_slot.h"

#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

struct ap_slot {
    float *left;
    float *right;
    uint32_t capacity;
    uint32_t sample_rate;

    _Atomic uint64_t write_index;   // owned by producer
    _Atomic uint64_t read_index;    // owned by consumer

    _Atomic uint32_t target_frames;
    _Atomic int32_t primed;          // written by render thread only
    _Atomic int32_t flush_request;   // set by any thread, cleared by render thread
    _Atomic uint64_t underruns;
    _Atomic uint64_t dropped;

    // Render-thread private.
    uint32_t fade_out_len;
    uint32_t fade_in_len;
    int64_t fade_out_pos;  // -1 when inactive
    int64_t fade_in_pos;   // -1 when inactive
};

ap_slot *ap_slot_create(uint32_t capacity_frames, uint32_t sample_rate) {
    if (capacity_frames == 0 || sample_rate == 0) return NULL;
    ap_slot *s = calloc(1, sizeof(ap_slot));
    if (!s) return NULL;
    s->left = calloc(capacity_frames, sizeof(float));
    s->right = calloc(capacity_frames, sizeof(float));
    if (!s->left || !s->right) {
        free(s->left);
        free(s->right);
        free(s);
        return NULL;
    }
    s->capacity = capacity_frames;
    s->sample_rate = sample_rate;
    atomic_init(&s->write_index, 0);
    atomic_init(&s->read_index, 0);
    atomic_init(&s->target_frames, sample_rate * 40 / 1000);
    atomic_init(&s->primed, 0);
    atomic_init(&s->flush_request, 0);
    atomic_init(&s->underruns, 0);
    atomic_init(&s->dropped, 0);
    s->fade_out_len = sample_rate * 20 / 1000;  // 20 ms, per spec
    s->fade_in_len = sample_rate * 5 / 1000;    // 5 ms de-click on start
    s->fade_out_pos = -1;
    s->fade_in_pos = -1;
    return s;
}

void ap_slot_destroy(ap_slot *s) {
    if (!s) return;
    free(s->left);
    free(s->right);
    free(s);
}

uint32_t ap_slot_write(ap_slot *s, const float *left, const float *right, uint32_t frames) {
    uint64_t w = atomic_load_explicit(&s->write_index, memory_order_relaxed);
    uint64_t r = atomic_load_explicit(&s->read_index, memory_order_acquire);
    uint64_t used = w - r;
    uint32_t space = used >= s->capacity ? 0 : (uint32_t)(s->capacity - used);
    uint32_t n = frames < space ? frames : space;
    if (n < frames) {
        atomic_fetch_add_explicit(&s->dropped, frames - n, memory_order_relaxed);
    }
    if (n == 0) return 0;

    uint32_t start = (uint32_t)(w % s->capacity);
    uint32_t first = s->capacity - start;
    if (first > n) first = n;
    memcpy(s->left + start, left, first * sizeof(float));
    memcpy(s->right + start, right, first * sizeof(float));
    if (n > first) {
        memcpy(s->left, left + first, (n - first) * sizeof(float));
        memcpy(s->right, right + first, (n - first) * sizeof(float));
    }
    atomic_store_explicit(&s->write_index, w + n, memory_order_release);
    return n;
}

uint32_t ap_slot_read(ap_slot *s, float *left, float *right, uint32_t frames) {
    uint64_t r = atomic_load_explicit(&s->read_index, memory_order_relaxed);
    uint64_t w = atomic_load_explicit(&s->write_index, memory_order_acquire);
    uint64_t avail = w - r;
    uint32_t n = frames < avail ? frames : (uint32_t)avail;
    if (n == 0) return 0;

    uint32_t start = (uint32_t)(r % s->capacity);
    uint32_t first = s->capacity - start;
    if (first > n) first = n;
    memcpy(left, s->left + start, first * sizeof(float));
    memcpy(right, s->right + start, first * sizeof(float));
    if (n > first) {
        memcpy(left + first, s->left, (n - first) * sizeof(float));
        memcpy(right + first, s->right, (n - first) * sizeof(float));
    }
    atomic_store_explicit(&s->read_index, r + n, memory_order_release);
    return n;
}

static void discard_all(ap_slot *s) {
    uint64_t w = atomic_load_explicit(&s->write_index, memory_order_acquire);
    atomic_store_explicit(&s->read_index, w, memory_order_release);
}

void ap_slot_render(ap_slot *s, uint32_t frames, AudioBufferList *abl) {
    if (!abl || abl->mNumberBuffers < 1) return;
    float *L = (float *)abl->mBuffers[0].mData;
    float *R = abl->mNumberBuffers > 1 ? (float *)abl->mBuffers[1].mData : NULL;
    if (!L) return;
    if (!s || !R) {
        memset(L, 0, frames * sizeof(float));
        if (R) memset(R, 0, frames * sizeof(float));
        return;
    }

    int primed = atomic_load_explicit(&s->primed, memory_order_relaxed);

    // Session ended: fade out over 20 ms, then clear the buffer.
    if (atomic_load_explicit(&s->flush_request, memory_order_acquire)) {
        uint32_t got = 0;
        if (primed) {
            if (s->fade_out_pos < 0) s->fade_out_pos = 0;
            got = ap_slot_read(s, L, R, frames);
            for (uint32_t i = 0; i < got; i++) {
                float g = s->fade_out_pos < (int64_t)s->fade_out_len
                    ? 1.0f - (float)s->fade_out_pos / (float)s->fade_out_len
                    : 0.0f;
                L[i] *= g;
                R[i] *= g;
                s->fade_out_pos++;
            }
            if (got < frames) s->fade_out_pos = s->fade_out_len;  // nothing left to fade
        }
        if (got < frames) {
            memset(L + got, 0, (frames - got) * sizeof(float));
            memset(R + got, 0, (frames - got) * sizeof(float));
        }
        if (!primed || s->fade_out_pos >= (int64_t)s->fade_out_len) {
            discard_all(s);
            s->fade_out_pos = -1;
            s->fade_in_pos = -1;
            atomic_store_explicit(&s->primed, 0, memory_order_relaxed);
            atomic_store_explicit(&s->flush_request, 0, memory_order_release);
        }
        return;
    }

    if (!primed) {
        uint32_t target = atomic_load_explicit(&s->target_frames, memory_order_relaxed);
        if (target == 0) target = 1;
        if (ap_slot_available(s) >= target) {
            primed = 1;
            atomic_store_explicit(&s->primed, 1, memory_order_relaxed);
            s->fade_in_pos = 0;
        } else {
            memset(L, 0, frames * sizeof(float));
            memset(R, 0, frames * sizeof(float));
            return;
        }
    }

    // Far over target (e.g. the engine was stopped for a device change while
    // the capture kept writing): drop the excess instead of letting the ±0.1 %
    // drift controller take minutes to drain it.
    {
        uint32_t target = atomic_load_explicit(&s->target_frames, memory_order_relaxed);
        uint32_t limit = target * 2 + s->sample_rate / 20;  // 2× target + 50 ms
        uint32_t avail = ap_slot_available(s);
        if (avail > limit + frames) {
            uint64_t r = atomic_load_explicit(&s->read_index, memory_order_relaxed);
            atomic_store_explicit(&s->read_index, r + (avail - target - frames), memory_order_release);
            s->fade_in_pos = 0;  // soften the jump
        }
    }

    uint32_t got = ap_slot_read(s, L, R, frames);
    if (got < frames) {
        // Underrun: output silence and re-buffer to the target depth.
        memset(L + got, 0, (frames - got) * sizeof(float));
        memset(R + got, 0, (frames - got) * sizeof(float));
        atomic_fetch_add_explicit(&s->underruns, 1, memory_order_relaxed);
        atomic_store_explicit(&s->primed, 0, memory_order_relaxed);
    }

    if (s->fade_in_pos >= 0) {
        for (uint32_t i = 0; i < got && s->fade_in_pos < (int64_t)s->fade_in_len; i++) {
            float g = (float)s->fade_in_pos / (float)s->fade_in_len;
            L[i] *= g;
            R[i] *= g;
            s->fade_in_pos++;
        }
        if (s->fade_in_pos >= (int64_t)s->fade_in_len) s->fade_in_pos = -1;
    }
}

uint32_t ap_slot_available(const ap_slot *s) {
    uint64_t w = atomic_load_explicit(&((ap_slot *)s)->write_index, memory_order_acquire);
    uint64_t r = atomic_load_explicit(&((ap_slot *)s)->read_index, memory_order_acquire);
    uint64_t d = w >= r ? w - r : 0;
    return d > s->capacity ? s->capacity : (uint32_t)d;
}

uint32_t ap_slot_capacity(const ap_slot *s) { return s->capacity; }

void ap_slot_set_target(ap_slot *s, uint32_t frames) {
    if (frames > s->capacity) frames = s->capacity;
    atomic_store_explicit(&s->target_frames, frames, memory_order_relaxed);
}

uint32_t ap_slot_target(const ap_slot *s) {
    return atomic_load_explicit(&((ap_slot *)s)->target_frames, memory_order_relaxed);
}

void ap_slot_request_flush(ap_slot *s) {
    atomic_store_explicit(&s->flush_request, 1, memory_order_release);
}

int ap_slot_flush_pending(const ap_slot *s) {
    return atomic_load_explicit(&((ap_slot *)s)->flush_request, memory_order_acquire);
}

int ap_slot_is_primed(const ap_slot *s) {
    return atomic_load_explicit(&((ap_slot *)s)->primed, memory_order_relaxed);
}

uint64_t ap_slot_underruns(const ap_slot *s) {
    return atomic_load_explicit(&((ap_slot *)s)->underruns, memory_order_relaxed);
}

uint64_t ap_slot_dropped_frames(const ap_slot *s) {
    return atomic_load_explicit(&((ap_slot *)s)->dropped, memory_order_relaxed);
}
