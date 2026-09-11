#pragma once
#include <assert.h>
#define MONO_TRACE_DIAGNOSTICS 0
#define mono_trace_message(...) ((void)0)
#define g_assert(value) assert(value)
#define g_error(...) do { fprintf(stderr,__VA_ARGS__); abort(); } while(0)
