/* skeleton.c */
#include <linux/cdev.h>      /* needed for char device driver */
#include <linux/fs.h>        /* needed for device drivers */
#include <linux/gpio.h>      /* needed for i/o handling */
#include <linux/init.h>      /* needed for macros */
#include <linux/interrupt.h> /* needed for interrupt handling */
#include <linux/io.h>        /* needed for mmio handling */
#include <linux/ioport.h>    /* needed for memory region handling */
#include <linux/kernel.h>    /* needed for debugging */
#include <linux/miscdevice.h>
#include <linux/module.h> /* needed by all modules */
#include <linux/poll.h>   /* needed for polling handling */
#include <linux/sched.h>  /* needed for scheduling constants */
#include <linux/types.h>
#include <linux/uaccess.h> /* needed to copy data to/from user */
#include <linux/wait.h>    /* needed for wating */

#include "linux/printk.h"

static const int K1 = 0;
static const int K2 = 2;
static const int K3 = 3;

static char* k1 = "gpio_a.0-k1";
static char* k2 = "gpio_a.2-k2";
static char* k3 = "gpio_a.3-k3";

static atomic_t nb_of_interrupts;
static int last_key;
DECLARE_WAIT_QUEUE_HEAD(queue);

irqreturn_t gpio_isr(int irq, void* handle)
{
    int key = *(int*)handle;
    atomic_inc(&nb_of_interrupts);
    last_key = key;
    wake_up_interruptible(&queue);

    pr_info("interrupt %d raised...\n", key);

    return IRQ_HANDLED;
}

static ssize_t skeleton_read(struct file* f,
                             char __user* buf,
                             size_t sz,
                             loff_t* off)
{
    char tmp[sizeof(int) + 1];
    int bytes;

    if (sz < sizeof(tmp)) {
        pr_err("sz is too small to hold buffer");
        return -EINVAL;
    }

    bytes = sprintf(tmp, "%d", last_key);
    if (copy_to_user(buf, tmp, bytes + 1)) {
        return -EFAULT;
    }
    return bytes + 1;
}

static unsigned int skeleton_poll(struct file* f, poll_table* wait)
{
    unsigned mask = 0;
    poll_wait(f, &queue, wait);
    if (atomic_read(&nb_of_interrupts) != 0) {
        mask |= POLLIN | POLLRDNORM; /* read operation */
        /* mask |= POLLOUT | POLLWRNORM;   write operation */
        atomic_dec(&nb_of_interrupts);
        pr_info("polling thread waked-up...\n");
    }
    return mask;
}

static struct file_operations skeleton_fops = {
    .owner = THIS_MODULE,
    .read  = skeleton_read,
    .poll  = skeleton_poll,
};

struct miscdevice misc_device = {
    .minor = MISC_DYNAMIC_MINOR,
    .fops  = &skeleton_fops,
    .name  = "mymodule",
    .mode  = 0777,
};

static int __init skeleton_init(void)
{
    int status = 0;

    atomic_set(&nb_of_interrupts, 0);

    status = misc_register(&misc_device);

    // install k1
    if (status == 0)
        status = devm_request_irq(misc_device.this_device,
                                  gpio_to_irq(K1),
                                  gpio_isr,
                                  IRQF_TRIGGER_FALLING | IRQF_SHARED,
                                  k1,
                                  (void*)&K1);

    // install k2
    if (status == 0)
        status = devm_request_irq(misc_device.this_device,
                                  gpio_to_irq(K2),
                                  gpio_isr,
                                  IRQF_TRIGGER_RISING | IRQF_SHARED,
                                  k2,
                                  (void*)&K2);

    // install k3
    if (status == 0)
        status = devm_request_irq(
            misc_device.this_device,
            gpio_to_irq(K3),
            gpio_isr,
            IRQF_TRIGGER_FALLING | IRQF_TRIGGER_RISING | IRQF_SHARED,
            k3,
            (void*)&K3);

    if (status) {
        misc_deregister(&misc_device);
    }

    pr_info("Linux module skeleton loaded(status=%d)\n", status);
    return status;
}

static void __exit skeleton_exit(void)
{
    misc_deregister(&misc_device);
    pr_info("Linux module skeleton unloaded\n");
}

module_init(skeleton_init);
module_exit(skeleton_exit);

MODULE_AUTHOR("Daniel Gachet <daniel.gachet@hefr.ch>");
MODULE_DESCRIPTION("Module skeleton");
MODULE_LICENSE("GPL");
