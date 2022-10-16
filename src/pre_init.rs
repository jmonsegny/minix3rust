#![no_std]
#![no_main]
mod vga_buffer;

use core::panic::PanicInfo;

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    loop{}
}

static HELLO: &[u8] = b"minix3rust - pre_init function";
static HEX: &[u8] = b"0123456789ABCDEF";

#[no_mangle]
pub extern "C" fn pre_init(mb: i64, magic: i64 ) {
    let vga_buffer = 0xb8000 as *mut u8;

    for( i, &byte ) in HELLO.iter().enumerate() {
        unsafe {
            *vga_buffer.offset(i as isize*2) = byte;
            *vga_buffer.offset(i as isize*2 + 1) = 0x1b;
        }
    }

/*    let idx : usize = (magic & 0xF) as usize;

    unsafe {
        *vga_buffer.offset(0) = HEX[idx];
    }*/

    let mut idx : usize = 0;    
    
    for i in 0..15 {
        unsafe {
            idx = ((mb >> i*4) & 0xF) as usize;
            *vga_buffer.offset((14-i) as isize*2 + 160) = HEX[idx];
        }
    }

    idx = 0;

    for i in 0..15 {
        unsafe {
            idx = ((magic >> i*4) & 0xF) as usize;
            *vga_buffer.offset((14-i) as isize*2 + 320) = HEX[idx];
        }
    }

    vga_buffer::print_something();

    loop{}

}

