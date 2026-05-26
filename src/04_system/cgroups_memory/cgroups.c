#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define MEBIBYTE (1 << 20)
size_t total_allocated = 0;

// Return 2^20 bytes of data and return true of allocation succeeded
bool allocate_mebibyte(size_t count) {
    size_t size = count * MEBIBYTE;
    void* ptr = malloc(size);
    if (ptr == NULL) return false;
    total_allocated += size;
    memset(ptr, 0, size);
    return true;
}

int main(int argc, char* argv[]) {
    while (allocate_mebibyte(1)) {
        printf("Allocated 1 MEBIBYTE, reaching a total of %lu bytes\n",
               total_allocated);
        usleep(100000);
    }
    printf("Allocation failed, reaching a total of %lu bytes\n",
           total_allocated);
}
