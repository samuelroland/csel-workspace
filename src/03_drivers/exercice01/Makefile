EXE=app
EXE_SOL=app-sol

ifeq ($(target),)
target=nano
endif

CFLAGS=-Wall -Wextra -g -c -O0 -MD -std=gnu11 ${EXTRA_CFLAGS}
TOOLCHAIN_PATH=/buildroot/output/host/usr/bin/
TOOLCHAIN=$(TOOLCHAIN_PATH)aarch64-linux-
CFLAGS+=-mcpu=cortex-a53 -funwind-tables

OBJDIR=.obj/$(target)
OBJDIR_SOL=.obj/$(target)-sol

CC?=$(TOOLCHAIN)gcc
LD?=$(TOOLCHAIN)gcc
AR?=$(TOOLCHAIN)ar
STRIP?=$(TOOLCHAIN)strip

# Sources: all .c files except main.c and main.sol.c are shared
COMMON_SRCS=$(filter-out main.c main.sol.c, $(wildcard *.c))
COMMON_OBJS=$(addprefix $(OBJDIR)/, $(COMMON_SRCS:.c=.o))
COMMON_OBJS_SOL=$(addprefix $(OBJDIR_SOL)/, $(COMMON_SRCS:.c=.o))

MAIN_OBJ=$(OBJDIR)/main.o
MAIN_SOL_OBJ=$(OBJDIR_SOL)/main.sol.o

$(OBJDIR)/%.o: %.c
	$(CC) $(CFLAGS) $< -o $@

$(OBJDIR_SOL)/%.o: %.c
	$(CC) $(CFLAGS) $< -o $@

all: $(OBJDIR)/ $(OBJDIR_SOL)/ $(EXE) $(EXE_SOL)

$(EXE): $(COMMON_OBJS) $(MAIN_OBJ) $(LINKER_SCRIPT)
	$(LD) $(COMMON_OBJS) $(MAIN_OBJ) $(LDFLAGS) -o $@

$(EXE_SOL): $(COMMON_OBJS_SOL) $(MAIN_SOL_OBJ) $(LINKER_SCRIPT)
	$(LD) $(COMMON_OBJS_SOL) $(MAIN_SOL_OBJ) $(LDFLAGS) -o $@

$(OBJDIR)/:
	mkdir -p $(OBJDIR)

$(OBJDIR_SOL)/:
	mkdir -p $(OBJDIR_SOL)

clean:
	rm -Rf $(OBJDIR) $(OBJDIR_SOL) $(EXE) $(EXE_SOL) $(EXE)_s $(EXE_SOL)_s *~

clean_all: clean
	rm -Rf .obj $(EXE) $(EXE)_s $(EXE)_a $(EXE)_a_s $(EXE)_h $(EXE)_h_s \
	        $(EXE_SOL) $(EXE_SOL)_s $(EXE_SOL)_a $(EXE_SOL)_a_s

-include $(COMMON_OBJS:.o=.d)
-include $(MAIN_OBJ:.o=.d)
-include $(COMMON_OBJS_SOL:.o=.d)
-include $(MAIN_SOL_OBJ:.o=.d)

.PHONY: all clean clean_all
