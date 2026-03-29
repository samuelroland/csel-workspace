#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/ktime.h>
#include <linux/module.h>
#include <linux/moduleparam.h>
#include <linux/rtc.h>
#include <linux/slab.h>

static int __init skeleton_init(void)
{
    struct rtc_time t = rtc_ktime_to_tm(ktime_get_real());
    pr_info("Linux module loaded !\n");
    pr_emerg("Testing various logs levels at %ptRs\n", &t);

    pr_emerg("LOG with level 0 KERN_EMERG");
    pr_alert("LOG with level 1 KERN_ALERT");
    pr_crit("LOG with level 2 KERN_CRIT");
    pr_err("LOG with level 3 KERN_ERR");
    pr_warn("LOG with level 4 KERN_WARNING");
    pr_notice("LOG with level 5 KERN_NOTICE");
    pr_info("LOG with level 6 KERN_INFO");
    pr_info("LOG with level 7 KERN_DEBUG\n");
    return 0;
}

static void __exit skeleton_exit(void) { pr_info("Linux module unloaded !\n"); }

module_init(skeleton_init);
module_exit(skeleton_exit);

MODULE_AUTHOR("Samuel Roland");
MODULE_DESCRIPTION("Testing log levels module");
MODULE_LICENSE("GPL");
