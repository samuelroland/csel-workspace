#include "daemon.h"

int main(void)
{
    daemon_t daemon;
    int err = daemon_init(&daemon);
    if (err) {
        return err;
    }
    err = daemon_run(&daemon);
    daemon_deinit(&daemon);
    return err;
}
