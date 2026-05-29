#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include "daemon.h"
#include "daemon_ipc_protocol.h"

static void ipc_read_cb(daemon_t* daemon, void* event_data);
static void ipc_accept_cb(daemon_t* daemon, void* data);
static inline void send_error(int fd);
static inline void send_value(int fd,
                              daemon_ipc_response_type_t type,
                              int value);

int daemon_ipc_init(daemon_t* daemon)
{
    struct sockaddr_un addr = {.sun_family = AF_UNIX};
    strncpy(addr.sun_path, DAEMON_IPC_SOCKET_PATH, sizeof(addr.sun_path) - 1);

    int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
    if (fd < 0) {
        perror("ipc: socket");
        return -1;
    }
    /* remove stale socket from previous run */
    unlink(DAEMON_IPC_SOCKET_PATH);

    if (bind(fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        perror("ipc: bind");
        close(fd);
        return -1;
    }
    if (listen(fd, 8) < 0) {
        perror("ipc: listen");
        close(fd);
        return -1;
    }
    daemon->ipc.server_fd = fd;

    daemon_event_ctx_t ctx = {.events     = EPOLLIN,
                              .fd         = fd,
                              .cb         = ipc_accept_cb,
                              .event_data = (void*)(uintptr_t)fd};

    return daemon_add_event(daemon, ctx);
}

void daemon_ipc_deinit(daemon_ipc_t* ipc)
{
    if (ipc->server_fd > 0) {
        close(ipc->server_fd);
        ipc->server_fd = 0;
    }
    unlink(DAEMON_IPC_SOCKET_PATH);
}

static void ipc_accept_cb(daemon_t* daemon, void* data)
{
    (void)data;
    int client_fd = accept4(
        daemon->ipc.server_fd, NULL, NULL, SOCK_NONBLOCK | SOCK_CLOEXEC);

    if (client_fd < 0) {
        perror("accept4");
        return;
    }

    daemon_event_ctx_t ctx = {
        .fd         = client_fd,
        .events     = EPOLLIN,
        .cb         = ipc_read_cb,
        .event_data = (void*)(uintptr_t)client_fd,
    };

    if (daemon_add_event(daemon, ctx) < 0) {
        fprintf(stderr, "daemon_add_event failed\n");
        close(client_fd);
    }
}
static void ipc_read_cb(daemon_t* daemon, void* event_data)
{
    int fd = (int)(uintptr_t)event_data;

    uint8_t byte;
    ssize_t n = read(fd, &byte, 1);

    if (n == 0 || (n < 0 && errno != EAGAIN)) {
        /* Client disconnected or hard error */
        daemon_remove_event(daemon, fd);
        close(fd);
        return;
    }
    if (n < 0) return;

    int err = 0;

    switch ((daemon_ipc_cmd_t)byte) {
        case CMD_FREQ_UP: {
            int new_freq;
            err = daemon_increase_frequency(daemon, &new_freq);
            if (err) {
                send_error(fd);
            } else {
                send_value(fd, RES_FREQ, new_freq);
            }
        } break;

        case CMD_FREQ_DOWN: {
            int new_freq;
            err = daemon_decrease_frequency(daemon, &new_freq);
            if (err) {
                send_error(fd);
            } else {
                send_value(fd, RES_FREQ, new_freq);
            }
        } break;

        case CMD_TOGGLE_MODE: {
            int new_mode;
            err = daemon_toggle_mode(daemon, &new_mode);
            if (err) {
                send_error(fd);
            } else {
                send_value(fd, RES_MODE, new_mode);
            }
        } break;

        default:
            fprintf(stderr, "ipc: unknown command 0x%02x, discarding\n", byte);
            send_error(fd);
            break;
    }
}

static inline void send_value(int fd,
                              daemon_ipc_response_type_t type,
                              int value)
{
    write(fd, &type, 1);
    write(fd, &value, sizeof(value));
}
static inline void send_error(int fd)
{
    uint8_t value = RES_ERROR;
    write(fd, &value, 1);
}
