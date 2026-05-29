#include "gpio.h"

#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static int echo(const char* path, const char* value);
static gpio_state_t gpio_state_from_str(const char* str);
static const char* gpio_dir_to_str(gpio_dir_t dir);
static const char* gpio_state_to_str(gpio_state_t state);

int gpio_init(gpio_t* gpio)
{
    assert(gpio);
    assert(gpio->name);

    printf("Initializing gpio %s\n", gpio->name);

    char path[128];
    snprintf(path, sizeof(path), "%s%s", GPIO, gpio->name);
    int ret;
    if (access(path, F_OK) == 0) {
        ret = echo(GPIO_UNEXPORT, gpio->name);
        if (ret) {
            return ret;
        }
    }

    // export pin to sysfs
    ret = echo(GPIO_EXPORT, gpio->name);
    if (ret) {
        goto err;
    }

    // config pin
    const char* direction = gpio_dir_to_str(gpio->dir);
    snprintf(path, sizeof(path), "%s%s%s", GPIO, gpio->name, "/direction");
    ret = echo(path, direction);
    if (ret) {
        goto err;
    }

    if (gpio->dir == GPIO_INPUT) {
        snprintf(path, sizeof(path), "%s%s%s", GPIO, gpio->name, "/edge");
        ret = echo(path, "rising");
        if (ret) {
            goto err;
        }
    }

    snprintf(path, sizeof(path), "%s%s%s", GPIO, gpio->name, "/value");

    int f = open(path, O_RDWR);
    if (f < 0) {
        perror("open value");
        goto err;
    }

    // open gpio value attribute
    gpio->fd = f;
    return 0;

err: {
    if (echo(GPIO_UNEXPORT, gpio->name) < 0) {
        fprintf(stderr, "failed to unexport device after previous error");
    }
    return ret;
}
}
void gpio_write(gpio_t* gpio, gpio_state_t state)
{
    assert(gpio);
    assert(gpio->dir == GPIO_OUTPUT);
    const char* state_write = gpio_state_to_str(state);

    ssize_t len = pwrite(gpio->fd, state_write, strlen(state_write), 0);
    if (len < 0) {
        fprintf(stderr,
                "failed to write state %s: '%s'\n",
                gpio->name,
                strerror(errno));
        return;
    }
    gpio->state = state;
}

gpio_state_t gpio_read(gpio_t* gpio)
{
    assert(gpio);
    assert(gpio->dir == GPIO_INPUT);
    char state[8];
    ssize_t len = pread(gpio->fd, state, sizeof(state) - 1, 0);
    if (len < 0) {
        fprintf(stderr,
                "failed to read state %s: '%s'\n",
                gpio->name,
                strerror(errno));
        return GPIO_LOW;
    }
    assert(len > 0);
    state[len]  = '\0';
    gpio->state = gpio_state_from_str(state);
    return gpio->state;
}

void gpio_deinit(gpio_t* gpio)
{
    assert(gpio);

    int f = open(GPIO_UNEXPORT, O_WRONLY);
    write(f, gpio->name, strlen(gpio->name));
    close(f);
    close(gpio->fd);
}

static const char* gpio_dir_to_str(gpio_dir_t dir)
{
    switch (dir) {
        case GPIO_INPUT:
            return "in";
        case GPIO_OUTPUT:
            return "out";
    }
    assert(0);
}
static const char* gpio_state_to_str(gpio_state_t state)
{
    switch (state) {
        case GPIO_LOW:
            return "0";
        case GPIO_HIGH:
            return "1";
    }
    assert(0);
}
static gpio_state_t gpio_state_from_str(const char* str)
{
    switch (str[0]) {
        case '0':
            return GPIO_LOW;
        case '1':
            return GPIO_HIGH;
    }
    fprintf(stderr, "Invalid state %s\n", str);
    return GPIO_LOW;
}

static int echo(const char* path, const char* value)
{
    int f = open(path, O_WRONLY);
    if (f < 0) {
        fprintf(stderr, "failed to open '%s': '%s'\n", path, strerror(errno));
        return f;
    }
    ssize_t ret = write(f, value, strlen(value));
    close(f);
    if (ret < 0) {
        fprintf(stderr,
                "failed to write '%s' to %s': '%s'\n",
                value,
                path,
                strerror(errno));
        return ret;
    }
    return 0;
}
