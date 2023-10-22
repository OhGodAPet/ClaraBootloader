;************************************************************************
;*  Second Stage Bootloader - by Wolf									*
;*																		*
;*	Current state of 0x00000000 - 0x000FFFFF:							*
;* 			* 0x00000000 - 0x000003FF - Real Mode IVT		(1KB)		*
;* 			* 0x00000400 - 0x000004FF - BIOS Data Area		(.25KB)		*
;*			* 0x00000500 - 0x00000BFF - Free				(1.75KB)	*
;*			* 0x00000C00 - 0x000009FF - Bootloader stack	(1KB)		*
;*			* 0x00001000 - 0x00007BFF - Stage 1 FS data		(27KB)		*
;*			* 0x00007C00 - 0x00007DFF - Stage 1 image		(.5KB)		*
;*			* 0x00007E00 - 0x000175FF - Stage 2 image		(62KB)		*
;* 			* 0x00017600 - 0x0009FFFF - Free				(546.5KB)	*
;* 			* 0x000A0000 - 0x000BFFFF - Video RAM			(128KB)		*
;* 			* 0x000B0000 - 0x000B7777 - Monochrome RAM		(32KB)		*
;* 			* 0x000B8000 - 0x000BFFFF - Color RAM			(32KB)		*
;* 			* 0x000C0000 - 0x000C7FFF - Video ROM BIOS		(32KB)		*
;* 			* 0x000C8000 - 0x000EFFFF - BIOS Shadow Area	(160KB)		*
;* 			* 0x000F0000 - 0x000FFFFF - System BIOS			(64KB)		*
;*	Design:																*
;*		Memory usage: 													*
;*			* 0x00017600 - 0x000215FF - Memory map			(40KB)		*
;*			* 0x00021600 - 0x0002DDFF - Temporary buffer	(50KB)		*
;*			* 0x0002DE00 - 0x0002E1FF - Info for kernel		(1KB)		*
;*			* 0x0002E200 - 0x00032FFF - Temp page tables	(19.5KB)	*
;*			* 0x00033000 - 0x00044FFF - Page tables			(72KB)		*
;*			* 0x00032400 - 0x0009FFFF - Unused				(364KB)		*
;*		Conventions:													*
;*			* Comments may be no longer than half a 1366x768 display	*
;*			* Comment blocks begin with ;* and end at a tab with a *	*
;************************************************************************

;************************************************
;*  Constants and other assembler directives	*
;************************************************ 

format binary
org 0x7E00
use16

LOADER_STACK_TOP 			equ	0x0009FF		; Loader wide stack

STAGE2_KRNL_BASE_ADDR		equ 0x100000		; Kernel base address

STAGE2_MEM_REQUIRE_KB		equ 0x004000		; Memory needed (B)

STAGE2_GDT32_CODE_SELECTOR	equ 0x000008		; 32 bit GDT code offset
STAGE2_GDT32_DATA_SELECTOR	equ 0x000010		; 32 bit GDT data offset

STAGE2_GDT64_CODE_SELECTOR	equ 0x000008		; 64 bit GDT code offset
STAGE2_GDT64_DATA_SELECTOR	equ 0x000010		; 64 bit GDT data offset

STAGE2_MEM_MAP_BUF_ADDR		equ 0x017600		; Mem map buf addr
STAGE2_MEM_MAP_BUF_HIGH 	equ 0x001760		; Mem map segment addr
STAGE2_MEM_MAP_BUF_LOW		equ	0x000000		; Mem map offset addr
STAGE2_MEM_MAP_BUF_SIZE		equ 0x00A000		; Size of mem map buf

STAGE2_TEMP_BUF_ABS			equ 0x021600		; Temp buffer addr
STAGE2_TEMP_BUF_HIGH		equ 0x002160		; Temp buffer segment
STAGE2_TEMP_BUF_LOW			equ 0x000000		; Temp buffer offset
STAGE2_TEMP_BUF_SIZE		equ 0x00C800		; Temp buffer size

STAGE2_KRNL_INFO_BASE_ADDR	equ 0x2DE00			; Kernel info struct area
STAGE2_KRNL_INFO_SIZE		equ 0x00400			; Info struct area size

STAGE2_PAGING_BUF_BASE_ADDR	equ	0x2E200			; Buffer base address
STAGE2_PD_BASE_ADDR			equ 0x2F000			; Space for the PDEs
STAGE2_PDPT_BASE_ADDR		equ 0x43000			; Space for the PDPTEs
STAGE2_PML4_BASE_ADDR		equ 0x44000			; Space for the PML4Es
STAGE2_PAGING_BUF_END_ADDR	equ 0x45000			; Buffer end address
STAGE2_PAGING_BUF_SIZE		equ 0x16E00			; Size in bytes

STAGE2_PAGING64_BUF_ADDR	equ 0x33000			; Buffer base address
STAGE2_PD64_BASE_ADDR		equ 0x33000			; Space for the PDEs
STAGE2_PDPT64_BASE_ADDR		equ 0x43000			; Space for the PDPTEs
STAGE2_PML464_BASE_ADDR		equ 0x44000			; Space for the PML4Es
STAGE2_PAGING64_END_ADDR	equ 0x45000			; Buffer end address

;************************************************
;*  Stage 2 signature							*
;************************************************ 

dd 'YIFF'

;************************************************
;*  Start of execution							*
;************************************************ 

start: jmp Stage2Main	

;************************************************
;*  External routines							*
;************************************************ 

include "errors.asm"
include "formats.asm"
include "memory.asm"
include "disk.asm"
include "cpu.asm"

;************************************************
;* Variables									*
;************************************************ 

KernelName							db "KRNL64  EXE"

BootDrive		rb 1
BytesPerSector	rw 1
FindFile		rw 1
LoadFile		rw 1

;************************************************
;*  Real Mode I/O Routines						*
;************************************************ 

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
;*  Stage 2 entry point							*
;************************************************ 

Stage2Main:
	; Store arguments
	pop ax									; Pop boot drive
	mov byte [BootDrive], al				; Upper byte has the flags
	pop [BytesPerSector]					; Pop BPS					
	pop [FindFile]							; Pop file finding routine
	pop [LoadFile]							; Pop file loading routine
	
	; Check for 586 or better
	call IdentifyCPU
	jc Errors.OldCPU
	
	; Get amount of memory
	;call GetMemorySize
	;jc Errors.GettingMemorySize
	
	; Make sure it's above the minimum
	;cmp eax, STAGE2_MEM_REQUIRE_KB
	;jb Errors.LowMemory
	
	; Enable A20 address line
	call EnableA20							; Call function
	jc Errors.A20							; If error, handle
	
	; Load first 8KB of file (headers) to temporary buffer
	push fs									; Save FS
	push word STAGE2_TEMP_BUF_HIGH			; Push segment
	pop fs									; Pop into FS
	mov di, STAGE2_TEMP_BUF_LOW				; Set DI to offset
	mov si, KernelName						; We want the kernel headers
	call LoadFileHeaders					; Call function
	jc Errors.LoadFileHeaders				; Handle any errors
	pop fs									; Restore FS
	
	; Enter Unreal Mode
	call EnterUnrealMode32					; Call function
	
	; Parse the file headers
	xor eax, eax							; Clear EAX
	mov ax, STAGE2_MEM_MAP_BUF_LOW			; Low 16 bits = offset
	shl eax, 16								; Shift to high 16 bits
	mov ax, STAGE2_MEM_MAP_BUF_HIGH			; Low 16 bits = segment
	xor ecx, ecx
	mov ecx, STAGE2_MEM_MAP_BUF_SIZE		; ECX = Size of buffer
	mov esi, STAGE2_TEMP_BUF_ABS			; ESI = File buffer
	mov edi, STAGE2_KRNL_INFO_BASE_ADDR		; EDI = Kernel info buffer
	
	call ParseFileHeaders					; Call function
	jc Errors.ParseFileHeaders				; Fix this
	
	cli
	hlt
	
	pushfd									; Save EFLAGS
	push eax
	
	; Load the modules
	mov ecx, STAGE2_TEMP_BUF_ABS			; ECX = Base of file buffer
	call LoadModules						; Load the modules
	cli
	hlt
	jc Errors.LoadModules
	
	; Load the kernel
	mov edi, [eax+40]						; Load offset
	mov si, KernelName						; Kernel name
	mov ebx, dword [eax+12]					; End address (32 only)
	mov eax, dword [eax]					; Base address (32 only)
	call LoadFileHigh						; Load the kernel
	jc Errors.LoadFileHigh
	
	pop ebx									; EBX = Pointer to base addr
	mov ecx, [ebx+24]						; ECX = Entry point offset
	mov edx, STAGE2_KRNL_INFO_BASE_ADDR		; EDX = Info structure ptr
	
	; Disable interrupts and NMIs
	cli										; Disable interrupts
	in al, 0x70								; Read in CMOS register
	or al, 0x80								; Set NMI disable bit
	out 0x70, al							; Send to CMOS register
	
	pop eax									; Restore EFLAGS
	bt eax, 10								; Is DF set?
	jc ExecuteKernel_x86_64					; If so, use 64 bit mode
	jmp ExecuteKernel_x86_32				; Otherwise, use 32 bit mode
	
;****************************************************
;* 	ExecuteKernel_x86_64()							*
;* 		- Enters 64 bit mode and executes kernel	*
;*		- Input										*
;*			- EBX	= Kernel base address pointer	*
;*			- ECX	= Entry point offset			*
;*			- EDX	= Kernel info structure pointer	*
;*		- No output									*
;*		- Registers don't matter					*
;**************************************************** 
	
	; To enter long mode, we have to create page tables, load a 64 bit
	; GDT, enable PAE in CR4, load the physical address of our PML4
	; table into CR3, set LME in the EFER MSR, and set PE and PG in
	; CR0. In accordance with the Clara specification, the page tables
	; set up IA-32e paging with 2MB pages, identity mapping the first
	; 16GB of memory, and process-context identifiers are disabled.
	; All pages are marked supervisor, and are readable, writable, and
	; executable.
	
ExecuteKernel_x86_64:
	clc										; Used a JC to get here
	push ecx								; Save entry point offset
	push edx								; Save kernel info pointer
	call CreatePageTables					; Create the page tables				
	lgdt [GDT64]							; Load the 64 bit GDT
	
	; Now load CR3 with a pointer to PML4, and set all those flags
	
	mov eax, cr4							; Get the CR4 register
	or eax, 0x20							; Set bit 5 (PAE)
	mov cr4, eax							; Store it
	
	mov eax, STAGE2_PML4_BASE_ADDR			; Has to go into EAX first
	mov cr3, eax							; Load PML4 into CR3
	
	mov ecx, 0xC0000080						; EFER MSR
	rdmsr									; Read it into EAX
	or eax, 0x100							; Set LME
	wrmsr									; Store the register
	
	mov eax, cr0							; Get CR0
	or eax, 0x80000001						; Set PE and PG
	mov cr0, eax							; Store it
	
	pop edx									; Restore info struct ptr
	pop ecx									; Restore entry point offset
	jmp STAGE2_GDT64_CODE_SELECTOR:Entry64	; Far jump to load CS

;****************************************************
;* 	ExecuteKernel_x86()								*
;* 		- Enters 32 bit mode and executes kernel	*
;*		- Input										*
;*			- EBX	= File info structure pointer	*
;*			- ECX	= Entry point offset			*
;*			- EDX	= Kernel info structure pointer	*
;*		- No output									*
;*		- Registers don't matter					*
;**************************************************** 

; For 32 bit protected mode, we just have to load a 32 bit GDT, set
; the PE bit in CR0, and long jump to the 32 bit entry point, as the
; arguments have already been set.

ExecuteKernel_x86_32:
	lgdt [GDT32]							; Load the 32 bit GDT
	mov eax, cr0							; Move CR0 into EAX
	or eax, 1								; Set PE bit
	mov cr0, eax							; Load into CR0
	
	jmp STAGE2_GDT32_CODE_SELECTOR:Entry32	; Far jump to load CS


GeneralError:
	mov si, MsgGenErr
	call PrintLine
	cli
	hlt

;************************************************
;*  32 bit entry point							*
;*		- We have a 586 or better				*
;*		- We have at least required memory		*
;*		- We have a memory map from the BIOS	*
;*		- We have A20 enabled, and a GDT		*
;*		- Interrupts and NMI disabled			*
;************************************************ 

use32

; Parameters:
; EBX = Pointer to 32 bit base address
; ECX = Entry point offset
; EDX = Address of kernel information structure (NULL if none)

Entry32:
	mov eax, STAGE2_GDT32_DATA_SELECTOR		; Data selector
	mov ds, ax								; Set DS
	mov es, ax								; Set ES
	mov fs, ax								; Set FS
	mov gs, ax								; Set GS
	mov ss, ax								; Set SS
	
	; Compute base address (Base addr + entry offset = entry point addr)
	mov ebp, dword [ebx]
	add ebp, ecx
	
	; Put the info structure pointer (if any) in EAX and jump
	xchg edx, eax
	jmp ebp
	
; 64 bit loader

use64

; Parameters:
; EBX = Pointer to 64 bit base address
; ECX = Entry point offset
; EDX = Address of kernel information structure (NULL if none)

Entry64:
	mov rax, STAGE2_GDT64_DATA_SELECTOR		; Data selector
	mov ds, ax								; Set DS
	mov es, ax								; Set ES
	mov fs, ax								; Set FS
	mov gs, ax								; Set GS
	mov ss, ax								; Set SS
	
	; Compute base address (Base addr + entry offset = entry point addr)
	mov rbp, qword [ebx]					; EBP = Base address
	movsxd rcx, ecx							; Sign-extend the offset
	add rbp, rcx							; EBP = Entry point address
	
	; Load appropriate register values and leave
	movsxd rcx, edx							; RCX = Info struct, if any										
	jmp rbp									; Jump to kernel

	