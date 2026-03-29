#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/moduleparam.h>
#include <linux/slab.h>

struct Element {
    char* text;
    unsigned id;
    struct list_head list;
};
static char* default_text = "?";
static int elements_count = 0;
module_param(default_text, charp, 0);
module_param(elements_count, int, 0);
static LIST_HEAD(ELEMENTS_LIST);
static unsigned last_used_id = 0;

static int __init skeleton_init(void)
{
    int i;
    struct Element* curr;
    struct Element* ptr;
    pr_info("Linux module loaded !\n");
    pr_info("Creating dynamically %d elements with default text '%s'!\n",
            elements_count,
            default_text);

    pr_info("Allocating elements\n");
    for (i = 0; i < elements_count; i++) {
        ptr = kzalloc(sizeof(struct Element), GFP_KERNEL);
        if (ptr != NULL) {
            ptr->text = default_text;
            ptr->id   = last_used_id++;
            list_add_tail(&ptr->list, &ELEMENTS_LIST);
        }
    }
    pr_info("Showing elements\n");
    list_for_each_entry(curr, &ELEMENTS_LIST, list)
    {
        pr_info("ID=%d, text=%s\n", curr->id, curr->text);
    }
    return 0;
}

static void __exit skeleton_exit(void)
{
    // This is based on
    // https://docs.kernel.org/core-api/list.html#traversing-whilst-removing-nodes
    struct Element* curr;
    struct Element* temp_storage; /* temporary storage for safe iteration */
    pr_info("Freeing and removing elements from the list\n");
    list_for_each_entry_safe(curr, temp_storage, &ELEMENTS_LIST, list)
    {
        pr_info("Freeing element with ID=%d\n", curr->id);
        list_del(&curr->list);
        kfree(curr);
    }
    pr_info("Linux module unloaded !\n");
}

module_init(skeleton_init);
module_exit(skeleton_exit);

MODULE_AUTHOR("Samuel Roland");
MODULE_DESCRIPTION("Testing kmalloc module for testing");
MODULE_LICENSE("GPL");
