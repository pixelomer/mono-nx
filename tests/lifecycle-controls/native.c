#include <switch.h>
#include <stdio.h>
#include <malloc.h>
#include <sys/stat.h>
#include <pthread.h>
#include <stdint.h>
#include <string.h>
#ifdef MONO_ALLOC_OWNER_TRACE
void lifecycle_allocation_snapshot(FILE* file);
#endif

unsigned long long lifecycle_native_used(void)
{
    return (unsigned long long)mallinfo().uordblks;
}

static void* native_worker(void* token)
{
    return token;
}

static void native_thread_control(FILE* file)
{
    // Same libc/libnx pthread implementation, without attaching to Mono.
    // Every created handle has exactly one join owner.
    for (int round = 0; round < 48; round++) {
        pthread_t threads[8];
        int made = 0, errors = 0;
        for (int i = 0; i < 8; i++) {
            int rc = pthread_create(&threads[i], NULL, native_worker, (void*)(uintptr_t)(i+1));
            if (rc != 0) { errors++; break; }
            made++;
        }
        for (int i = 0; i < made; i++) {
            void* result = NULL;
            int rc = pthread_join(threads[i], &result);
            if (rc != 0 || result != (void*)(uintptr_t)(i+1)) errors++;
        }
        fprintf(file, "native_phase=pthreads round=%d native_used=%llu errors=%d\n",
            round, lifecycle_native_used(), errors);
        fflush(file);
        if (errors) { fprintf(file, "NATIVE CONTROL FAIL\n"); return; }
    }
}

void lifecycle_log(const char* text)
{
    static int first = 1;
    mkdir("sdmc:/switch", 0777);
    FILE* file = fopen("sdmc:/switch/mono-llvm-lifecycle-controls.txt", first ? "w" : "a");
    if (!file) return;
    first = 0;
    fprintf(file, "%s\n", text);
    if (strncmp(text, "BEGIN ", 6) == 0) native_thread_control(file);
#ifdef MONO_ALLOC_OWNER_TRACE
    if (strncmp(text, "BEGIN ", 6) == 0 || strstr(text, " round=0 ") ||
        strstr(text, " round=47 ") || strncmp(text, "PASS ", 5) == 0)
        lifecycle_allocation_snapshot(file);
#endif
    fclose(file);
}
