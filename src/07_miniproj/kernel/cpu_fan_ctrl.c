#include <linux/gpio.h>
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/thermal.h>

#define DRIVER_NAME "cpu-fan-ctrl"

#define GPIO_LED 10
#define TEMPERATURE_FACTOR 1000

static const char* led_name = "gpio_a.10-led";

/* driver data structures */
enum mode { MODE_MANUAL, MODE_AUTO };

struct dev_data {
    struct timer_list fan_timer;
    struct delayed_work temperature_work;
    struct thermal_zone_device* tzd;
    atomic_t temperature;
    atomic_t mode;
    atomic_t hz;
    bool led_state;
};

/* temperature*/
static inline uint32_t temperature_to_hz(int temperature)
{
    if (temperature < 35) {
        return 2;
    } else if (temperature < 40) {
        return 5;
    } else if (temperature < 45) {
        return 10;
    } else {
        return 20;
    }
}

static void temperature_work_callback(struct work_struct* work)
{
    struct dev_data* dd =
        container_of(work, struct dev_data, temperature_work.work);
    int temperature;

    if (thermal_zone_get_temp(dd->tzd, &temperature)) {
        schedule_delayed_work(&dd->temperature_work, HZ);
        return;
    }

    temperature /= TEMPERATURE_FACTOR;

    atomic_set(&dd->temperature, temperature);
    if (atomic_read(&dd->mode) == MODE_AUTO) {
        atomic_set(&dd->hz, temperature_to_hz(temperature));
    }
    schedule_delayed_work(&dd->temperature_work, HZ);
}

/* timer */
static unsigned long freq_to_jiffies(int hz)
{
    return HZ / hz / 2; /* divide by 2: on + off = 1 period*/
}

static inline int rearm_timer(struct dev_data* dd)
{
    int hz = atomic_read(&dd->hz);
    return mod_timer(&dd->fan_timer, jiffies + freq_to_jiffies(hz));
}

static void timer_callback(struct timer_list* timer)
{
    struct dev_data* dd = container_of(timer, struct dev_data, fan_timer);

    dd->led_state = !dd->led_state;
    gpio_set_value(GPIO_LED, dd->led_state);
    rearm_timer(dd);
}

/* sysfs */
ssize_t mode_show(struct device* dev, struct device_attribute* attr, char* buf)
{
    struct dev_data* dd = (struct dev_data*)dev_get_drvdata(dev);

    int mode = atomic_read(&dd->mode);
    return sysfs_emit(buf, "%d\n", mode);
}

ssize_t mode_store(struct device* dev,
                   struct device_attribute* attr,
                   const char* buf,
                   size_t count)
{
    struct dev_data* dd = (struct dev_data*)dev_get_drvdata(dev);
    int mode;
    int ret;
    ret = kstrtoint(buf, 10, &mode);
    if (ret) {
        return ret;
    }
    atomic_set(&dd->mode, mode);

    /* if we go from manual to auto, update the frequency based on the
     * temperature on next timer run*/
    pr_info("mode set to %d", mode);
    return count;
}
ssize_t frequency_show(struct device* dev,
                       struct device_attribute* attr,
                       char* buf)
{
    struct dev_data* dd = (struct dev_data*)dev_get_drvdata(dev);

    int hz = atomic_read(&dd->hz);
    return sysfs_emit(buf, "%d\n", hz);
}

ssize_t frequency_store(struct device* dev,
                        struct device_attribute* attr,
                        const char* buf,
                        size_t count)
{
    struct dev_data* dd = (struct dev_data*)dev_get_drvdata(dev);
    int hz;
    int ret;
    int mode = atomic_read(&dd->mode);
    if (mode != MODE_MANUAL) {
        pr_err("device is not in manual mode");
        return -EINVAL;
    }
    ret = kstrtoint(buf, 10, &hz);
    if (ret) {
        return ret;
    }
    if (hz <= 0) {
        return -EINVAL;
    }
    atomic_set(&dd->hz, hz);
    pr_info("frequency set to %d", hz);
    return count;
}

ssize_t temperature_show(struct device* dev,
                         struct device_attribute* attr,
                         char* buf)
{
    struct dev_data* dd = (struct dev_data*)dev_get_drvdata(dev);

    int temperature = atomic_read(&dd->temperature);
    return sysfs_emit(buf, "%d\n", temperature);
}

DEVICE_ATTR_RO(temperature);
DEVICE_ATTR_RW(mode);
DEVICE_ATTR_RW(frequency);

/* platform device */

static int fan_probe(struct platform_device* pdev)
{
    struct thermal_zone_device* tzd;
    struct dev_data* dd;
    int ret;

    dd = (struct dev_data*)devm_kzalloc(&pdev->dev, sizeof(*dd), GFP_KERNEL);
    if (!dd) {
        return -ENOMEM;
    }
    dev_set_drvdata(&pdev->dev, dd);

    tzd = thermal_zone_get_zone_by_name("cpu-thermal");
    if (IS_ERR(tzd)) {
        return PTR_ERR(tzd);
    }

    ret = devm_gpio_request(&pdev->dev, GPIO_LED, led_name);
    if (ret) {
        return ret;
    }
    ret = gpio_direction_output(GPIO_LED, 0);
    if (ret) {
        return ret;
    }

    ret = device_create_file(&pdev->dev, &dev_attr_frequency);
    if (ret) {
        return ret;
    }
    ret = device_create_file(&pdev->dev, &dev_attr_mode);
    if (ret) {
        device_remove_file(&pdev->dev, &dev_attr_frequency);
        return ret;
    }
    ret = device_create_file(&pdev->dev, &dev_attr_temperature);
    if (ret) {
        device_remove_file(&pdev->dev, &dev_attr_frequency);
        device_remove_file(&pdev->dev, &dev_attr_mode);
        return ret;
    }

    timer_setup(&dd->fan_timer, timer_callback, 0);
    INIT_DELAYED_WORK(&dd->temperature_work, temperature_work_callback);
    schedule_delayed_work(&dd->temperature_work, 0);

    dd->tzd       = tzd;
    dd->led_state = false;
    /* ensure hz is never == 0 to avoid a division by zero*/
    atomic_set(&dd->hz, 1);
    atomic_set(&dd->mode, MODE_AUTO);
    rearm_timer(dd);
    pr_info("fan probed");
    return 0;
}

static int fan_remove(struct platform_device* pdev)
{
    struct dev_data* dd = (struct dev_data*)dev_get_drvdata(&pdev->dev);

    device_remove_file(&pdev->dev, &dev_attr_mode);
    device_remove_file(&pdev->dev, &dev_attr_frequency);
    device_remove_file(&pdev->dev, &dev_attr_temperature);
    del_timer_sync(&dd->fan_timer);
    cancel_delayed_work_sync(&dd->temperature_work);
    return 0;
}

static struct platform_device* fan_pdev;
static struct platform_driver fan_drv = {
    .driver = {.name = DRIVER_NAME, .owner = THIS_MODULE},
    .probe  = fan_probe,
    .remove = fan_remove,

};

static int __init fan_init(void)
{
    int ret;

    fan_pdev = platform_device_register_simple(DRIVER_NAME, -1, NULL, 0);
    if (IS_ERR(fan_pdev)) {
        return PTR_ERR(fan_pdev);
    }

    ret = platform_driver_register(&fan_drv);
    if (ret) {
        goto pdriver_register_err;
    }
    pr_info(DRIVER_NAME " driver loaded\n");
    return 0;
    platform_driver_unregister(&fan_drv);
pdriver_register_err:
    platform_device_unregister(fan_pdev);
    return ret;
}

static void __exit fan_exit(void)
{
    platform_driver_unregister(&fan_drv);
    platform_device_unregister(fan_pdev);

    pr_info(DRIVER_NAME " driver unloaded\n");
}
module_init(fan_init);
module_exit(fan_exit);

MODULE_AUTHOR("André Costa <andre_miguel_costa@hotmail.com");
MODULE_DESCRIPTION("CPU Fan Control Management");
MODULE_LICENSE("GPL");
