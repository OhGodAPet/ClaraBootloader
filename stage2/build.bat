fasm boot.asm boot.sys
copy /y boot.sys A:
ndisasm -b16 boot.sys > asm.txt
pause
