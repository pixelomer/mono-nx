#include <switch.h>
#include <stdio.h>
#include <malloc.h>
#include <sys/stat.h>

unsigned long long lifecycle_native_used(void)
{
    return (unsigned long long)mallinfo().uordblks;
}

void lifecycle_log(const char* text)
{
    static int first = 1;
    mkdir("sdmc:/switch", 0777);
    FILE* file = fopen("sdmc:/switch/mono-llvm-lifecycle-controls.txt", first ? "w" : "a");
    if (!file) return;
    first = 0;
    fprintf(file, "%s\n", text);
    fclose(file);
}
