
#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>

#define MEM_FILE "/dev/mem"
#define PAGE_SIZE (4 * 1024)
#define CHIP_ID_BASE_ADDRESS (0x01c14200)
#define CHIP_ID_REGISTER_COUNT (4)

int main(void)
{
    int ret = EXIT_SUCCESS;
    int fd;
    void* memory = MAP_FAILED;

    fd = open(MEM_FILE, O_RDONLY);
    if (fd < 0) {
        perror("open");
        ret = EXIT_FAILURE;
        goto end;
    }

    /* bind to a page boundary*/
    const size_t page_offset = CHIP_ID_BASE_ADDRESS % PAGE_SIZE;
    const size_t mmap_offset = CHIP_ID_BASE_ADDRESS - page_offset;

    memory = mmap(NULL, PAGE_SIZE, PROT_READ, MAP_SHARED, fd, mmap_offset);
    if (memory == MAP_FAILED) {
        perror("mmap");
        ret = EXIT_FAILURE;
        goto end;
    }

    uint32_t* chip_id = (uint32_t*)((uint8_t*)memory + page_offset);

    printf("Chip id is ");
    for (size_t i = 0; i < CHIP_ID_REGISTER_COUNT; ++i) {
        printf("%" PRIx32 " ", chip_id[i]);
    }
    printf("\n");

end:
    if (memory != MAP_FAILED) munmap((void*)memory, PAGE_SIZE);
    if (fd > 0) close(fd);
    return ret;
}
