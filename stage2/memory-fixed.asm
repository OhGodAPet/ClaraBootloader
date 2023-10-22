;
;	memory.asm
;	Memory
;

;
;	GetMemoryLow
;	Clobbered Registers:
;		AX
;	Arguments:
;		None
;	Returns:
;		AX			KiB detected
;		CF			Set on error
;
GetMemoryLow:
	; Invoke BIOS for memory
	xor		eax, eax
	int		0x12
	
	; Check for errors
	jc		.Error
	cmp		ah, 0x86
	je		.Error
	cmp		ah, 0x80
	je		.Error
	
	; Success
	clc
	ret
	
	; Error
	.Error:
		stc
		ret

;
;	GetMemorySize
;	Clobbered Registers:
;		EBX
;	Arguments:
;		None
;	Returns:
;		EAX			KiB detected
;		CF			Set on error
;
;	Shouldn't be relied on, can only report up to 4GB
;
GetMemorySize:
	; Preserve registers
	push	ecx
	push	edx
	
	; Clear EAX and EBX
	xor		eax, eax
	xor		ebx, ebx
	
	; Invoke BIOS
	mov		ax, 0xE801
	int		0x15
	
	; Check for error
	jc		.MethodTwo
	cmp		ah, 0x86
	je		.MethodTwo
	cmp		ah, 0x80
	je		.MethodTwo
	
	; Find out what registers the info we want is in
	cmp		ax, 0x0000				; If AX == 0x0000, info's in CX/DX
	je		.InCXDX
	
	; In AX/BX registers
	shl		ebx, 6					; EBX *= 64
	add		eax, ebx				; EAX += EBX
	
	; Clean up and return
	pop		edx
	pop		ecx
	clc
	ret
	
	; In CX/DX registers
	.InCXDX:
		shr		edx, 6				; EDX *= 64
		xchg	eax, ecx			; EAX = ECX
		xchg	ebx, edx			; EBX = EDX
		add		eax, ebx			; EAX += EBX
		
		; Clean up and return
		pop		edx
		pop		ecx
		clc
		ret
	
	; Method Two
	.MethodTwo:
		; Invoke BIOS
		mov		ax, 0xE881
		int		0x15
		
		; Check for error
		jc		.MethodTwo
		cmp		ah, 0x86
		je		.MethodTwo
		cmp		ah, 0x80
		je		.MethodTwo
		
		; Find out what registers the info we want is in
		cmp		ax, 0x0000				; If AX == 0x0000, info's in CX/DX
		je		.InCXDX
		
		; In AX/BX registers
		shl		ebx, 4					; EBX *= 64
		add		eax, ebx				; EAX += EBX
		
		; Clean up and return
		pop		edx
		pop		ecx
		clc
		ret
	
	; Error
	.Error:
		pop		edx
		pop		ecx
		stc
		ret

;
;	GetMemoryMap
;	Clobbered Registers:
;		EAX, ECX, ESI, EDI
;	Arguments:
;		EAX			Length
;		ES:DI		Buffer
;	Returns:
;		ECX			Number of map entries
;		ES:DI		Buffer
;		CF			Set on error
;			AL		Error code
;			 0	General
;			 1	BIOS Error
;			 2	Buffer too small
;
GetMemoryMap:
	; Save registers
	push	ebx
	push	edx
	push	ebp
	
	; Save buffer & clear counter
	mov		esi, eax
	xor		ebp, ebp
	
	; Invoke BIOS for first part of memory map
	xor		eax, eax
	xor		ebx, ebx
	mov		word [es:di], 24
	add		di, 2
	mov		eax, 0xE820
	mov		ecx, 24
	mov		edx, 0x534D4150
	mov		[es:di + 20], dword 1
	int		0x15
	
	; Check for errors
	jc		.BIOSError
	cmp		eax, 0x534D4150
	jne		.BIOSError
	cmp		cl, 0
	jz		.BIOSError
	cmp		ebx, 0
	je		.BIOSError
	
	; Memory Map loop
	.Loop:
		; Update our position in the buffer
		add		di, 24
		inc		ebp
		
		; Check if we have enough space for another entry
		sub		esi, 28
		cmp		esi, 28
		jb		.OutOfSpace
		
		; Advance pointer
		mov		word [es:di], 24
		add		edi, 2
	
	; Invoke BIOS again
	.Skip:
		; Check if we're done
		cmp		ebx, 0
		je		.Done
		
		; Invoke BIOS
		mov		eax, 0x0000E820
		mov		ecx, 24
		mov		edx, 0x534D4150
		mov		[es:di + 20], dword 1
		int		0x15
		
		; Check for errors
		jc		.Done
		cmp		eax, 0x534D4150
		jne		.BIOSError
		cmp		cl, 0
		je		.Skip
		
		; Check if we have an ACPI dword
		cmp		cl, 20
		jbe		.NoACPI
		
		test	byte [es:di + 20], 1
		je		.Skip
	
	; No ACPI dword
	.NoACPI:
		mov		ecx, [es:di + 8]
		or		ecx, [es:di + 12]
		jz		.Skip
		jmp		.Loop
	
	; BIOS Error
	.BIOSError:
		mov		al, 1
		jmp		.Error
	
	; Out of Space Error
	.OutOfSpace:
		mov		al, 2
		jmp		.Error
	
	; General error
	.Error:
		stc
		ret		12
	
	; Done
	.Done:
		mov		ecx, ebp
		pop		ebp
		pop		edx
		pop		ebx
		clc
		ret

;
;	CreatePageTables
;	Copied from Clara Bootloader source
;	No registers clobbered
;	Arguments:
;		None
;	Returns:
;		Nothing
;
CreatePageTables:
	pushad									; Save all registers

	; Calculate size of pagetable buffer in dwords
	; Note that addresses are 4KB aligned, no remainder
	xor edx, edx							; Prepare EDX
	mov eax, PAGING_BUFFER_SIZE			; Number of bytes to fill
	mov ecx, 4								; 4 bytes per dword
	div ecx									; Divide; ignore remainder
	
	; Zero out buffer
	mov ecx, eax							; ECX = Dwords to fill
	xor eax, eax							; We're writing zeroes
	mov edi, ADDRESS_PAGING	; Starting address
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
	mov edi, ADDRESS_PD			; Writing PDs
	
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
		mov ecx, ADDRESS_PD		; PD addresses goes in PDPT
		mov edi, ADDRESS_PDPT		; Writing the PDPT
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
		mov eax, ADDRESS_PDPT		; PDPT address goes in PML4T
		mov edi, ADDRESS_PLM4		; Writing the PML4T
		or eax, 7							; Set bits 0-3
		mov dword [edi], eax				; Write PML4E
		
	popad									; Restore saved registers
	ret										; Return to caller