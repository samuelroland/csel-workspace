#ifndef GPIO_H
#define GPIO_H

#define GPIO_EXPORT "/sys/class/gpio/export"
#define GPIO_UNEXPORT "/sys/class/gpio/unexport"
#define GPIO "/sys/class/gpio/gpio"

typedef enum { GPIO_INPUT, GPIO_OUTPUT } gpio_dir_t;
typedef enum { GPIO_LOW, GPIO_HIGH } gpio_state_t;

typedef struct {
    const char* name;
    int fd;
    gpio_dir_t dir;
    gpio_state_t state;
} gpio_t;

int gpio_init(gpio_t* gpio);
void gpio_write(gpio_t* gpio, gpio_state_t state);
gpio_state_t gpio_read(gpio_t* gpio);
void gpio_deinit(gpio_t* gpio);

#endif /*GPIO_H*/
