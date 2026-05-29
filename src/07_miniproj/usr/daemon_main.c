#include "daemon.h"

int main(void)
{
    daemon_t daemon;
    daemon_init(&daemon);
    daemon_run(&daemon);
    daemon_deinit(&daemon);
}
