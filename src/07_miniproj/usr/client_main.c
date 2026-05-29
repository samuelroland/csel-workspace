#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include "daemon_ipc_protocol.h"

int send_cmd(daemon_ipc_cmd_t cmd)
{
    int sock_fd;
    struct sockaddr_un addr;

    // Create UNIX domain stream socket
    if ((sock_fd = socket(AF_UNIX, SOCK_STREAM, 0)) == -1) {
        perror("socket error");
        return -1;
    }

    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, DAEMON_IPC_SOCKET_PATH, sizeof(addr.sun_path) - 1);

    if (connect(sock_fd, (struct sockaddr*)&addr, sizeof(addr)) == -1) {
        perror("connect error (is the daemon running?)");
        close(sock_fd);
        return -1;
    }

    uint8_t payload = (uint8_t)cmd;
    if (write(sock_fd, &payload, sizeof(payload)) != sizeof(payload)) {
        perror("write error");
        close(sock_fd);
        return -1;
    }
    uint8_t buffer[16];
    if (read(sock_fd, buffer, sizeof(buffer)) < 0) {
        perror("read error");
        close(sock_fd);
        return -1;
    }
    daemon_ipc_response_type_t response_type = buffer[0];
    switch (response_type) {
        case RES_ERROR:
            fprintf(stderr, "Error\n");
            break;
        case RES_FREQ:
            printf("New Frequency: %d\n", *(int*)buffer + 1);
            break;
        case RES_MODE:
            printf("New Mode: %d\n", *(int*)buffer + 1);
            break;
    }

    close(sock_fd);
    return 0;
}

// Parses string input into the corresponding enum
int parse_and_send(const char* cmd_str)
{
    if (strcasecmp(cmd_str, "up") == 0) {
        printf("Sending CMD_FREQ_UP (0x01)...\n");
        return send_cmd(CMD_FREQ_UP);
    } else if (strcasecmp(cmd_str, "down") == 0) {
        printf("Sending CMD_FREQ_DOWN (0x02)...\n");
        return send_cmd(CMD_FREQ_DOWN);
    } else if (strcasecmp(cmd_str, "toggle") == 0) {
        printf("Sending CMD_TOGGLE_MODE (0x03)...\n");
        return send_cmd(CMD_TOGGLE_MODE);
    } else {
        printf("Unknown command: %s\n", cmd_str);
        return -1;
    }
}

void print_usage(const char* prog_name)
{
    printf("Usage:\n");
    printf("  Single command:    %s <up | down | toggle>\n", prog_name);
    printf("  Interactive mode:  %s -i\n", prog_name);
}

void run_interactive_mode()
{
    char input[256];
    printf("--- Fan Control Daemon CLI Interactive Mode ---\n");
    printf("Available commands: up, down, toggle, exit\n\n");

    while (1) {
        printf("fan-ctrl-cli> ");
        fflush(stdout);

        if (!fgets(input, sizeof(input), stdin)) {
            break;
        }

        // Strip newline character
        input[strcspn(input, "\n")] = 0;

        // Skip empty inputs
        if (strlen(input) == 0) {
            continue;
        }

        // Exit condition
        if (strcasecmp(input, "exit") == 0 || strcasecmp(input, "quit") == 0) {
            printf("Exiting interactive mode.\n");
            break;
        }

        parse_and_send(input);
    }
}

int main(int argc, char* argv[])
{
    if (argc < 2) {
        print_usage(argv[0]);
        return EXIT_FAILURE;
    }

    // Check for interactive flag
    if (strcmp(argv[1], "-i") == 0) {
        run_interactive_mode();
    } else {
        // Run single command mode
        if (parse_and_send(argv[1]) != 0) {
            return EXIT_FAILURE;
        }
    }

    return EXIT_SUCCESS;
}
