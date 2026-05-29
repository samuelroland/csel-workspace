#ifndef DAEMON_IPC_PROTOCOL_H
#define DAEMON_IPC_PROTOCOL_H

#define DAEMON_IPC_SOCKET_PATH "/run/mydaemon.sock"

typedef enum {
    CMD_FREQ_UP     = 0x01,
    CMD_FREQ_DOWN   = 0x02,
    CMD_TOGGLE_MODE = 0x03,
} daemon_ipc_cmd_t;

typedef enum {
    RES_ERROR = 0x10,
    RES_FREQ  = 0x11,
    RES_MODE  = 0x12,
} daemon_ipc_response_type_t;

#endif /*DAEMON_IPC_PROTOCOL_H*/
