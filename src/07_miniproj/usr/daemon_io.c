#include <sys/epoll.h>

#include "daemon.h"
#include "daemon_key.h"

typedef int (*key_op_cb_t)(daemon_t* daemon, int*);
static void read_key_event(daemon_t* daemon, void* user_data);

int daemon_io_init(daemon_t* daemon)
{
    daemon_io_t* daemon_io = &daemon->io;

    int err = daemon_key_create(K1, &daemon_io->key_speed_up);
    if (err) {
        return err;
    }
    err = daemon_key_create(K2, &daemon_io->key_slow_down);
    if (err) {
        daemon_key_delete(&daemon_io->key_speed_up);
        return err;
    }
    err = daemon_key_create(K3, &daemon_io->key_mode);
    if (err) {
        daemon_key_delete(&daemon_io->key_speed_up);
        daemon_key_delete(&daemon_io->key_slow_down);
        return err;
    }

    daemon_event_ctx_t ctx[] = {
        {.events     = EPOLLERR,
         .fd         = daemon_key_get_fd(&daemon->io.key_speed_up),
         .cb         = read_key_event,
         .event_data = &daemon->io.key_speed_up},
        {.events     = EPOLLERR,
         .fd         = daemon_key_get_fd(&daemon->io.key_slow_down),
         .cb         = read_key_event,
         .event_data = &daemon->io.key_slow_down},
        {.events     = EPOLLERR,
         .fd         = daemon_key_get_fd(&daemon->io.key_mode),
         .cb         = read_key_event,
         .event_data = &daemon->io.key_mode},
    };

    const size_t ctx_count = sizeof(ctx) / sizeof(ctx[0]);
    for (size_t i = 0; i < ctx_count; ++i) {
        /* read so it doesn' trigger on start*/
        daemon_key_read(ctx[i].event_data);
        daemon_add_event(daemon, ctx[i]);
    }

    return 0;
}
int daemon_io_deinit(daemon_io_t* daemon_io)
{
    daemon_key_delete(&daemon_io->key_speed_up);
    daemon_key_delete(&daemon_io->key_slow_down);
    daemon_key_delete(&daemon_io->key_mode);
    return 0;
}

static void read_key_event(daemon_t* daemon, void* user_data)
{
    daemon_key_t* key = (daemon_key_t*)user_data;
    /* always read the key to reset epoll event */
    daemon_key_read(key);
    if (key == &daemon->io.key_speed_up) {
        daemon_increase_frequency(daemon, NULL);
    } else if (key == &daemon->io.key_slow_down) {
        daemon_decrease_frequency(daemon, NULL);
    } else {
        daemon_toggle_mode(daemon, NULL);
    }
}
