#include "CaptureRing.h"
#include <stdlib.h>
#include <stdatomic.h>
struct CaptureRing { float *data; size_t capacity; _Atomic size_t read, write; _Atomic uint64_t first, dropped; };
CaptureRing *ring_create(size_t capacity) { CaptureRing *r=calloc(1,sizeof(*r)); if(!r) return NULL; r->data=calloc(capacity,sizeof(float)); if(!r->data){free(r);return NULL;} r->capacity=capacity;return r; }
void ring_destroy(CaptureRing *r){free(r->data);free(r);}
size_t ring_write(CaptureRing *r,const float *s,size_t n,uint64_t host){size_t w=atomic_load_explicit(&r->write,memory_order_relaxed),rd=atomic_load_explicit(&r->read,memory_order_acquire);size_t available=r->capacity-(w-rd),take=n<available?n:available;uint64_t zero=0;if(take)atomic_compare_exchange_strong(&r->first,&zero,host);for(size_t i=0;i<take;i++)r->data[(w+i)%r->capacity]=s[i];atomic_store_explicit(&r->write,w+take,memory_order_release);atomic_fetch_add(&r->dropped,n-take);return take;}
size_t ring_read(CaptureRing *r,float *s,size_t n){size_t rd=atomic_load_explicit(&r->read,memory_order_relaxed),w=atomic_load_explicit(&r->write,memory_order_acquire),take=n<w-rd?n:w-rd;for(size_t i=0;i<take;i++)s[i]=r->data[(rd+i)%r->capacity];atomic_store_explicit(&r->read,rd+take,memory_order_release);return take;}
uint64_t ring_first_host(CaptureRing *r){return atomic_load(&r->first);}
uint64_t ring_dropped(CaptureRing *r){return atomic_load(&r->dropped);}
void ring_reset(CaptureRing *r){atomic_store(&r->read,0);atomic_store(&r->write,0);atomic_store(&r->first,0);atomic_store(&r->dropped,0);}
