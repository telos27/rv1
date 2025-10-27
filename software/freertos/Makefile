# FreeRTOS Makefile for RV1 RISC-V Core
# Target: RV32IMAFDC
# Created: 2025-10-27

PROJECT = freertos-rv1
PREFIX = riscv64-unknown-elf-
CC = $(PREFIX)gcc
OBJCOPY = $(PREFIX)objcopy
OBJDUMP = $(PREFIX)objdump
SIZE = $(PREFIX)size

ARCH = rv32imafdc
ABI = ilp32d

KERNEL_DIR = FreeRTOS-Kernel
PORT_DIR = port
CONFIG_DIR = config
DEMO_DIR = demos
LIB_DIR = lib
BUILD_DIR = build

HEAP_IMPL = $(KERNEL_DIR)/portable/MemMang/heap_4.c

KERNEL_SRCS = $(KERNEL_DIR)/tasks.c $(KERNEL_DIR)/queue.c $(KERNEL_DIR)/list.c \
              $(KERNEL_DIR)/timers.c $(KERNEL_DIR)/event_groups.c \
              $(KERNEL_DIR)/stream_buffer.c $(HEAP_IMPL)

PORT_SRCS = $(PORT_DIR)/port.c
PORT_ASM_SRCS = $(PORT_DIR)/start.S $(PORT_DIR)/portASM.S

DEMO_SRCS = $(DEMO_DIR)/blinky/main_blinky.c
LIB_SRCS = $(LIB_DIR)/uart.c $(LIB_DIR)/syscalls.c

C_SRCS = $(KERNEL_SRCS) $(PORT_SRCS) $(DEMO_SRCS) $(LIB_SRCS)
ASM_SRCS = $(PORT_ASM_SRCS)

INCLUDES = -I$(CONFIG_DIR) -I$(KERNEL_DIR)/include -I$(PORT_DIR) \
           -I$(PORT_DIR)/chip_specific_extensions -I$(LIB_DIR)

COMMON_FLAGS = -march=$(ARCH) -mabi=$(ABI) -g -Wall -Wextra \
               -Wno-unused-parameter -ffunction-sections -fdata-sections \
               --specs=/usr/lib/picolibc/riscv64-unknown-elf/picolibc.specs

CFLAGS = $(COMMON_FLAGS) -std=gnu11 -O2 $(INCLUDES)
ASFLAGS = $(COMMON_FLAGS) $(INCLUDES)
LDFLAGS = -march=$(ARCH) -mabi=$(ABI) -T$(PORT_DIR)/riscv32-freertos.ld \
          -nostartfiles --specs=/usr/lib/picolibc/riscv64-unknown-elf/picolibc.specs \
          -Wl,--gc-sections -Wl,-Map=$(BUILD_DIR)/$(PROJECT).map \
          -Wl,--print-memory-usage

LIBS = -lm

C_OBJS = $(addprefix $(BUILD_DIR)/, $(notdir $(C_SRCS:.c=.o)))
ASM_OBJS = $(addprefix $(BUILD_DIR)/, $(notdir $(ASM_SRCS:.S=.o)))
ALL_OBJS = $(C_OBJS) $(ASM_OBJS)

.PHONY: all clean blinky help

all: blinky

help:
	@echo "FreeRTOS Build System for RV1"
	@echo "  make blinky    - Build LED blinky demo"
	@echo "  make clean     - Remove build artifacts"

blinky: $(BUILD_DIR)/$(PROJECT).elf $(BUILD_DIR)/$(PROJECT).hex
	@echo "Built blinky demo successfully!"

$(BUILD_DIR)/$(PROJECT).elf: $(ALL_OBJS) | $(BUILD_DIR)
	@echo "Linking $@..."
	$(CC) $(LDFLAGS) -o $@ $(ALL_OBJS) $(LIBS)
	@$(SIZE) $@

$(BUILD_DIR)/$(PROJECT).hex: $(BUILD_DIR)/$(PROJECT).elf
	@echo "Generating hex file..."
	$(OBJCOPY) -O verilog $< $@

$(BUILD_DIR)/%.o: $(KERNEL_DIR)/%.c | $(BUILD_DIR)
	@echo "Compiling $<..."
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/%.o: $(KERNEL_DIR)/portable/MemMang/%.c | $(BUILD_DIR)
	@echo "Compiling $<..."
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/%.o: $(PORT_DIR)/%.c | $(BUILD_DIR)
	@echo "Compiling $<..."
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/%.o: $(LIB_DIR)/%.c | $(BUILD_DIR)
	@echo "Compiling $<..."
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/%.o: $(DEMO_DIR)/*/%.c | $(BUILD_DIR)
	@echo "Compiling $<..."
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/%.o: $(PORT_DIR)/%.S | $(BUILD_DIR)
	@echo "Assembling $<..."
	$(CC) $(ASFLAGS) -c $< -o $@

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

clean:
	rm -rf $(BUILD_DIR)
