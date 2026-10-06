Set WshShell = CreateObject("WScript.Shell")
qemu = """C:\Program Files\qemu\qemu-system-x86_64.exe""" & _
  " -bios D:\OHOS-QEMU\KaihongOS\OVMF.fd" & _
  " -boot order=c" & _
  " -drive id=system,file=D:\OHOS-QEMU\KaihongOS\qemu.img,if=none,format=raw,cache=none" & _
  " -device virtio-blk-pci,drive=system,bootindex=0" & _
  " -smp 2 -m 16G -accel whpx" & _
  " -chardev socket,id=serial0,host=127.0.0.1,port=22473,server=on,wait=off,logfile=D:\OHOS-QEMU\KaihongOS\p5-serial.log" & _
  " -serial chardev:serial0" & _
  " -display egl-headless -display vnc=127.0.0.1:5" & _
  " -monitor telnet:127.0.0.1:22471,server,nowait" & _
  " -qmp telnet:127.0.0.1:22472,server,nowait" & _
  " -vga none -device virtio-vga-gl,xres=1280,yres=720" & _
  " -device virtio-tablet-pci" & _
  " -netdev user,id=net0,hostfwd=tcp:127.0.0.1:15565-:5555" & _
  " -device virtio-net-pci,netdev=net0,bootindex=1"
WshShell.Run qemu, 0, False
WScript.Echo "launched"
