;************************************************************************
;*	Clara First Stage FAT12 Bootloader - by Wolf						*
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
;* 	FAT12 BPB (BIOS Parameter Block				*
;************************************************ 

bpbOEM					rb 8
bpbBytesPerSector  		rw 1
bpbSectorsPerCluster 	rb 1
bpbReservedSectors 		rw 1
bpbNumberOfFATs 		rb 1
bpbRootEntries 			rw 1
bpbTotalSectors 		rw 1
bpbMedia				rb 1
bpbSectorsPerFAT 		rw 1
bpbSectorsPerTrack 		rw 1
bpbHeadsPerCylinder 	rw 1
bpbHiddenSectors		rd 1
bpbTotalSectorsBig  	rd 1
bsDriveNumber      		rb 1
bsUnused				rb 1
bsExtBootSignature		rb 1
bsSerialNumber      	rd 1
bsVolumeLabel 	        rb 11
bsFileSystem 	        rb 8

;************************************************
;* 	Other Uninitialized variables				*
;************************************************

clusoff rw 1
curclus rw 1
bootdrv rb 1

;************************************************
;*  Initialized Variables						*
;************************************************ 

Stage2Name 		db "BOOT    SYS"
MsgGenErr 		db "Fatal error.", 0

;************************************************
;* 	ReadDisk()									*
;* 		- Reads sectors off disk				*
;*		- Input									*
;* 			- al 		= Number of sectors		*
;* 			- ch 		= Cylinder				*
;* 			- cl 		= Sector				*
;* 			- dh 		= Head					*
;*			- es:bx		= Buffer to read to		*
;*			- bootdrv	= Drive number			*
;*		- Output								*
;* 			- es:bx 	= Disk contents			*
;* 		- All registers preserved				*
;************************************************ 

ReadDisk:
	pusha				; Preserve registers
	
	mov dl, [bootdrv]	; Set the boot drive for the BIOS
	mov di, 3			; Three retries for error
	
	.Read:
		mov ah, 0x02	; BIOS read sector call, al is number of sectors 
		int 0x13		; Call interrupt
		jc .Die			; If CF is set, error
		popa			; Restore registers
		ret				; Succeeded, CF is clear, return
	.Error:
		cmp di, 0		; Are we out of retries?
		jle .Die		; If so, fail
		dec di			; If not, reduce retry counter
		call .Reset		; Reset drive
		jnc .Read		; If the rest didn't error, retry
		jmp .Die		; If the reset errored, die
	.Reset:
		push ax			; Save current value
		xor ax, ax		; BIOS reset disk call (dl is already the drive)
		int 0x13		; Call interrupt
		pop ax			; Restore AX and return to .error
		ret
	.Die:
		popa			; Pop registers
		stc				; Some paths here don't set CF
		ret				; Return to caller
		
;************************************************
;* 	LBA2CHS()									*
;* 		- Converts LBA value to CHS				*
;*		- Input									*
;* 			- ax 		= LBA address			*
;*		- Output								*
;* 			- ch 		= Cylinder				*
;* 			- dh 		= Head					*
;* 			- cl 		= Sector				*
;*		- Algorithm								*
;*			* C = LBA / (SPT * HPC)				*
;*			* H = (LBA / SPT) % HPC				*
;*			* S = (LBA % SPT) + 1				*
;* 		- AX, CX and DX clobbered				*
;************************************************

LBA2CHS:
	xor dx, dx						; Sector first
	div word [bpbSectorsPerTrack]	; Divide LBA by SPT
	inc dl							; Truncate to one byte
	mov cl, dl						; Sector goes in CL
	xor dx, dx						; Prepare DX
	div word [bpbHeadsPerCylinder]	; LBA / SPT in AX
	mov dh, dl						; Heads go in DH
	mov ch, al						; Cylinder goes in CH
	ret								; Return to caller
		
;************************************************
;* 	Fat12Init()									*
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

Fat12Init:
	
	; Root directory start = size of FAT + reserved
	xor ax, ax							; Clear AX
	mov al, byte [bpbNumberOfFATs]		; Move number of FATs in
	mul word [bpbSectorsPerFAT]			; Multiply by sectors per FAT
	push ax								; Save size of FAT
	add ax, word [bpbReservedSectors]	; AX = start of root dir
	xchg ax, bx							; Save start addr
	
	; Root directory size = (Size of entry * number of entries)
	mov ax, 32							; Size of entry
	mul word [bpbRootEntries]			; Multiply by number of entries
	div word [bpbBytesPerSector]		; Divide to get sectors
	push ax
	
	; Cluster offset is the end of the root dir
	mov dx, bx							; Copy start address
	add dx, ax							; Root dir base + sizeof root dir						
	mov word [clusoff], dx				; Save cluster offset in variable
	
	; Read root directory to ROOT_DIR_BASE_ADDR
	xchg ax, bx							; AX = start addr (BX = garbage)
	call LBA2CHS						; Change LBA addr to CHS
	pop ax								; Size of root dir
	mov bx, ROOT_DIR_BASE_ADDR			; Load to ROOT_DIR_BASE_ADDR						
	cmp ax, ROOT_DIR_BUFFER_SIZE		; Make sure it's not too big
	;jg FatalError						; If it is, die
	call ReadDisk 						; Read it into memory
	jc FatalError						; If it errored, die
	
	; Start of FAT = end of reserved sectors
	mov ax, word [bpbReservedSectors]	; Number of reserved sectors
	call LBA2CHS						; Convert to CHS addr
	
	; Size of FAT = (number of FATs * sectors per FAT)
	pop ax								; AX = size of FAT
	
	; Read into FAT_BASE_ADDR
	mov bx, FAT_BASE_ADDR				; Load to FAT_BASE_ADDR
	cmp ax, FAT_BUFFER_SIZE				; Make sure it's not too big
	;jg FatalError						; Die if it is
	call ReadDisk						; Read sectors
	jc FatalError						; Die on error
	
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

Fat12Find:
	pusha								; Save registers
	
	mov di, ROOT_DIR_BASE_ADDR			; Read from root dir
	mov bx, word [bpbRootEntries]		; Set counter
	
	.FindLoop:
		mov cx, 11						; Size of file name
		push si							; Preserve file name
		push di							; Preserve address
		rep cmpsb						; Compare entry with file to load
		pop di							; Restore address	
		pop si							; Restore name
		je .Found						; Jump if it's the file we want
		add di, 32						; If not, go to next entry
		dec bx							; Loop until no more entries
		jnz .FindLoop
	.Failed:
		popa							; File missing, pop registers
		stc								; Set CF, there was an error
		ret								; Return to caller
	.Found:
		add di, 0x1A					; Found file, get cluster addr
		mov ax, word [di]				; Get actual cluster
		mov word [curclus], ax			; Save in variable
		popa							; Restore variables
		ret								; Return to caller
		
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
Fat12Load:
	pusha
	
	push es								; Save original ES
	push fs								; Put FS onto stack
	pop es								; Pop FS into ES
	
	xor si, si							; Clear counter
	
	.ReadFile:
		mov ax, [curclus]					; AX = current cluster
		;push dx
		
		; Convert to LBA address; ((cluster - 2) * sectors per cluster)
		sub ax, 2							; Cluster - 2
		xor cx, cx							; Clear upper 8 bits
		mov cl, [bpbSectorsPerCluster]		; Move in SPC
		mul cx								; Multiply by SPC
		add ax, word [clusoff]				; Add the cluster offset

		; Read cluster into memory
		call LBA2CHS						; Convert LBA addr to CHS
		mov al, [bpbSectorsPerCluster]		; Read one cluster
		mov bx, di							; Move dest. address to BX
		call ReadDisk						; Read it in
		jc .Die								; Die on error
		
		; Check if done
		;pop dx
		;cmp dx, 0xFF8						; Is this the last one?
		;jge .Loaded							; If so, signal and return
		
		; Update destination address
		
		xor ax, ax							; Clear AX
		mov al, byte [bpbSectorsPerCluster]	; Sectors per cluster times
		mov bx, word [bpbBytesPerSector]	; Bytes per sector equals
		mul bx								; Bytes per cluster
		add di, ax							; Increment dest. address

		; Update counter
		xor ax, ax
		mov al, byte [bpbSectorsPerCluster]
		add si, ax
		
		; Next cluster = (currentcl * 1.5) + 1
		; We can't multiply by 1.5, so (currentcl / 2) + currentcl + 1
		; We're reading a word, so no + 1
	
		mov bx, word [curclus]	; Current cluster
		shr bx, 1				; currentcl / 2
		add bx, word [curclus]	; + currentcl
		
		add bx, FAT_BASE_ADDR	; Add to base of FAT
		mov dx, word [bx]		; Read two bytes
		mov ax, [curclus]		; Move current cluster into AX
		and ax, 1				; Check if it's even or odd
		jz .Even				; If even (bit 0 is 0), jump to .Even
		
		.Odd:
			shr dx, 4			; If odd, shift right four
			jmp .ClusterDone	; Done with cluster
		.Even:
			and dx, 0xFFF		; If even, and with 0xFFF, fall through
			
		.ClusterDone:
			mov [curclus], dx	; Save current cluster
			cmp dx, 0xFF7		; Is it a bad cluster?
			je .Die				; If so, die
			cmp dx, 0xFF8		; Is this the last one?
			jge .Loaded			; If so, signal and return
			cmp si, bp			; Have we read enough sectors?
			jl .ReadFile		; If not, read more
			jmp .Done			; If not, but done, don't signal EOF
			
	.Loaded:
		; If we get here, the file's completely loaded
		pop es					; Restore ES value
		popa					; Restore registers
		mov bp, 0xFFFF			; Signal EOF
		ret						; Return
		
	.Done:
		pop es					; Restore ES value
		popa					; Restore registers
		clc						; No error
		ret						; Return to caller
		
	.Die:
		pop es					; Restore ES value
		popa					; Restore registers
		stc						; Set CF, there was an error
		ret						; Return to caller
		
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
	
	; Fucking old comp check
	;int 0x12
	;jc Errors.GeneralError
	;cmp ah, 0x86				; Support for this interrupt
	;je Errors.OldError
	;cmp ah, 0x80				; If not, there's REALLY something wrong
	;je Errors.OldError	
	;cmp ax, 639				; Only returns up to 639K
	;jl Errors.OldError
	
	;cmp [bpbBytesPerSector], 0x200
	;jne FatalError
	
	mov [bootdrv], dl			; Set bootdrv

	; Initialize FAT12 real mode driver
	call Fat12Init				; Initialize real mode FAT12 driver
	
	; Find stage 2
	mov si, Stage2Name			; We want to find Stage 2
	call Fat12Find				; Find the file
	jc FatalError
	
	; Load stage 2 into memory
	push STAGE2_ADDR_HIGH					
	pop fs
	mov di, STAGE2_ADDR_LOW		; Move offset into DI
	mov bp, STAGE2_BUFFER_SIZE	; Read until EOF, or out of reserved mem
	call Fat12Load				; Load Stage 2
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
	push word Fat12Load
	push word Fat12Find
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
;* 	Padding										*
;************************************************

times 510-($-$$) db 0
dw 0xAA55