All other asm files are included by boot.asm

Untested things:
	- Loading a file from its Clara structure values
	- Bit 1, 16, or 17 being set, or bit 2 being clear
	- Bit 2 set without a valid HeaderAddress value
	- Zero or random HeaderAddress value
	- Any TargetMachine value except 0x0000
	- In FixPointer, the case of the real and header offsets being inequal
	- Loading from the file headers without a Clara structure
	- A lot of error handling code, especially for the BIOS