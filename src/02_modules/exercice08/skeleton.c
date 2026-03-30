/* skeleton.c */
#include <linux/gpio.h>      /* needed for i/o handling */
#include <linux/init.h>      /* needed for macros */
#include <linux/interrupt.h> /* needed for interrupt handling */
#include <linux/kernel.h>    /* needed for debugging */
#include <linux/module.h>    /* needed by all modules */

irqreturn_t press_button_logger(int irq, void* dev_id) {
    pr_info("received IRQ %d => pressed button %s\n", irq, dev_id);
    return IRQ_HANDLED;
}

#define N1 0
#define N2 2
#define N3 3

#define N1isrid "btn1-isr"
#define N2isrid "btn2-isr"
#define N3isrid "btn3-isr"

static int __init skeleton_init(void) {
    int status = gpio_request(N1, "bouton 1");
    if (status < 0) {
        pr_warn("Error: could not gpio_request for button 1\n");
        return -1;
    }
    request_irq(gpio_to_irq(N1), press_button_logger, IRQF_SHARED, "btn1",
                N1isrid);
    status = gpio_request(N2, "bouton 2");
    if (status < 0) {
        pr_warn("Error: could not gpio_request for button 2\n");
        return -1;
    }
    request_irq(gpio_to_irq(N2), press_button_logger, IRQF_SHARED, "btn2",
                N2isrid);
    status = gpio_request(N3, "bouton 3");
    if (status < 0) {
        pr_warn("Error: could not gpio_request for button 3\n");
        return -1;
    }
    request_irq(gpio_to_irq(N3), press_button_logger, IRQF_SHARED, "btn3",
                N3isrid);

    pr_info("Linux module 08 skeleton loaded\n");
    return status;
}

static void __exit skeleton_exit(void) {
    gpio_free(N1);
    free_irq(gpio_to_irq(N1), N1isrid);
    gpio_free(N2);
    free_irq(gpio_to_irq(N2), N2isrid);
    gpio_free(N3);
    free_irq(gpio_to_irq(N3), N3isrid);

    pr_info("Linux module skeleton unloaded\n");
}

module_init(skeleton_init);
module_exit(skeleton_exit);

MODULE_AUTHOR("Daniel Gachet <daniel.gachet@hefr.ch>");
MODULE_DESCRIPTION("Module skeleton");
MODULE_LICENSE("GPL");
