// Diagnostic only: fixed storage and lock-free updates avoid introducing an
// allocator lock that a GC-suspended worker could hold. Snapshots are approximate
// when background native allocation is concurrent; joined-worker deltas matter.
#include <stdint.h>
#include <stddef.h>
#include <stdatomic.h>
#include <stdio.h>
#include <string.h>

#define SLOTS 131072
typedef struct { _Atomic(uintptr_t) pointer, caller; _Atomic(size_t) size; } Entry;
static Entry entries[SLOTS];
static _Atomic(unsigned) overflow;

static void forget(void* ptr)
{
    uintptr_t value=(uintptr_t)ptr;
    if(!value) return;
    size_t start=((value>>4)*11400714819323198485ull)&(SLOTS-1);
    for(size_t i=0;i<SLOTS;i++) {
        Entry* e=&entries[(start+i)&(SLOTS-1)];
        uintptr_t p=atomic_load(&e->pointer);
        if(p==0) return;
        if(p==value) { atomic_store(&e->pointer,1); return; }
    }
}
static void remember(void* ptr,size_t size,void* caller)
{
    uintptr_t value=(uintptr_t)ptr;
    if(!value) return;
    size_t start=((value>>4)*11400714819323198485ull)&(SLOTS-1);
    for(size_t i=0;i<SLOTS;i++) {
        Entry* e=&entries[(start+i)&(SLOTS-1)];
        uintptr_t p=atomic_load(&e->pointer);
        if(p==value) { atomic_store(&e->size,size); atomic_store(&e->caller,(uintptr_t)caller); return; }
        // Insertions may use a tombstone before an older duplicate entry.
        // Wrappers remove their previous record before replacing provenance.
        if(p<=1 && atomic_compare_exchange_strong(&e->pointer,&p,2)) {
            atomic_store(&e->size,size); atomic_store(&e->caller,(uintptr_t)caller);
            atomic_store(&e->pointer,value); return;
        }
    }
    atomic_fetch_add(&overflow,1);
}
#define RECORD(p,n) do { forget(p); remember(p,n,__builtin_return_address(0)); } while(0)
#define MALLOC_WRAP(name) \
extern void* __real_##name(size_t); \
void* __wrap_##name(size_t n) { void* p=__real_##name(n); RECORD(p,n); return p; }
#define CALLOC_WRAP(name) \
extern void* __real_##name(size_t,size_t); \
void* __wrap_##name(size_t n,size_t m) { void* p=__real_##name(n,m); RECORD(p,n*m); return p; }
#define REALLOC_WRAP(name) \
extern void* __real_##name(void*,size_t); \
void* __wrap_##name(void* old,size_t n) { void* p=__real_##name(old,n); if(p || !n) forget(old); RECORD(p,n); return p; }
#define FREE_WRAP(name) \
extern void __real_##name(void*); \
void __wrap_##name(void* p) { forget(p); __real_##name(p); }
MALLOC_WRAP(malloc)
CALLOC_WRAP(calloc)
REALLOC_WRAP(realloc)
FREE_WRAP(free)
MALLOC_WRAP(monoeg_malloc)
MALLOC_WRAP(monoeg_malloc0)
MALLOC_WRAP(monoeg_try_malloc)
CALLOC_WRAP(monoeg_g_calloc)
REALLOC_WRAP(monoeg_realloc)
REALLOC_WRAP(monoeg_try_realloc)
FREE_WRAP(monoeg_g_free)

void lifecycle_allocation_snapshot(FILE* file)
{
    typedef struct { uintptr_t caller; size_t count,bytes; } Owner;
    static Owner owners[2048];
    memset(owners,0,sizeof(owners));
    size_t used=0,missed=0;
    for(size_t i=0;i<SLOTS;i++) {
        Entry* e=&entries[i]; uintptr_t p=atomic_load(&e->pointer);
        if(p<=2) continue;
        uintptr_t caller=atomic_load(&e->caller); size_t size=atomic_load(&e->size);
        if(atomic_load(&e->pointer)!=p) continue;
        size_t j; for(j=0;j<used;j++) if(owners[j].caller==caller) break;
        if(j==used) { if(used==2048) { missed++; continue; } owners[used++].caller=caller; }
        owners[j].count++; owners[j].bytes+=size;
    }
    fprintf(file,"OWNERS begin overflow=%u missed=%zu anchor=%p\n",atomic_load(&overflow),missed,(void*)lifecycle_allocation_snapshot);
    for(size_t j=0;j<used;j++) fprintf(file,"owner pc=0x%lx count=%zu bytes=%zu\n",
        (unsigned long)owners[j].caller,owners[j].count,owners[j].bytes);
    fprintf(file,"OWNERS end\n");
}
