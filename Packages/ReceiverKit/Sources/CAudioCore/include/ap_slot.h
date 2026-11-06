#ifndef AP_SLOT_H
#define AP_SLOT_H

#include <stdint.h>
#include <CoreAudio/CoreAudioTypes.h>

#ifdef __cplusplus
extern "C" {
#endif

/// One slot's audio buffer: a lock-free single-producer / single-consumer
/// stereo ring buffer (planar Float32) plus the playback state the render
/// callback needs. The producer is the capture queue, the consumer is
/// the audio render thread. Everything the render thread touches is atomics
/// or render-thread-private fields: no locks, no allocation.
typedef struct ap_slot ap_slot;

ap_slot *ap_slot_create(uint32_t capacity_frames, uint32_t sample_rate);
void ap_slot_destroy(ap_slot *slot);

// Producer side.
/// Writes up to `frames` frames; returns how many were written. Frames that do
/// not fit are dropped and counted.
uint32_t ap_slot_write(ap_slot *slot, const float *left, const float *right, uint32_t frames);

// Consumer side.
/// Raw read (used by tests and the render callback). Returns frames read.
uint32_t ap_slot_read(ap_slot *slot, float *left, float *right, uint32_t frames);
/// Render callback body: handles priming to the target depth, underrun
/// re-buffering, a short fade-in on start and the 20 ms fade-out on flush.
void ap_slot_render(ap_slot *slot, uint32_t frames, AudioBufferList *abl);

// Any thread.
uint32_t ap_slot_available(const ap_slot *slot);
uint32_t ap_slot_capacity(const ap_slot *slot);
void ap_slot_set_target(ap_slot *slot, uint32_t frames);
uint32_t ap_slot_target(const ap_slot *slot);
/// Asks the render thread to fade out over 20 ms and clear the buffer.
void ap_slot_request_flush(ap_slot *slot);
int ap_slot_flush_pending(const ap_slot *slot);
int ap_slot_is_primed(const ap_slot *slot);
uint64_t ap_slot_underruns(const ap_slot *slot);
uint64_t ap_slot_dropped_frames(const ap_slot *slot);

#ifdef __cplusplus
}
#endif

#endif
