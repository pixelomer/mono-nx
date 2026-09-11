#include <stdlib.h>
#include <stdio.h>
#include <assert.h>
typedef int MonoNativeTlsKey;
typedef void* gpointer;
static int containers;
static void* tracked_calloc(size_t n,size_t size) { void* p=calloc(n,size); if(p) containers++; return p; }
void tracked_free(void* p) { if(p) containers--; free(p); }
#define calloc tracked_calloc
#define free tracked_free
#include "tls-under-test.inc"
#undef calloc
#undef free

static MonoNativeTlsKey repeat_key, peer_key, plain_key, freed_key, forever_key;
static int repeats,peers,freed_calls,forever_calls,token;
static void repeat(void* value)
{
    assert(value==&token);
    assert(mono_native_tls_get_value(repeat_key)==NULL);
    if(++repeats<3) mono_native_tls_set_value(repeat_key,value);
}
static void peer(void* value) { assert(value==&token); peers++; }
static void freed(void* value) { (void)value; freed_calls++; }
static void forever(void* value) { forever_calls++; mono_native_tls_set_value(forever_key,value); }
static void exit_thread(void)
{
    // libnx clears its physical slot before its single destructor call.
    void* old=slot; slot=NULL;
    if(old) slot_destructor(old);
    assert(slot==NULL && containers==0);
}
int main(void)
{
    mono_native_tls_alloc(&repeat_key,repeat);
    mono_native_tls_alloc(&peer_key,peer);
    mono_native_tls_alloc(&plain_key,NULL);
    mono_native_tls_alloc(&freed_key,freed);
    mono_native_tls_alloc(&forever_key,forever);
    assert(mono_native_tls_get_value(plain_key)==NULL && containers==0);
    mono_native_tls_set_value(plain_key,NULL);
    assert(containers==0);
    mono_native_tls_set_value(repeat_key,&token);
    mono_native_tls_set_value(peer_key,&token);
    mono_native_tls_set_value(plain_key,&token);
    mono_native_tls_set_value(freed_key,&token);
    mono_native_tls_free(freed_key);
    assert(containers==1);
    exit_thread();
    assert(repeats==3 && peers==1 && freed_calls==0);
    mono_native_tls_set_value(forever_key,&token);
    exit_thread();
    assert(forever_calls==4);
    for(int i=0;i<128;i++) {
        mono_native_tls_set_value(plain_key,&token);
        assert(mono_native_tls_get_value(plain_key)==&token);
        mono_native_tls_set_value(plain_key,NULL);
        assert(mono_native_tls_get_value(plain_key)==NULL);
        exit_thread();
    }
    puts("PASS: container reclamation, null access, destructor values, repeated callbacks, freed keys, bounded passes");
}
