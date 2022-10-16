
# 
obj/minix3.a: Cargo.toml $(shell find src -type f -name "*.rs")
	mkdir -p $(@D)
	env RUSTFLAGS="-C soft-float" \
	cargo rustc \
	-Z build-std=core,alloc \
	-Z build-std-features=compiler-builtins-mem \
	--target x86_64-blog_os.json \
	--lib \
	--release \
	-- \
	--emit link=$@

obj/head.o: src/arch/x86_64/head.s
	mkdir -p $(@D)
	as --64 -msyntax=att -mnaked-reg -o $@ $<

obj/minix3.elf: linker.ld obj/minix3.a obj/head.o
	mkdir -p $(@D)
	ld -m elf_x86_64 --gc-sections -T $< -o $@ obj/head.o obj/minix3.a 

minix3.iso: obj/minix3.elf
	mkdir iso
	mkdir iso/boot
	mkdir iso/boot/grub
	cp $< iso/boot/
	echo 'set timeout=0'                  > iso/boot/grub/grub.cfg
	echo 'set default=0'                 >> iso/boot/grub/grub.cfg
	echo ''                              >> iso/boot/grub/grub.cfg
	echo 'menuentry "Minix3" {'          >> iso/boot/grub/grub.cfg
	echo ' multiboot /boot/minix3.elf'   >> iso/boot/grub/grub.cfg
	echo ' boot'                         >> iso/boot/grub/grub.cfg
	echo '}'                             >> iso/boot/grub/grub.cfg
	grub2-mkrescue --output=$@ iso
	rm -R iso

#run: blog_os.iso
#    (killall VirtualBoxVM && sleep 1) || true
#    VirtualBoxVM --startvm "blog_os" 2> log.txt &

runq: minix3.iso
	(killall qemu-system-x86_64 && sleep 1) || true
	qemu-system-x86_64 -drive format=raw,file=$< &

.PHONY: clean
clean:
	rm -rf obj minix3pp.iso

