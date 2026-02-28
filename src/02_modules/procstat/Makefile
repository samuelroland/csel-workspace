EXE=procstat
SRCS=$(wildcard *.c) 

ifeq ($(TARGET), host)
CC?=gcc
LD?=gcc
STRIP?=strip
CFLAGS=-Wall -Wextra -g -c -O0 -MD -std=c99 ${EXTRA_CFLAGS}
OBJDIR?=.obj/host
EXEC=$(EXE)_h

else
TOOLCHAIN_PATH=/buildroot/output/host/usr/bin/
TOOLCHAIN=$(TOOLCHAIN_PATH)aarch64-buildroot-linux-gnu-

CC?=$(TOOLCHAIN)gcc
LD?=$(TOOLCHAIN)gcc
STRIP?=$(TOOLCHAIN)strip

CFLAGS+=-pedantic -Wall -Wextra -g -c -mcpu=cortex-a53 -O0 -MD -std=gnu11
CPPFLAGS+=-pedantic -Wall -Wextra -g -c -mcpu=cortex-a53 -O0 -MD -std=gnu11

OBJDIR=.obj/odroid
EXEC=$(EXE)
endif

OBJS= $(addprefix $(OBJDIR)/, $(ASRC:.s=.o) $(SRCS:.c=.o))

all: $(OBJDIR)/ $(EXEC)
	
$(EXEC): $(OBJS) $(LINKER_SCRIPT)
	$(LD) $(OBJS) $(LDFLAGS) -o $@_s 
	$(STRIP) -g -o $@ $@_s 

$(OBJDIR)/%o: %c
	$(CC) $(CFLAGS) $< -o $@
	
$(OBJDIR)/:
	mkdir -p $(OBJDIR)

clean:
	rm -Rf $(OBJDIR) $(EXEC) $(EXEC)_s

clean_all: 
	rm -Rf .obj $(EXE) $(EXE)_h $(EXE)_s $(EXE)_h_s *~


.PHONY: all clean clean_all

-include $(OBJS:.o=.d)
