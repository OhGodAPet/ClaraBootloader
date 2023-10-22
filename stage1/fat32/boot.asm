;************************************************************************
;*	Clara First Stage FAT32 Bootloader - by Wolf						*
;*																		*
;*	Notes:																*
;*		* First MB of memory in Real Mode looks as follows:				*
;* 			* 0x00000000 - 0x000003FF - Real Mode IVT		(1KB)		*
;* 			* 0x00000400 - 0x000004FF - BIOS Data Area		(.25KB)		*
;* 			* 0x00000500 - 0x00007BFF - Free				(29KB)		*
;* 			* 0x00007C00 - 0x00007DFF - This Bootloader		(.5KB)		*
;* 			* 0x00007E00 - 0x0009FFFF - Free				(32KB)		*
;* 			* 0x000A0000 - 0x000BFFFF - Video RAM			(128KB)		*
;* 			* 0x000B0000 - 0x000B7777 - Monochrome RAM		(32KB)		*
;* 			* 0x000B8000 - 0x000BFFFF - Color RAM			(32KB)		*
;* 			* 0x000C0000 - 0x000C7FFF - Video ROM BIOS		(32KB)		*
;* 			* 0x000C8000 - 0x000EFFFF - BIOS Shadow Area	(160KB)		*
;* 			* 0x000F0000 - 0x000FFFFF - System BIOS			(64KB)		*
;*	Design:																*
;*		Steps:															*
;*			* If int 0x12 returns less than 639KB or errors, die		*
;*			* Use initialization routine to load root dir table and FAT	*
;*			* Use file locating routine to find Stage 2					*
;*			* Use file loading routine to load Stage 2					*
;*			* Validate signature, die if invalid						*
;*			* Push file locating and finding routines (in that order)	*
;*			* Far jump to Stage 2										*
;*		Conventions:													*
;*			* Comments may be no longer than half a 1366x768 display	*
;*			* Comment blocks begin with ;* and end at a tab with a *	*
;*			* In constants, sizes are in 512 byte units					*
;*			* Register names capitalized in comments					*
;*		Limits:															*
;*			* Can only read 0xFFFF bytes without segment reg adjustment	*
;*			* Root Dir and FAT tables must fit in 13.5KB each			*
;*			* Stage 2 image must be smaller than 92KB					*
;*			* Sector size must be 512 bytes								*
;*			* Cannot read more than 0xFF sectors at one time			*
;*		Memory Layout:													*
;*			* 0x00000C00 - 0x000009FF - Bootloader stack		(1KB)	*
;*			* 0x00001000 - 0x000045FF - Root Directory Table	(13.5KB)*
;*			* 0x00004600 - 0x00007BFF - File Allocation Table 	(13.5KB)*
;*			* 0x00007C00 - 0x00007DFF - Stage 1 image			(.5KB)	*
;*			* 0x00007E00 - 0x0001F0FF - Stage 2 image			(92KB)	*
;*		Note:															*
;*			* Bytes per sector and memory check won't fit, currently	*
;************************************************************************

;************************************************
;*  Assembler directives & constants			*
;************************************************ 

format binary
org 0x7C00
use16

; Bootloader wide constants
LOADER_STACK_TOP		equ 0x09FF		; Top of bootloader stack

; Stage 1 local constants
STAGE2_ADDR_HIGH		equ 0x07E0		; Stage 2 segment
STAGE2_ADDR_LOW			equ 0x0000		; Stage 2 offset
STAGE2_BUFFER_SIZE		equ 0x00B9		; Stage 2 buffer size in sectors
STAGE2_ABSOLUTE_ADDR	equ 0x7E00		; Stage 2 absolute address

; Filesystem constants
ROOT_DIR_BASE_ADDR		equ 0x1000		; Base of root dir
FAT_BASE_ADDR			equ 0x4600		; Base of FAT
ROOT_DIR_BUFFER_SIZE	equ 0x001B		; Root dir buffer size sectors
FAT_BUFFER_SIZE			equ 0x001B		; FAT buffer size in sectors

;************************************************
;*  Start of execution (long jump for 3 bytes)	*
;************************************************ 

start: 
	jmp main							; Buggy BIOS protection, too

;************************************************
;* 	FAT32 BPB (BIOS Parameter Block				*
;************************************************ 

bpbOEMName				rb 8
bpbBytesPerSector		dw ?
bpbSectorsPerCluster	db ?
bpbReservedSectors		dw ?
bpbFATCount				db ?
bpbRDirectoryEntries	dw ?
bpbTotalSectors 		dw ?
bpbMedia				db ?
bpbUnused				dw ?
bpbSectorsPerTrack		dw ?
bpbHeadsPerCylinder		dw ?
bpbHiddenSectors		dd ?
bpbLargeSectorCount		dd ?

bpbSectorsPerFAT		dd ?
bpbFlags				dw ?
bpbVersion				dw ?
bpbRootCluster			dd ?
bpbFSInfoCluster		dw ?
bpbBSBackupCluster		dw ?
bpbReserved0			rb 12
bpbDriverNumber 		db ?
bpbReserved1			db ?
bpbSignature			db ?
bpbVolumeSerial 		dd ?
bpbVolumeLabel			rb 11
bpbFilesystemName		rb 8

;************************************************
;* 	Other Uninitialized variables				*
;************************************************

SECTOR_DATA	dw	0
cluster 	dw	0
bootdrv 	db	0

;************************************************
;*  Initialized Variables						*
;************************************************ 

Stage2Name 		db "BOOT    SYS"
MsgGenErr 		db "Fatal error.", 0

;************************************************
;* 	ReadDisk()									*
;* 		- Reads sectors off disk				*
;*		- Input									*
;* 			- ax		= Cluster to red		*
;*			- ebx		= Buffer				*
;*			- bootdrv	= Drive number			*
;*		- Output								*
;* 			- es:bx 	= Disk contents			*
;* 		- All registers preserved				*
;************************************************ 

ReadDisk:
	pusha				; Preserve registers
	
	; Get size of cluster
	movzx		cx, byte [bpbSectorsPerCluster]
	
	; Update packet
	mov		word [diskAddressPacket + DiskAddressPacket.blockCount], cx
	mov		dword [diskAddressPacket + DiskAddressPacket.buffer], ebx
	mov		dword [diskAddressPacket + DiskAddressPacket.startBlock], eax

	; Call packet
	mov		ah, 0x42
	mov		dl, byte [bootdrv]
	xor		bx, bx
	mov		ds, bx
	mov		si, diskAddressPacket
	
	int		0x13
	
	popa
	
	; Update buffer location
	push	ax
	push	cx
	
	mov		ax, word [bpbBytesPerSector]
	movzx	cx, byte [bpbSectorsPerCluster]
	mul		cx
	add		bx, ax
	
	pop		bx
	pop		ax
	
	ret
		
;       ClusterToSector
;       Arguments:
;               AX->            Cluster
;       Returns:
;               AX->            Sector
ClusterToSector:
	sub		ax, 2							; ((n - 2)
	mul		byte [bpbSectorsPerCluster]		; * bpb->sectorsPerCluster)
	add		ax, word [SECTOR_DATA]			; + SECTOR_DATA
	
	ret
		
;************************************************
;* 	Fat32Init()									*
;* 		- Loads the root dir table and FAT		*
;*		- Input 								*
;*			- bootdrv = Boot drive				*
;*		- Output								*
;*			- clusoff = Cluster offset			*
;*			- root dir and FAT at addresses		*
;*		- Requirements							*
;* 			- ROOT_DIR_BASE_ADDR constant		*
;*			- FAT_BASE_ADDR	constant			*
;* 		- AX, BX, CX, and DX clobbered			*
;************************************************ 

Fat32Init:
	; Find SECTOR_DATA
	movzx	ax, byte [bpbFATCount]
	mul		word [bpbSectorsPerFAT]
	add		ax, word [bpbReservedSectors]
	mov		word [SECTOR_DATA], ax
	
	; Get FAT sector
	xor		eax, eax
	mov		ax, word [cluster]		; (((n)
	shl		ax, 2
	div		word [bpbBytesPerSector]	; / bpb->bytesPerSector)
	add		ax, word [bpbReservedSectors]	; + bpb->reservedSectors
	
	; Load the FAT
	mov		ebx, FAT_BASE_ADDR
	call	ReadDisk
	
	; Get root sector
	mov		eax, dword [bpbRootCluster]
	call	ClusterToSector
	
	; Load the first sector of the root directory
	mov		ebx, ROOT_DIR_BASE_ADDR
	call	ReadDisk
	
	ret									; Return

;************************************************
;* 	Fat12Find()									*
;* 		- Loads a file into memory				*
;*		- Input 								*
;*			- DS:SI = Pointer to file name		*
;*		- Output								*
;*			- curclus = First cluster			*
;*			- CF set on error					*
;*		- Requirements							*
;*			- ROOT_DIR_BASE_ADDR constant		*
;* 		- All registers preserved				*
;************************************************ 

Fat32Find:
	pusha
	
	mov		cx, 16			; 16 entries per sector
	mov		di, ROOT_DIR_BASE_ADDR
	mov		dx, si
	
	.Loop:
		push	cx
		mov		cx, 11
		mov		si, dx
		
		; Compare names
		push	di
		rep	cmpsb
		pop		di
		pop		cx
		
		; Found it!
		je		.Found
		
		; Didn't find it, keep moving
		add		di, 32
		
		loop	.Loop
		
		popa
		
		stc
		ret
	
	.Found:
		xor		dx, dx
		mov		dx, word [di + 0x1A]
		mov		word [cluster], dx
		
		popa
		ret
		
;************************************************
;* 	Fat12Load()									*
;* 		- Loads a file into memory				*
;*		- Input 								*
;* 			- FS:DI 	= Buffer 				*
;*			- BP 		= Sectors to read		*
;*			- curclus 	= Cluster				*
;*		- Output								*
;*			- File data at ES:DI				*
;*			- CF set on error					*
;*		- Requirements							*
;*			- FAT_BASE_ADDR constant			*
;* 		- BP clobbered							*
;************************************************ 
Fat32Load:
	push	bx
	
	.Main:
		mov		ax, word [cluster]
		pop		bx
		
		; Load sector
		call	ClusterToSector
		call	ReadDisk
		
		push	bx
		
		; Find FAT entry
		mov		bx, word [cluster]
		imul	bx, 4
		
		; Save it
		push	es
		
		mov		dx, FAT_BASE_ADDR
		mov		es, dx
		
		mov		dx, word [es:bx]
		
		pop		es
		
		; Check if we're at EOF
		mov		word [cluster], dx
		cmp		dx, 0xFFF8
		jb		.Main
		
	pop		bx	
	ret
		
PrintLine:
	lodsb
	cmp al, 0
	je .done
	mov ah, 0x0E
	int 0x10
	jmp PrintLine
	.done:
		ret

;************************************************
;*	Bootloader Entry Point						*
;************************************************

main:
	; Set up segments and the stack (we're not using FS or GS)
	cli
	xor ax, ax
	mov ds, ax
	mov es, ax
	mov ss, ax
	mov sp, LOADER_STACK_TOP
	sti
	
	mov [bootdrv], dl			; Set bootdrv

	; Initialize FAT32 real mode driver
	call Fat32Init				; Initialize real mode FAT32 driver
	
	; Find stage 2
	mov si, Stage2Name			; We want to find Stage 2
	call Fat32Find				; Find the file
	jc FatalError
	
	; Load stage 2 into memory
	push STAGE2_ADDR_HIGH					
	pop fs
	mov di, STAGE2_ADDR_LOW		; Move offset into DI
	mov bp, STAGE2_BUFFER_SIZE	; Read until EOF, or out of reserved mem
	call Fat32Load				; Load Stage 2
	jc FatalError				; If error, die
	cmp bp, 0xFFFF				; Check for EOF
	jne FatalError				; If we didn't read all of it, die

	; Check signature
	cmp word [fs:STAGE2_ADDR_LOW], 'YI'
	jne FatalError
	cmp word [fs:STAGE2_ADDR_LOW + 2], 'FF'
	jne FatalError
	
	; We edited ES, fix it
	push ds						; DS is 0, push it
	pop fs						; Pop it into ES
	
	; Pass arguments
	push word Fat32Load
	push word Fat32Find
	push word [bpbBytesPerSector]
	push word [bootdrv]
	
	; Jump to stage 2 (past sig)
	jmp 0x0000:STAGE2_ABSOLUTE_ADDR + 4

FatalError:
	mov si, MsgGenErr					; Put message in SI
	call PrintLine						; Print it
	cli									; Clear interrupts
	hlt									; Halt

;************************************************
;*	Structures									*
;************************************************

struct DiskAddressPacket
	size		db	?
	reserved	db	?
	blockCount	dw	?
	buffer		dd	?
	startBlock	dq	?
ends

;************************************************
;*	Disk Address Packet							*
;************************************************

diskAddressPacket:
	db 16					; Size
	rb 15					; Rest of packet

;************************************************
;* 	Padding										*
;************************************************

times 510-($-$$) db 0
dw 0xAA55
