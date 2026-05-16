#define _GNU_SOURCE
#include <asm-generic/errno-base.h>
#include <errno.h>
#include <sched.h>
#include <signal.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

void ignore(int signal) { printf("Ignored signal %d\n", signal); }

void constrain_current_process_on_core(int core_idx) {
    cpu_set_t set;
    CPU_ZERO(&set);
    CPU_SET(core_idx, &set);
    sched_setaffinity(getpid(), sizeof(set), &set);
}
#define MESSAGE_LEN 10
#define EXIT_CMD "exit"

// Safe version of write() resisting waking up via signals.
void safe_write(int fd, const void* buf, size_t len) {
    int res = write(fd, buf, len);
    while (res < len) {
        if (res < 0) {
            if (errno == EINTR) {  // if EINTR, no byte were written at all
                perror("EINTR in write");
                res = write(fd, buf, len);
            } else {  // another error, cannot recover
                perror("Failed to write");
                exit(EXIT_FAILURE);
            }
        } else {  // write the remaining bytes
            len -= res;
            buf += res;
            res = write(fd, buf, len);
        }
    }
}

void safe_read_msg(int fd, char* message, size_t buflen) {
    int res = read(fd, message, buflen);
    while (res < buflen) {
        if (res == 0) break;
        if (res < 0) {
            if (errno == EINTR) {
                perror("EINTR in read");
                res = read(fd, message, buflen);
            } else {
                perror("Failed to read");
                exit(EXIT_FAILURE);
            }
        } else {  // partial read
            buflen -= res;
            message += res;
            res = read(fd, message, buflen);
        }
    }
}

int main(int argc, char* argv[]) {
    struct sigaction action = {.sa_handler = ignore};
    sigaction(SIGHUP, &action, NULL);
    sigaction(SIGINT, &action, NULL);
    sigaction(SIGQUIT, &action, NULL);
    sigaction(SIGABRT, &action, NULL);
    sigaction(SIGTERM, &action, NULL);

    printf("Procs\n");
    int fd[2];
    int err = socketpair(AF_UNIX, SOCK_STREAM, 0, fd);
    if (err < 0) {
        perror("Error: creating socketpair");
        exit(2);
    }
    int pid = fork();
    if (pid < 0) {
        perror("Fork has failed");
        exit(EXIT_FAILURE);
    }
    if (pid == 0) {
        // child code
        printf("child: Child process started !\n");
        constrain_current_process_on_core(1);
        close(fd[0]);
        char message[MESSAGE_LEN];
        for (int i = 0; i < 4; i++) {
            printf("child: Sending message %d to parent\n", i);
            snprintf(message, MESSAGE_LEN, "Hello %d", i);
            safe_write(fd[1], message, MESSAGE_LEN);
            sleep(1);
        }
        printf("child: Sending exit command to parent\n");
        safe_write(fd[1], EXIT_CMD, MESSAGE_LEN);
        close(fd[1]);
        exit(EXIT_SUCCESS);
    } else {
        // parent code
        printf("parent: Parent process continues !\n");
        constrain_current_process_on_core(0);
        close(fd[1]);
        char message[MESSAGE_LEN];
        message[0] = '\0';
        while (strncmp(message, EXIT_CMD, strlen(EXIT_CMD)) != 0) {
            printf("parent: Waiting for messages from child\n");
            safe_read_msg(fd[0], message, MESSAGE_LEN);
            printf("parent: Got message: '%s'\n", message);
        }
        close(fd[0]);
        waitpid(pid, NULL, 0);
        exit(EXIT_SUCCESS);
    }
    return 0;
}
