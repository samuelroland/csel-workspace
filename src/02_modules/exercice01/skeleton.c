#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/moduleparam.h>

static char* firstname = "?";
static char* lastname = "?";
static int min_temperature = 20;
module_param(firstname, charp, 0);
module_param(lastname, charp, 0);
module_param(min_temperature, int, 0);

static int __init skeleton_init(void) {
    pr_info("Linux module loaded !\n");
    pr_info("You are %s %s and your prefered min temperature is %d !\n",
            firstname, lastname, min_temperature);
    return 0;
}

static void __exit skeleton_exit(void) {
    pr_info("Linux module unloaded !\n");
    pr_info("Byebye %s %s \n", firstname, lastname);
}

module_init(skeleton_init);
module_exit(skeleton_exit);

MODULE_AUTHOR("Samuel Roland");
MODULE_DESCRIPTION("Empty module for testing");
MODULE_LICENSE("GPL");
