#pragma once
#include <stdint.h>
#include <stddef.h>
typedef struct CaptureRing CaptureRing;
CaptureRing *ring_create(size_t capacity);
void ring_destroy(CaptureRing *ring);
size_t ring_write(CaptureRing *ring, const float *samples, size_t count, uint64_t host);
size_t ring_read(CaptureRing *ring, float *samples, size_t count);
uint64_t ring_first_host(CaptureRing *ring);
uint64_t ring_dropped(CaptureRing *ring);
void ring_reset(CaptureRing *ring);
