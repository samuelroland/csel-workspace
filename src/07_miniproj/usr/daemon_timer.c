#include <errno.h>
#include <stdio.h>
#include <sys/epoll.h>
#include <sys/timerfd.h>

#include "daemon.h"

int daemon_timer_create_event(daemon_t* daemon, int fd, daemon_event_cb cb)
{
    daemon_event_ctx_t timer_event = {
        .events = EPOLLIN, .fd = fd, .cb = cb, .event_data = NULL};

    /* ensure only one event exists at a time*/
    daemon_remove_event(daemon, daemon->io.timer_fd);
    return daemon_add_event(daemon, timer_event);
}

int daemon_timer_rearm(int timerfd, int period_ms)
{
    struct itimerspec its = {
        .it_interval = {0, 0},
        .it_value =
            {
                .tv_sec  = period_ms / 1000,
                .tv_nsec = (period_ms % 1000) * 1000000L,
            },
    };
    if (timerfd_settime(timerfd, 0, &its, NULL) < 0) {
        perror("timerfd_settime");
        return -errno;
    }
    return 0;
}
