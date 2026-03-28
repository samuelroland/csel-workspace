
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/poll.h>
#include <unistd.h>

#define DEV_NAME "/dev/mymodule"

int main(void)
{
    int fd = open(DEV_NAME, O_RDWR);
    if (fd < 0) {
        fprintf(stderr, "failed to open %s (%s)", DEV_NAME, strerror(errno));
        return EXIT_FAILURE;
    }

    printf("Press any (physical) button\n");
    struct pollfd fds = {.fd = fd, .events = POLLIN};

    int ret = poll(&fds, 1, -1);
    if (ret < 1) {
        fprintf(stderr, "poll failed: %s\n", strerror(errno));
        close(fd);
        return EXIT_FAILURE;
    }
    char tmp[8];
    ret = read(fd, tmp, sizeof(tmp));
    if (ret <= 0) {
        fprintf(
            stderr, "Button pressed but couldn't read what it was %d\n", ret);
        close(fd);
        return EXIT_FAILURE;
    }
    printf("You pressed button %s!\n", tmp);
    close(fd);
    return EXIT_SUCCESS;
}
