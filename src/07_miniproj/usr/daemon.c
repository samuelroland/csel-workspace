#include "daemon.h"

#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/epoll.h>
#include <unistd.h>

#define DEVICE_PATH "/sys/bus/platform/devices/cpu-fan-ctrl"
#define MODE_PATH DEVICE_PATH "/mode"
#define FREQUENCY_PATH DEVICE_PATH "/frequency"

static int write_int(int fd, int value);
static int read_int(int fd, int* value);

int daemon_init(daemon_t* daemon)
{
    int err;
    memset(daemon, 0, sizeof(*daemon));

    err = epoll_create1(0);
    if (err < 0) {
        perror("epoll_create");
        return err;
    }
    daemon->epfd = err;

    err = open(MODE_PATH, O_RDWR);
    if (err < 0) {
        perror("open " MODE_PATH);
        goto mode_open_err;
    }
    daemon->mode_fd = err;

    err = open(FREQUENCY_PATH, O_RDWR);
    if (err < 0) {
        perror("open " FREQUENCY_PATH);
        goto freq_open_err;
    }
    daemon->freq_fd = err;

    err = daemon_io_init(daemon);
    if (err) {
        goto daemon_io_err;
    }
    err = daemon_ipc_init(daemon);
    if (err) {
        goto daemon_ipc_err;
    }

    return err;

daemon_ipc_err:
    daemon_io_deinit(&daemon->io);
daemon_io_err:
freq_open_err:
mode_open_err:
    if (daemon->freq_fd > 0) {
        close(daemon->freq_fd);
        daemon->freq_fd = 0;
    }
    if (daemon->mode_fd > 0) {
        close(daemon->mode_fd);
        daemon->mode_fd = 0;
    }

    if (daemon->epfd > 0) {
        close(daemon->epfd);
        daemon->epfd = 0;
    }
    return err;
}

int daemon_run(daemon_t* daemon)
{
    struct epoll_event* events = NULL;
    int err;
    size_t last_event_count = 0;
    while (1) {
        if (last_event_count != daemon->event_count) {
            struct epoll_event* new_events =
                realloc(events, sizeof(*events) * daemon->event_count);
            if (!new_events) {
                fprintf(stderr, "failed to allocate memory for epoll events");
                continue;
            }
            events = new_events;
        }

        memset(events, 0, sizeof(*events) * daemon->event_count);

        err = epoll_wait(daemon->epfd, events, daemon->event_count, -1);
        if (err < 0) {
            perror("epoll_wait");
            continue;
        }

        for (size_t i = 0; i < (size_t)err; ++i) {
            daemon_event_ctx_t* ctx = (daemon_event_ctx_t*)events[i].data.ptr;
            ctx->cb(daemon, ctx->event_data);
        }
    }
}
void daemon_deinit(daemon_t* daemon)
{
    daemon_ipc_deinit(&daemon->ipc);
    daemon_io_deinit(&daemon->io);
    free(daemon->events);
    daemon->events      = NULL;
    daemon->event_count = daemon->event_capacity = 0;
    if (daemon->epfd > 0) {
        close(daemon->epfd);
        daemon->epfd = 0;
    }
    if (daemon->mode_fd > 0) {
        close(daemon->mode_fd);
        daemon->mode_fd = 0;
    }
    if (daemon->freq_fd > 0) {
        close(daemon->freq_fd);
        daemon->freq_fd = 0;
    }
}

int daemon_add_event(daemon_t* daemon, daemon_event_ctx_t ctx)
{
    if (daemon->event_count == daemon->event_capacity) {
        size_t new_capacity =
            daemon->event_capacity == 0 ? 1 : daemon->event_capacity * 2;
        daemon_event_ctx_t* new_events =
            realloc(daemon->events, new_capacity * sizeof(*new_events));
        if (!new_events) {
            return -1;
        }
        daemon->events         = new_events;
        daemon->event_capacity = new_capacity;
    }
    daemon->events[daemon->event_count++] = ctx;
    daemon_event_ctx_t* new_ctx = &daemon->events[daemon->event_count - 1];
    struct epoll_event event    = {.events = new_ctx->events,
                                   .data   = {.ptr = new_ctx}};
    epoll_ctl(daemon->epfd, EPOLL_CTL_ADD, new_ctx->fd, &event);
    return 0;
}

void daemon_remove_event(daemon_t* daemon, int fd)
{
    for (size_t i = 0; i < daemon->event_count; ++i) {
        if (daemon->events[i].fd == fd) {
            epoll_ctl(daemon->epfd, EPOLL_CTL_DEL, fd, NULL);
            daemon->events[i] = daemon->events[daemon->event_count - 1];
            daemon->event_count--;
        }
    }
}

int daemon_get_mode(daemon_t* daemon, int* mode)
{
    return read_int(daemon->mode_fd, mode);
}

int daemon_set_mode(daemon_t* daemon, int mode)
{
    printf("Setting mode %d\n", mode);
    return write_int(daemon->mode_fd, mode);
}

int daemon_set_frequency(daemon_t* daemon, int frequency)
{
    printf("Setting frequency to %d\n", frequency);
    return write_int(daemon->freq_fd, frequency);
}
int daemon_get_frequency(daemon_t* daemon, int* frequency)
{
    return read_int(daemon->freq_fd, frequency);
}

int daemon_increase_frequency(daemon_t* daemon, int* new_freq)
{
    int freq;
    int err = daemon_get_frequency(daemon, &freq);
    if (err < 0) {
        fprintf(stderr, "failed to read frequency\n");
        return -1;
    }
    freq++;
    err = daemon_set_frequency(daemon, freq);
    if (err) {
        fprintf(stderr, "failed to set frequency\n");
        return err;
    }
    if (new_freq) {
        *new_freq = freq;
    }
    return err;
}

int daemon_decrease_frequency(daemon_t* daemon, int* new_freq)
{
    int freq;
    int err = daemon_get_frequency(daemon, &freq);
    if (err < 0) {
        fprintf(stderr, "failed to read frequency\n");
        return -1;
    }
    freq--;
    err = daemon_set_frequency(daemon, freq);
    if (err) {
        fprintf(stderr, "failed to set frequency\n");
        return err;
    }
    if (new_freq) {
        *new_freq = freq;
    }
    return err;
}

int daemon_toggle_mode(daemon_t* daemon, int* new_mode)
{
    int mode;
    int err = daemon_get_mode(daemon, &mode);
    if (err < 0) {
        fprintf(stderr, "failed to read current mode\n");
        return -1;
    }
    mode = !mode;
    err  = daemon_set_mode(daemon, mode);
    if (err) {
        fprintf(stderr, "failed to set mode\n");
        return err;
    }
    if (new_mode) {
        *new_mode = mode;
    }
    return err;
}

static int write_int(int fd, int value)
{
    char buffer[16];
    int n = snprintf(buffer, sizeof(buffer), "%d\n", value);
    return pwrite(fd, buffer, n, 0) != n;
}

static int read_int(int fd, int* value)
{
    char buffer[16];
    ssize_t n = pread(fd, buffer, sizeof(buffer), 0);
    if (n < 0) {
        perror("failed to read from driver\n");
        return n;
    }
    sscanf(buffer, "%d\n", value);
    return 0;
}
