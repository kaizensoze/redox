RUSTC=rustc
RUSTCFLAGS=--target=i686-unknown-redox-gnu.json \
	-C no-vectorize-loops -C no-vectorize-slp -C no-stack-check -C opt-level=2 \
	-Z no-landing-pads \
	-A dead-code -A deprecated \
	-L build
AS=nasm
AWK=awk
BASENAME=basename
CUT=cut
FIND=find
LD=ld
LDARGS=-m elf_i386
MKDIR=mkdir
OBJDUMP=objdump
RM=rm
SED=sed
SORT=sort
VB=virtualbox
VBM=VBoxManage
VB_AUDIO="pulse"

ifeq ($(OS),Windows_NT)
	SHELL=windows\sh
	LD=windows/i386-elf-ld
	AS=windows/nasm
	AWK=windows/awk
	BASENAME=windows/basename
	CUT=windows/cut
	FIND=windows/find
	MKDIR=windows/mkdir
	OBJDUMP=windows/objdump
	RM=windows/rm
	SED=windows/sed
	SORT=windows/sort
	VB="C:/Program Files/Oracle/VirtualBox/VirtualBox"
	VBM="C:/Program Files/Oracle/VirtualBox/VBoxManage"
	VB_AUDIO="dsound"
else
	UNAME := $(shell uname)
	ifeq ($(UNAME),Darwin)
		LD=i386-elf-ld
		OBJDUMP=i386-elf-objdump
                RUSTCFLAGS += -C ar=i386-elf-ar -C linker=i386-elf-linker
		VB="/Applications/VirtualBox.app/Contents/MacOS/VirtualBox"
		VBM="/Applications/VirtualBox.app/Contents/MacOS/VBoxManage"
		VB_AUDIO="coreaudio"
	endif
endif

help:
	@echo ".########..########.########...#######..##.....##"
	@echo ".##.....##.##.......##.....##.##.....##..##...##."
	@echo ".##.....##.##.......##.....##.##.....##...##.##.."
	@echo ".########..######...##.....##.##.....##....###..."
	@echo ".##...##...##.......##.....##.##.....##...##.##.."
	@echo ".##....##..##.......##.....##.##.....##..##...##."
	@echo ".##.....##.########.########...#######..##.....##"
	@echo
	@echo "-------- Redox: A Rust Operating System ---------"
	@echo
	@echo "Commands:"
	@echo
	@echo "    make all"
	@echo "        Build raw image of filesystem used by Redox."
	@echo "        It create build/harddrive.bin which can be used to build"
	@echo "        images for Your virtual machine."
	@echo
	@echo "    make virtualbox"
	@echo "        Build Redox and run it inside VirtualBox machine."
	@echo
	@echo "    make qemu"
	@echo "        Build Redox and run it inside KVM machine."
	@echo
	@echo "    make qemu_no_kvm"
	@echo "        Build Redox and run it inside Qemu machine without KVM support."
	@echo
	@echo "    make apps"
	@echo "        Build apps for Redox."
	@echo
	@echo "    make tests"
	@echo "        Run tests on Redox."
	@echo
	@echo "    make clean"
	@echo "        Clean build directory."
	@echo

all: build/harddrive.bin

docs: src/kernel.rs build/libcore.rlib build/liballoc.rlib
	rustdoc --target=i686-unknown-redox-gnu.json -L. $<

apps: apps/echo apps/editor apps/file_manager apps/httpd apps/game apps/ox apps/player apps/terminal apps/viewer apps/zfs apps/bad_code apps/bad_data apps/bad_segment apps/linux_stdio

tests: tests/success tests/failure

clean:
	$(RM) -rf build filesystem/apps/*/*.bin filesystem/apps/*/*.list

apps/%:
	@make --no-print-directory filesystem/apps/$*/$*.bin

FORCE:

tests/%: FORCE
	@$(SHELL) $@ && echo "$*: PASSED" || echo "$*: FAILED"

build/libcore.rlib: rust/libcore/lib.rs
	$(MKDIR) -p build
	$(RUSTC) $(RUSTCFLAGS) -o $@ $<

build/liballoc.rlib: rust/liballoc/lib.rs build/libcore.rlib
	$(RUSTC) $(RUSTCFLAGS) -o $@ $<

build/liballoc_system.rlib: rust/liballoc_system/lib.rs build/libcore.rlib
	$(RUSTC) $(RUSTCFLAGS) -o $@ $<

build/librustc_unicode.rlib: rust/librustc_unicode/lib.rs build/libcore.rlib
	$(RUSTC) $(RUSTCFLAGS) -o $@ $<

build/libcollections.rlib: rust/libcollections/lib.rs build/libcore.rlib build/liballoc.rlib build/liballoc_system.rlib librustc_unicode.rlib
	$(RUSTC) $(RUSTCFLAGS) -o $@ $<

build/libredox.rlib: libredox/lib.rs build/libcore.rlib build/liballoc.rlib build/liballoc_system.rlib
	$(RUSTC) $(RUSTCFLAGS) -o $@ $<

build/kernel.rlib: src/kernel.rs build/libcore.rlib build/liballoc.rlib build/liballoc_system.rlib
	$(RUSTC) $(RUSTCFLAGS) -C lto -o $@ $<

filesystem/kernel.bin: build/kernel.rlib src/kernel.ld
	$(LD) $(LDARGS) -o $@ -T src/kernel.ld $<

filesystem/kernel.list: filesystem/kernel.bin
	$(OBJDUMP) -C -M intel -d $< > $@

filesystem/%.bin: filesystem/%.asm src/program.ld
	$(MKDIR) -p build
	$(AS) -f elf -o build/`$(BASENAME) $*.o` $<
	$(LD) $(LDARGS) -o $@ -T src/program.ld build/`$(BASENAME) $*`.o

filesystem/%.bin: filesystem/%.rs src/program.rs src/program.ld build/libcore.rlib build/liballoc.rlib build/liballoc_system.rlib build/libredox.rlib
	$(SED) "s|APPLICATION_PATH|../$<|" src/program.rs > build/`$(BASENAME) $*`.gen
	$(RUSTC) $(RUSTCFLAGS) -C lto -o build/`$(BASENAME) $*`.rlib build/`$(BASENAME) $*`.gen
	$(LD) $(LDARGS) -o $@ -T src/program.ld build/`$(BASENAME) $*`.rlib

filesystem/%.list: filesystem/%.bin
	$(OBJDUMP -C -M intel -d $< > $@

filesystem/apps/zfs/zfs.img:
	dd if=/dev/zero of=$@ bs=256MB count=1
	sudo losetup /dev/loop0 $@
	-sudo zpool create redox_zfs /dev/loop0
	-sudo zfs create redox_zfs/root
	-sudo cp README.md /redox_zfs/root/
	-sudo sync
	-sudo zfs unmount redox_zfs/root
	-sudo zpool destroy redox_zfs
	sudo losetup -d /dev/loop0

build/filesystem.gen: apps
	$(FIND) filesystem -not -path '*/\.*' -type f -o -type l | $(CUT) -d '/' -f2- | $(SORT) | $(AWK) '{printf("file %d,\"%s\"\n", NR, $$0)}' > $@

build/harddrive.bin: src/loader.asm filesystem/kernel.bin build/filesystem.gen
	$(AS) -f bin -o $@ -ibuild/ -isrc/ -ifilesystem/ $<

virtualbox: build/harddrive.bin
	echo "Delete VM"
	-$(VBM) unregistervm Redox --delete; \
	if [ $$? -ne 0 ]; \
	then \
		if [ -d "$$HOME/VirtualBox VMs/Redox" ]; \
		then \
			echo "redox directory exists, deleting..."; \
			$(RM) -rf "$$HOME/VirtualBox VMs/Redox"; \
		fi \
	fi
	echo "Delete Disk"
	-$(RM) harddrive.vdi
	echo "Create VM"
	$(VBM) createvm --name Redox --register
	echo "Set Configuration"
	$(VBM) modifyvm Redox --memory 512
	$(VBM) modifyvm Redox --vram 64
	$(VBM) modifyvm Redox --nic1 nat
	$(VBM) modifyvm Redox --nictype1 82540EM
	$(VBM) modifyvm Redox --nictrace1 on
	$(VBM) modifyvm Redox --nictracefile1 build/network.pcap
	$(VBM) modifyvm Redox --uart1 0x3F8 4
	$(VBM) modifyvm Redox --uartmode1 file build/serial.log
	$(VBM) modifyvm Redox --usb on
	$(VBM) modifyvm Redox --audio $(VB_AUDIO)
	$(VBM) modifyvm Redox --audiocontroller ac97
	echo "Create Disk"
	$(VBM) convertfromraw $< build/harddrive.vdi
	echo "Attach Disk"
	$(VBM) storagectl Redox --name IDE --add ide --controller PIIX4 --bootable on
	$(VBM) storageattach Redox --storagectl IDE --port 0 --device 0 --type hdd --medium build/harddrive.vdi
	echo "Run VM"
	$(VB) --startvm Redox --dbg

qemu: build/harddrive.bin
	-qemu-system-i386 -net nic,model=rtl8139 -net user -net dump,file=build/network.pcap \
			-usb -device usb-tablet \
			-device usb-ehci,id=ehci -device nec-usb-xhci,id=xhci \
			-soundhw ac97 \
			-serial mon:stdio -d guest_errors -enable-kvm -hda $<

qemu_no_kvm: build/harddrive.bin
	-qemu-system-i386 -net nic,model=rtl8139 -net user -net dump,file=build/network.pcap \
			-usb -device usb-tablet \
			-device usb-ehci,id=ehci -device nec-usb-xhci,id=xhci \
			-soundhw ac97 \
			-serial mon:stdio -d guest_errors -hda $<

qemu_tap: build/harddrive.bin
	sudo tunctl -t tap_redox -u "${USER}"
	sudo ifconfig tap_redox 10.85.85.1 up
	-qemu-system-i386 -net nic,model=rtl8139 -net tap,ifname=tap_redox,script=no,downscript=no -net dump,file=build/network.pcap \
			-usb -device usb-tablet \
			-device usb-ehci,id=ehci -device nec-usb-xhci,id=xhci \
			-soundhw ac97 \
			-serial mon:stdio -d guest_errors -enable-kvm -hda $<
	sudo ifconfig tap_redox down
	sudo tunctl -d tap_redox

qemu_tap_8254x: build/harddrive.bin
	sudo tunctl -t tap_redox -u "${USER}"
	sudo ifconfig tap_redox 10.85.85.1 up
	-qemu-system-i386 -net nic,model=e1000 -net tap,ifname=tap_redox,script=no,downscript=no -net dump,file=build/network.pcap \
			-usb -device usb-tablet \
			-device usb-ehci,id=ehci -device nec-usb-xhci,id=xhci \
			-soundhw ac97 \
			-serial mon:stdio -d guest_errors -enable-kvm -hda $<
	sudo ifconfig tap_redox down
	sudo tunctl -d tap_redox

virtualbox_tap: build/harddrive.bin
	echo "Delete VM"
	-$(VBM) unregistervm Redox --delete
	echo "Delete Disk"
	-$(RM) harddrive.vdi
	echo "Create VM"
	$(VBM) createvm --name Redox --register
	echo "Create Bridge"
	sudo tunctl -t tap_redox -u "${USER}"
	sudo ifconfig tap_redox 10.85.85.1 up
	echo "Set Configuration"
	$(VBM) modifyvm Redox --memory 512
	$(VBM) modifyvm Redox --vram 64
	$(VBM) modifyvm Redox --nic1 bridged
	$(VBM) modifyvm Redox --nictype1 82540EM
	$(VBM) modifyvm Redox --nictrace1 on
	$(VBM) modifyvm Redox --nictracefile1 network.pcap
	$(VBM) modifyvm Redox --bridgeadapter1 tap_redox
	$(VBM) modifyvm Redox --uart1 0x3F8 4
	$(VBM) modifyvm Redox --uartmode1 file build/serial.log
	$(VBM) modifyvm Redox --usb on
	$(VBM) modifyvm Redox --audio $(VB_AUDIO)
	$(VBM) modifyvm Redox --audiocontroller ac97
	echo "Create Disk"
	$(VBM) convertfromraw $< build/harddrive.vdi
	echo "Attach Disk"
	$(VBM) storagectl Redox --name IDE --add ide --controller PIIX4 --bootable on
	$(VBM) storageattach Redox --storagectl IDE --port 0 --device 0 --type hdd --medium build/harddrive.vdi
	echo "Run VM"
	-$(VB) --startvm Redox --dbg
	echo "Delete Bridge"
	sudo ifconfig tap_redox down
	sudo tunctl -d tap_redox

arping:
	arping -I tap_redox 10.85.85.2

ping:
	ping 10.85.85.2

wireshark:
	wireshark network.pcap
