#include <fcntl.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define INSTANCE_COUNT 3
#define DEV_NAME "/dev/mymodule"

typedef struct {
    int fd;
    char file_path[256];
    char wrote[20];
    size_t wrote_bytes;
} ctx_t;

static ctx_t ctx[INSTANCE_COUNT];

int main(void)
{
    int err = EXIT_SUCCESS;

    printf("opening devices...\n");
    for (size_t i = 0; i < INSTANCE_COUNT; ++i) {
        snprintf(ctx[i].file_path, sizeof(ctx[i].file_path), DEV_NAME "%zu", i);
        ctx[i].fd = open(ctx[i].file_path, O_RDWR);

        if (ctx[i].fd < 0) {
            fprintf(stderr, "failed to open %s\n", ctx[i].file_path);
            err = EXIT_FAILURE;
            goto end;
        }
    }

    printf("writing...\n");

    for (size_t i = 0; i < INSTANCE_COUNT; ++i) {
        int bytes =
            snprintf(ctx[i].wrote, sizeof(ctx[i].wrote), "Expected%zu", i);

        size_t bytes_to_write = bytes + 1;

        /* bytes + \0*/
        ssize_t n = write(ctx[i].fd, ctx[i].wrote, bytes_to_write);
        if (n < 0) {
            fprintf(stderr, "failed to write to %s\n", ctx[i].file_path);
            err = EXIT_FAILURE;
            goto end;
        }
        /* safe cast as per check above*/
        ctx[i].wrote_bytes = (size_t)n;

        printf("Wrote %s to %s...\n", ctx[i].wrote, ctx[i].file_path);
    }

    printf("reading...\n");

    for (size_t i = 0; i < INSTANCE_COUNT; ++i) {
        lseek(ctx[i].fd, 0, SEEK_SET);

        char actual[sizeof(ctx[i].wrote)];

        printf("Reading %zu bytes\n", ctx[i].wrote_bytes);
        ssize_t actual_bytes = read(ctx[i].fd, actual, ctx[i].wrote_bytes);

        if (actual_bytes != ctx[i].wrote_bytes) {
            fprintf(stderr,
                    "byte length mismatch. Expected %zu, Got %zd\n",
                    ctx[i].wrote_bytes,
                    actual_bytes);
            err = EXIT_FAILURE;
            continue;
        }

        if (memcmp(ctx[i].wrote, actual, ctx[i].wrote_bytes)) {
            fprintf(stderr,
                    "text mismatch. Expected %s, Got %s\n",
                    (char*)ctx[i].wrote,
                    (char*)actual);
            err = EXIT_FAILURE;
            continue;
        }
        printf("Test passed for %s\n", ctx[i].file_path);
    }

end:
    for (size_t i = 0; i < INSTANCE_COUNT; ++i) {
        if (ctx[i].fd <= 0) {
            continue;
        }
        close(ctx[i].fd);
    }

    return err;
}
