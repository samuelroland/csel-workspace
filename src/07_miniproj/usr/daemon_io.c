#include <sys/epoll.h>

#include "daemon.h"
#include "daemon_key.h"

typedef int (*key_op_cb_t)(daemon_t* daemon, int*);
static void read_key_event(daemon_t* daemon, void* user_data);

int daemon_io_init(daemon_t* daemon)
{
    daemon_io_t* daemon_io = &daemon->io;

    struct {
        const char* name;
        daemon_key_t* key;
    } keys[] = {{.name = K1, .key = &daemon_io->key_speed_up},
                {.name = K2, .key = &daemon_io->key_speed_up},
                {.name = K3, .key = &daemon_io->key_speed_up}};

    const size_t key_count = sizeof(keys) / sizeof(keys[0]);

    for (size_t i = 0; i < key_count; ++i) {
        int err = daemon_key_create(keys[i].name, keys[i].key);
        if (err) {
            goto key_create_err;
        }

        /* dummy read so it doesn' trigger on start*/
        (void)daemon_key_read(keys[i].key);

        daemon_event_ctx_t ev_ctx = {.events = EPOLLERR,
                                     .fd     = daemon_key_get_fd(keys[i].key),
                                     .cb     = read_key_event,
                                     .event_data = keys[i].key};

        err = daemon_add_event(daemon, ev_ctx);
        if (err) {
            goto add_event_err;
        }
        continue;

    add_event_err:
        for (size_t j = 0; j < i; ++j) {
            daemon_remove_event(daemon, daemon_key_get_fd(keys[i].key));
        }
        daemon_key_delete(keys[i].key);
    key_create_err:

        for (size_t j = 0; j < i; ++j) {
            daemon_key_delete(keys[j].key);
        }
        return err;
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
