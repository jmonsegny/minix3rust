# Grub put us in 32 bit protected mode
# Initial code is 32 bit, and activates 
# the 64 bit mode


#######################################
# Text 32 bits
#######################################

.code32
.global _start

MB_MAGIC = 0x1BADB002
MB_FLAGS = 0x3
MB_VIDEO_MODE_EGA = 1
MB_CONSOLE_LINES = 25
MB_CONSOLE_COLS = 80

PAGES_PRESENT = 0x1
PAGES_RW = 0x2
PAGES_4MB_SIZE = 1 << 7
CR4_ENABLE_PAE = 1 << 5
LONG_MODE_ENABLE = 0xC0000080
CR0_ENABLE_PAGING = 1 << 31

.section .text

# Entry point declared in linker.ld
_start:
	jmp over

	.balign 8  # It must be aligned or Grub won't find it
    .long MB_MAGIC
    .long MB_FLAGS
    .long -(MB_MAGIC + MB_FLAGS)
    .long 0
    .long 0
    .long 0
    .long 0
    .long 0
    .long MB_VIDEO_MODE_EGA
    .long MB_CONSOLE_COLS
    .long MB_CONSOLE_LINES
    .long 0
	
over:
# We need a stack
	mov $load_stack_start, %esp
	mov $0, %ebp
	push $0

# Save multiboot address and magic number to temp space
	mov %ebx, (multiboot) # Multiboot struct
	mov %eax, (magic)     # Multiboot magic number

check_cpu:	
    call check_cpuid
    call check_long_mode

    cli

    lidt zero_idt         # Load a zero IDT for detect nmi

set_up_page_tables:
# Init buffer for page tables
    mov $page_table_start, %edi
    mov $page_table_end, %ecx
    sub %edi, %ecx
    shr $2, %ecx
    xor %eax, %eax
    rep stosl

# p4
    mov $p3, %eax  # Address of p3
    or $(PAGES_PRESENT | PAGES_RW), %eax     # R/W | P bit
    mov %eax, (p4)       # Store in 1st p4 entry 
# p3
    mov $p2, %eax
    or $(PAGES_PRESENT | PAGES_RW), %eax
    mov %eax, (p3)
# p2
    mov $(PAGES_PRESENT | PAGES_RW | PAGES_4MB_SIZE), %eax
    mov $0, %ecx

map_p2_table:
	mov %eax, p2(,%ecx,8)
    add $0x200000, %eax
    add $1, %ecx
    cmp $512, %ecx
    jb map_p2_table

enable_paging:
# Write back cache and add a memory fence
    wbinvd
    mfence

# load P4 to cr3 register (cpu uses this to access the P4 table)
    mov $p4, %eax
    mov %eax, %cr3

# enable PAE-flag in cr4 (Physical Address Extension)
    mov %cr4, %eax
    or $CR4_ENABLE_PAE, %eax
    mov %eax, %cr4

# set the long mode bit in the EFER MSR (model specific register)
    mov $LONG_MODE_ENABLE, %ecx
    rdmsr
    or $(1 << 8), %eax
    wrmsr

# enable paging in the cr0 register
    mov %cr0, %eax
    or $CR0_ENABLE_PAGING, %eax
    mov %eax, %cr0

load_64bit_gdt:
# Load GDT Pointer
    lgdt (gdt_64_pointer)

jump_to_long_mode:
# Finally, long jump to 64 bit code!!
	ljmpl $0x8,$start64

# Not supposed to reach this point
0:
	cli
	hlt
    jmp 0b

check_cpuid:
# Check if CPUID is supported by attempting to flip the ID bit (bit 21)
# in the FLAGS register. If we can flip it, CPUID is available.

# Copy FLAGS in to EAX via stack
    pushfl
    pop %eax

# Copy to ECX as well for comparing later on
    mov %eax, %ecx

# Flip the ID bit
    xor $(1 << 21), %eax

# Copy EAX to FLAGS via the stack
    push %eax
    popfl

# Copy FLAGS back to EAX (with the flipped bit if CPUID is supported)
    pushfl
    pop %eax

# Restore FLAGS from the old version stored in ECX (i.e. flipping the
# ID bit back if it was ever flipped).
    push %ecx
    popfl

# Compare EAX and ECX. If they are equal then that means the bit
# wasn't flipped, and CPUID isn't supported.
    cmp %ecx, %eax
    je no_cpuid
    ret
no_cpuid:
    push no_cpuid_str
    call vga_println
no_cpuid_spin:
    hlt
    jmp no_cpuid_spin

check_long_mode:
# test if extended processor info in available
    mov $0x80000000, %eax    # implicit argument for cpuid
    cpuid                  # get highest supported argument
    cmp $0x80000001, %eax    # it needs to be at least 0x80000001
    jb no_long_mode        # if it's less, the CPU is too old for long mode

# use extended info to test if long mode is available
    mov $0x80000001, %eax    # argument for extended processor info
    cpuid                  # returns various feature bits in ecx and edx
    testl $(1 << 29), %edx    # test if the LM-bit is set in the D-register
    jz no_long_mode        # If it's not set, there is no long mode
    ret
no_long_mode:
    push no_long_mode_str
    call vga_println
no_long_mode_spin:
    hlt
    jmp no_long_mode_spin

# print a string
vga_println:
# Save registers
	push %ebp
	mov %esp, %ebp
	push %eax
	push %ebx
	push %ecx
# VGA address
	mov $0xb8000, %ecx
# String address
	mov 8(%ebp),%ebx
# Color
	mov $0xb, ah
loop:
# Copy character
	mov (%ebx), %al 
# if 0, end
	test %al, %al
	jz ret_print
# put character in memory
	mov %ax, (%ecx)
# Increment character ptr
	add $1, %ebx
# Increment vga ptr
	add $2, %ecx
# Another iteration
	jmp loop 
ret_print:
# Restore registers
	pop %ecx
	pop %ebx
	pop %eax
	pop %ebp
	ret

#######################################
# Text 64 bits
#######################################

# 64 bit code that jumps to rust!
.section .text
.code64
.extern pre_init
start64:
    mov $0, %ax
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %fs
    mov %ax, %gs
    mov %ax, %ss

    xor %rbx, %rbx
    xor %rax, %rax

    mov multiboot, %ebx # Multiboot struct
    mov magic,     %eax # Multiboot magic number

# Reinit the stack
    mov $load_stack_start, %esp
    mov $0, %ebp
    push $0

    mov %rbx, %rdi       # 1st param in 64 bit code 
    mov %rax, %rsi       # 2nd param in 64 bit code
    call pre_init      # Call the function written in rust

# Not supposed to reach this point
0:
    cli
    hlt
    jmp 0b

#######################################
# Data
#######################################

.section .data
# Temporal space for storing multiboot structure pointer
multiboot:
    .space 8
# Temporal space for storing magic number
magic:
    .space 8

# Initial IDT
.align 4
zero_idt:
    .word 0
    .byte 0

# Initial GDT
gdt_64:
    .quad 0x0000000000000000          # Null Descriptor - should be present.
    .quad 0x00209A0000000000          # 64-bit code descriptor (exec/read).
    .quad 0x0000920000000000          # 64-bit data descriptor (read/write).

.align 4
    .word 0                 # Padding to make the "address of the GDT" field aligned on a 4-byte boundary

gdt_64_pointer:
    .word gdt_64_pointer - gdt_64 - 1    # 16-bit Size (Limit) of GDT.
    .long gdt_64                            # 32-bit Base Address of GDT. (CPU will zero extend to 64-bit)

vga_position:
    .long 0xb8000

#######################################
# Read only data
#######################################

.section .rodata
# Error messages
no_cpuid_str: .asciz "Error: CPU does not support CPUID"
no_long_mode_str: .asciz "Error: CPU does not support long mode"

#######################################
# BSS
#######################################

# Space for page directories
.section .bss
.align 0x1000
page_table_start:
p4:
	.space 0x1000
p3:
	.space 0x1000
p2:
	.space 0x1000
p1:
	.space 0x1000
page_table_end:

# Space for load stack
.section .bss
.align 8
load_stack:
	.space 0x1000
load_stack_start:

