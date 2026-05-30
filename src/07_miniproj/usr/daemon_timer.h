#ifndef DAEMON_TIMER_H
#define DAEMON_TIMER_H

#include "daemon.h"

int daemon_timer_create_event(daemon_t* daemon, int fd, daemon_event_cb cb);
int daemon_timer_rearm(int timerfd, int period_ms);

#endif /*DAEMON_TIMER_H*/
