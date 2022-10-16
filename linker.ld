ENTRY(_start)
OUTPUT_FORMAT(elf64-x86-64)

SECTIONS {
    /* The start address */
    . = 0x40000;

    .text : 
	{
        *(.text*)
    }

    .rodata : 
	{
        *(.rodata*)
    }

    .data : 
	{
        *(.data*)
        *(.bss*)
    }
}

