#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/errno.h>
#include <sys/mman.h>
#include <unistd.h>

int main(void)
{
    /* open memory file descriptor */
    int fd = open("/dev/mem", O_RDWR);
    if (fd < 0) {
        printf("Could not open /dev/mem: error=%i\n", fd);
        return -1;
    }

    size_t psz     = getpagesize();
    off_t dev_addr = 0x01c14200;
    off_t ofs      = dev_addr % psz;
    off_t offset   = dev_addr - ofs;
    printf(
        "psz=%lx, addr=%lx, offset=%lx, ofs=%lx\n", psz, dev_addr, offset, ofs);

    /* map to user space nanopi internal registers */
    volatile uint32_t* regs =
        mmap(0, psz, PROT_READ | PROT_WRITE, MAP_SHARED, fd, offset);

    if (regs == MAP_FAILED)  // (void *)-1
    {
        printf("mmap failed, error: %i:%s \n", errno, strerror(errno));
        return -1;
    }

    uint32_t chipid[4] = {
        [0] = *(regs + (ofs + 0x00) / sizeof(uint32_t)),
        [1] = *(regs + (ofs + 0x04) / sizeof(uint32_t)),
        [2] = *(regs + (ofs + 0x08) / sizeof(uint32_t)),
        [3] = *(regs + (ofs + 0x0c) / sizeof(uint32_t)),
    };

    printf("NanoPi NEO Plus2 chipid=%08x'%08x'%08x'%08x\n",
           chipid[0],
           chipid[1],
           chipid[2],
           chipid[3]);

    munmap((void*)regs, psz);
    close(fd);

    return 0;
}
