;********************************************************************
;*  CPU stuff 														*
;********************************************************************

;****************************************************
;*  Global Descriptor Tables						*
;*	Each descriptor	is one quadword in length		*
;*	Null Descriptor:								*
;*		* Must be all zero							*
;*	Code/Data Descriptor:							*
;*		* 0xFFFF 	- Segment limit low				*
;*		* 0x0000 	- Base low, all zeros			*
;*		* 0x00		- Base middle, all zeros		*
;*		* 0x9A 										*
;*			* 0 - Not using virtual memory			*
;*			* 1 - Read and execute					*
;*			* 0 - Non-conforming					*
;*			* X - (1 for code, 0 for data)			*
;*			* 1 - Not a system descriptor			*
;*			* 0 - Not ring 3						*
;*			* 0 - Ring 0							*
;*			* 1 - Is in memory (no paging yet)		*
;*		* 0xCF										*
;*			* 1 - 4KB increments					*
;*			* X - (1 for x86, 0 for x64)			*
;*			* X - (0 for x86, 1 for x64)			*
;*			* 0 - Available for OS usage			*
;*			* 1 - Bit 16 of segment limit			*
;*			* 1 - Bit 17 of segment limit			*
;*			* 1 - Bit 18 of segment limit			*
;*			* 1 - Bit 19 of segment limit			*
;*		* 0x00		- Base high, all zeros			*
;*	Notes:											*
;*		* Code selector is offset 0x08				*
;*		* Data selector is offset 0x10				*
;****************************************************

; 32 bit GDT for Unreal Mode

GDTStart32:
	dq 0x0000000000000000					; Null descriptor
	dq 0x00CF9A000000FFFF					; Code descriptor
	dq 0x00CF92000000FFFF					; Data descriptor
GDT32:
	dw GDT32 - GDTStart32 - 1				; Size of GDT
	dd GDTStart32							; Base of GDT

; 64 bit GDT

GDTStart64:
	dq 0x0000000000000000					; Null descriptor
	dq 0x00AF9A000000FFFF					; Code descriptor
	dq 0x00AF92000000FFFF					; Data descriptor
GDT64:
	dw GDT64 - GDTStart64 - 1				; Size of GDT
	dd GDTStart64							; Base of GDT

;************************************************
;* 	EnableA20()									*
;* 		- Enables the A20 address line			*
;*		- No input								*
;*		- Output								*
;*			- CF set on error					*
;*		- Error code in AL						*
;*			- 0: General error					*
;*			- 1: KBC error						*
;*		- All registers preserved				*
;************************************************
EnableA20:
	pushad

	; Let's try the methods in order of portability
	.A20_Method_1:
		call .A20WaitInput		; Wait for input buffer to be clear
		mov al, 0xAD			; Disable keyboard command
		out 0x64, al			; Send to keyboard
		call .A20WaitInput		; Wait until input buffer is ready
		mov al, 0xD0			; Request to read KBC output buffer
		out 0x64, al			; Send to KBC

		call .A20WaitOutput		; Wait for output buffer to be full
		in al, 0x60				; Read output buffer into CL
		or al, 2				; Set A20 enable bit
		xchg al, cl				; Store in CL to preserve it

		call .A20WaitInput		; Wait for input buffer to be clear
		mov al, 0xD1			; Request to write output port
		out 0x64, al			; Send command

		call .A20WaitInput		; Wait until input buffer is clear
		xchg al, cl				; Put output data with A20 bit set in AL
		out 0x60, al			; Write data back into output buffer

		call .A20WaitInput		; Wait until input buffer is ready
		mov al, 0xAE			; Enable keyboard command
		out 0x64, al			; Send command
		call .CheckA20			; If A20 isn't enabled, fall through

	; Note: Doesn't work on Bochs
	.A20_Method_2:
		call .A20WaitInput		; Wait until the KBC is ready
		mov al, 0xDD			; Enable A20 command
		out 0x64, al			; Send command
		call .CheckA20			; Check if enabled, if not, fall through

	.A20_Method_3:
		mov ax, 0x2401			; BIOS Enable A20 command
		int 0x15				; Call interrupt

		; Error checks
		jc .A20_Method_4		; Try next method if error
		cmp ah, 0				; Is AH 0?
		jne .A20_Method_4		; If not, error. Try next method

		; No error
		call .CheckA20			; If A20 is not enabled, next method

	.A20_Method_4:
		mov al, 2				; Least portable, System Control Port A
		out 0x92, al			; Send A20 enable bit
		call .CheckA20			; Check if A20 is enabled
		stc						; We couldn't enable A20, set CF
		ret						; Return

	.CheckA20:
		mov ax, 0x2402			; BIOS Query A20 Status
		int 0x15				; Call interrupt

		; Error checks
		jc .Check2				; CF = Error
		cmp ah, 0x86			; AH = 0x86 means unsupported function
		je .Check2				; If error, try the backup check
		cmp ah, 0x01			; AH = 0x01 means KBC is in secure mode
		je .Check2				; Again, try backup check
		cmp cx, 0xFFFF			; Keyboard not responding
		je .KBCError			; The KBC is locked up, error

		; No error
		cmp al, 1				; No errors found, check result
		je .A20Enabled			; If AL = 1 and no error, A20 is enabled
		ret						; If AL is not 1, A20 is disabled, ret

	.Check2:
		mov al, 0xD0			; KBC read output port command
		out 0x64, al			; Send to KBC port
		call .A20WaitOutput		; Wait until the KBC is ready
		in al, 0x60				; Read output data (from input buffer)
		test al, 2				; Test bit 2
		jnz .A20Enabled			; If it's set,
		ret						; A20 is disabled, ret

	.A20WaitOutput:
		push cx					; Save CX so it's not clobbered
		xor cx, cx				; Clear counter
		.A20WaitOutLoop:
			in al, 0x64			; Read KBC status register into AL
			test al, 1			; Isolate the first bit
			jnz .A20WaitDone	; If it's 1, the buffer is OK to read
		.A20OutLoopInc:
			cmp cx, 0xFFFF		; Is CX equal to 0xFFFF?
			je .KBCError2		; If so, KBC is not responding
			inc cx				; Nope, increment counter
			jmp .A20WaitOutLoop	; Keep waiting

	.A20WaitInput:
		push cx					; Save CX so it's not clobbered
		xor cx, cx				; Clear counter
		.A20WaitInLoop:
			in al, 0x64			; Read KBC status register into AL
			test al, 2			; Isolate the second bit
			jz .A20WaitDone		; If it's 0, the buffer is OK to write
		.A20InLoopInc:
			cmp cx, 0xFFFF		; Is CX equal to 0xFFFF?
			je .KBCError2		; If so, KBC is not responding
			inc cx				; Nope, increment counter
			jmp .A20WaitInLoop	; Keep waiting

		.A20WaitDone:
			pop cx				; If we get here, the KBC is ready
			ret					; Return

	; If we get here, A20 is enabled. Signal success and return
	.A20Enabled:
		pop ax					; Pop previous return address off stack
		popad					; Restore registers
		clc						; Make sure CF is clear
		ret						; Return

	.KBCError:
		pop ax					; Pop old return address
		popad					; Restore registers
		stc						; Signal error
		ret						; Return

	.KBCError2:
		pop ax					; Pop old return address
		pop ax					; Pop saved CX
		popad					; Restore saved registers
		stc						; Signal error
		ret						; Return

;****************************************************
;* CreatePageTables()								*
;* 		- Creates tables that identity map 16GB		*
;*		- No input									*
;*		- Output									*
;*			- Page table at given address			*
;*		- No errors									*
;*		- Requirements								*
;*			- STAGE2_PAGING_BUF_BASE_ADDR constant	*
;*			- STAGE2_PD_BASE_ADDR constant			*
;*			- STAGE2_PDPT_BASE_ADDR constant		*
;*			- STAGE2_PML4_BASE_ADDR constant		*
;*			- STAGE2_PAGING_BUF_END_ADDR constant	*
;*			- STAGE2_PAGING_BUF_SIZE constant		*
;*		- Additional information					*
;*			- Tables are for IA-32e paging			*
;*			- Creates one 2MB page					*
;*	- All registers preserved						*
;****************************************************

CreatePageTables:
	pushad									; Save all registers

	; Calculate size of pagetable buffer in dwords
	; Note that addresses are 4KB aligned, no remainder
	xor edx, edx							; Prepare EDX
	mov eax, STAGE2_PAGING_BUF_SIZE			; Number of bytes to fill
	mov ecx, 4								; 4 bytes per dword
	div ecx									; Divide; ignore remainder

	; Zero out buffer
	mov ecx, eax							; ECX = Dwords to fill
	xor eax, eax							; We're writing zeroes
	mov edi, STAGE2_PAGING_BUF_BASE_ADDR	; Starting address
	rep stos dword [es:edi]					; Fill buffer

	; The address field in the entries start at bit 12; the processor
	; assumes the others are zero, forcing the address to be 4KB aligned.
	; Because of this, we can set the flags using address | flags.

	; Thoughts: Adding would preserve the OR'd flags, right?
	; Write all the PDEs in one loop, using something like:
	; if((ecx == 0) && (edx == 0)) inc edx;
	; else if(ecx == 0) shl edx, 1;
	; If I decided to integrate the flags thing, I could
	xor edx, edx							; High dword is zero
	xor ecx, ecx							; Clear ECX
	mov edi, STAGE2_PD_BASE_ADDR			; Writing PDs

	.WritePDEsFor4GB:
		mov eax, ecx						; Copy low dword of address
		or eax, 0x87						; Set bits 0-3 and bit 7
		mov dword [edi+4], edx				; Write high dword
		mov dword [edi], eax				; Write low dword
		add edi, 8							; Advance to next entry
		add ecx, 0x200000					; Advance address to map
		cmp ecx, 0							; Have we mapped 4GB?
		jne .WritePDEsFor4GB				; If not, loop some more

	.DoneMapping4GB:
		mov edx, 1							; 32nd bit set = 4GB
		xor ecx, ecx						; Clear ECX

	.WritePDEsFor8GB:
		mov eax, ecx						; Copy low dword of address
		or eax, 0x87						; Set bits 0-3 and bit 7
		mov dword [edi+4], edx				; Write high dword
		mov dword [edi], eax				; Write low dword
		add edi, 8							; Advance to next entry
		add ecx, 0x200000					; Advance address to map
		cmp ecx, 0							; Have we mapped 4GB?
		je .DoneMapping8GB					; Yep, leave
		jmp .WritePDEsFor8GB				; Nope, loop some more

	.DoneMapping8GB:
		mov edx, 2							; 33rd bit set = 8GB
		xor ecx, ecx						; Clear ECX

	.WritePDEsFor12GB:
		mov eax, ecx						; Copy low dword of address
		or eax, 0x87						; Set bits 0-3 and bit 7
		mov dword [edi], edx				; Write high dword
		mov dword [edi+4], eax				; Write low dword
		add edi, 8							; Advance to next entry
		add ecx, 0x200000					; Advance address to map
		cmp ecx, 0							; Have we mapped 4GB?
		je .DoneMapping12GB					; Yep, leave
		jmp .WritePDEsFor12GB				; Nope, loop some more

	.DoneMapping12GB:
		mov edx, 4							; 34th bit set = 12GB
		xor ecx, ecx						; Clear ECX

	.WritePDEsFor16GB:
		mov eax, ecx						; Copy low dword of address
		or eax, 0x87						; Set bits 0-3 and bit 7
		mov dword [edi], edx				; Write high dword
		mov dword [edi+4], eax				; Write low dword
		add edi, 8							; Advance to next entry
		add ecx, 0x200000					; Advance address to map
		cmp ecx, 0							; Have we mapped 4GB?
		je .DoneWritingPDEs					; Yep, leave
		jmp .WritePDEsFor16GB				; Nope, loop some more

	.DoneWritingPDEs:
		mov ecx, STAGE2_PD_BASE_ADDR		; PD addresses goes in PDPT
		mov edi, STAGE2_PDPT_BASE_ADDR		; Writing the PDPT
		xor edx, edx						; Zero EDX for a counter

	; All PD addresses are thankfully under 4GB, so we don't have
	; to use a high dword.

	.WritePDPTEs:
		mov eax, ecx						; Copy low dword of address
		or eax, 7							; Set bits 0-3
		mov dword [edi], eax				; Write PDPTE
		add edi, 8							; Advance to next entry
		add ecx, 0x1000						; Get address of next PD
		inc edx								; Increment counter
		cmp edx, 16							; Did we write 16 PDPTEs?
		jge .DoneWritingPDPTEs				; If yes, done
		jmp .WritePDPTEs					; Otherwise, write more

	.DoneWritingPDPTEs:
		mov eax, STAGE2_PDPT_BASE_ADDR		; PDPT address goes in PML4T
		mov edi, STAGE2_PML4_BASE_ADDR		; Writing the PML4T
		or eax, 7							; Set bits 0-3
		mov dword [edi], eax				; Write PML4E

	popad									; Restore saved registers
	ret										; Return to caller

;************************************************
;* 	IdentifyCPU()								*
;* 		- Checks for all CPUs before the 586	*
;*		- No input 								*
;*		- Output								*
;*			- CF set if the CPU < 586			*
;* 		- All registers preserved				*
;*		- Technique								*
;*			8086/8088:							*
;*				Intel says bits 12-15 of FLAGS	*
;*				are always set on the 8086/8088	*
;*			80286:								*
;*				Intel says bits 12-15 of FLAGS	*
;*				are always clear in real mode	*
;*			80386:								*
;*				Intel says bit 18 was not 		*
;*				introduced in EFLAGS until the 	*
;*				486, and cannot be set on		*
;*				the 386							*
;*			80486:								*
;*				Intel says the 486 is the last	*
;*				model without the CPUID 		*
;*				instruction, so if the ID bit	*
;*				cannot be set, it's a 486		*
;************************************************
IdentifyCPU:
	pushaw

	.Check8086:
		pushf				; Push the FLAGS register
		pop ax				; Put FLAGS in ax
		mov cx, ax			; Save original values
		and ax, 0x0FFF		; Clear bits 12-15
		push ax				; Push FLAGS back onto the stack
		popf				; Pop them into FLAGS

		pushf				; Push again
		pop ax				; Pop into AX
		and ax, 0xF000		; Mask out all but bits 12-15
		cmp ax, 0xF000		; If they're set, it's an 8086/8088
		jne .Check286		; Otherwise, it's not an 8086/8088

		push sp				; Intel says to double check
		pop dx				; Pop SP into DX
		cmp dx, sp			; If they're different, it's an 8086/8088
		je .Check286		; If not, unknown (I continue to make sure)
	.Cleanup8086:			; If we get here, it's an 8086/8088
		push cx				; Push the saved FLAGS register
		popf				; Restore FLAGS
		jmp .TooOld			; Indicate no CPUID

	.Check286:
		push cx				; Clean up after 8086/8088 check
		popf				; Restore FLAGS

		; Note that we're already in real mode, no need to enter V86
		pushf 				; Save FLAGS
		pop ax				; Pop into AX
		mov ax, cx			; Save old value
		or ax, 0xF000		; Clear bits 12-15
		push ax				; Push them back
		popf				; Pop into FLAGS

		pushf				; Get them again
		pop ax				; Pop back into AX
		and ax, 0xF000		; Isolate 12-15, if they're clear, 286
		jnz .Check386		; If they weren't clear, not a 286
	.Cleanup286:			; If we get here, it's a 286
		push cx				; Push the saved FLAGS onto the stack
		popf				; Pop into FLAGS
		jmp .TooOld			; Indicatie no CPUID

	.Check386:
		push cx				; Cleanup after 286 check
		popf				; Restore FLAGS register

		pushfd				; We know it's at least a 386
		pop eax				; Pop EFLAGS into EAX
		mov ecx, eax		; Save old value
		or eax, 0x40000		; Set the AC bit
		push eax			; Push onto the stack
		popfd				; And pop into EFLAGS

		pushfd				; Save them again
		pop eax				; Pop into EAX
		and eax, 0xFFFBFFFF	; Isolate the bit
		jnz .Check486		; If it's 1, the bit can be set, not a 386
	.Cleanup386:			; If we get here, it was 0, proc is a 386
		push ecx			; Restore saved EFLAGS
		popfd				; Pop into register
		jmp .TooOld			; Indicate no CPUID

	.Check486:
		push ecx			; Clean up after 386 check
		popfd				; Pop into EFLAGS

		pushfd				; Save EFLAGS
		pop eax				; Pop into EAX
		mov ecx, eax		; Back up value
		xor eax, 0x200000	; If we can change the ID flag, we have CPUID
		push eax			; Push back onto the stack
		popfd				; Pop into EFLAGS

		pushfd				; Push them onto the stack
		pop eax				; Pop into EAX
		cmp eax, ecx		; Check against our backup
		jne .Good			; If they're not equal, the bit changed
	.Cleanup486:			; If we get here, the bit didn't change
		push ecx			; Push our backup
		popfd				; Pop into EFLAGS and fall through

	.TooOld:
		popaw				; Pop the saved registers
		stc					; Indicate no CPUID
		ret					; Return to caller

	.Good:
		push ecx			; Clean up after 486 check
		popfd				; Pop saved EFLAGS
		popaw				; Pop saved registers
		clc					; Make sure CF is clear, CPUID is supported
		ret					; Return to caller

;************************************************
;* 	EnterUnrealMode32()							*
;* 		- Allows extension of segment registers	*
;*		- Input 								*
;* 			- GDT32 = GDT Pointer				*
;*		- Output								*
;*			- Segment registers (except CS)		*
;* 		- All registers preserved				*
;************************************************

EnterUnrealMode32:
	pushad									; Save all registers

	; Disable NMIs
	in al, 0x70								; Read in CMOS register
	or al, 0x80								; Set NMI disable bit
	out 0x70, al							; Send to CMOS

	; Set up GDT and enter PMode
	cli										; Interrupts now == BAD
	lgdt [GDT32]							; Load GDT into GDTR

	mov eax, cr0							; Move CR0 into EAX
	or eax, 1								; Set PMode bit
	mov cr0, eax							; Put it back

	; Extend all segment register limits (except CS)
	mov bx, 0x10							; Load GDT offset into BX
	mov ds, bx								; Extend DS
	mov es, bx								; Extend ES
	mov fs, bx								; Extend FS
	mov gs, bx								; Extend GS
	mov ss, bx								; Extend SS

	; Drop into Unreal Mode
	and eax, 0xFFFFFFFE						; Clear PMode bit
	mov cr0, eax							; Drop into Unreal Mode

	xor ax, ax								; Fix the registers
	mov ds, ax								; Fix DS
	mov es, ax								; Fix ES
	mov fs, ax								; Fix FS
	mov gs, ax								; Fix GS
	mov ss, ax								; Fix SS

	; Enable NMIs
	in al, 0x70								; Read in CMOS register
	and al, 0x7F							; Clear NMI disable bit
	out 0x70, al							; Store modified data
	sti										; Re-enable interrupts

	popad									; Restore saved registers
	ret										; Return to caller
