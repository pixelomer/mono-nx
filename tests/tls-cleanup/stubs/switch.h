#pragma once
#include <stdint.h>
#include <stdbool.h>
typedef uint64_t u64;
typedef int32_t s32;
typedef int Mutex;
#define INVALID_HANDLE 0
static void mutexLock(Mutex* mutex) { (void)mutex; }
static void mutexUnlock(Mutex* mutex) { (void)mutex; }
static void* slot;
static void (*slot_destructor)(void*);
static s32 threadTlsAlloc(void (*destructor)(void*)) { slot_destructor=destructor; return 0; }
static void* threadTlsGet(s32 key) { (void)key; return slot; }
static void threadTlsSet(s32 key,void* value) { (void)key; slot=value; }
