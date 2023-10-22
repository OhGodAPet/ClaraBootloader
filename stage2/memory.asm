;****************************************************
;* 	GetMemoryLow()									*
;* 		- Gets amount of low memory in bytes		*
;*		- No input									*
;*		- Output									*
;*			- AX = Number of KB detected			*
;*			- CF is set on error					*
;*		- Errors									*
;*			- Any errors are BIOS errors			*
;*		- Requirements								*
;*			- BIOS interrupts are accessible		*
;*		- AX clobbered								*
;****************************************************
GetMemoryLow:
	xor eax, eax			; Clear EAX
	int 0x12				; Call BIOS
				
	; Error checks
	jc .Die					; General error
	cmp ah, 0x86			; Test for support
	je .Die					; Die if unsupported
	cmp ah, 0x80			; Test for invalid command
	je .Die					; Die if invalid
	clc						; Clear CF, success
	ret						; Return to caller
	
	.Die:
		stc					; Set CF, error
		ret					; Return to caller


;****************************************************
;* 	GetMemorySize()									*
;* 		- Gets amount of KB in the system			*
;*		- Will only report up to 4,194,303 MB		*
;*		- No input									*
;*		- Output									*
;*			- EAX = Number of KB detected			*
;*			- CF is set on error					*
;*		- Errors									*
;*			- Any errors are BIOS errors			*
;*		- Requirements								*
;*			- BIOS interrupts are accessible		*
;*		- EAX and ECX clobbered						*
;**************************************************** 
GetMemorySize:
	push ebx				; Save EBX
	push edx				; Save EDX
	
	; Clear registers for comparing
	xor ebx, ebx
	xor ecx, ecx
	xor edx, edx
	
	; Call interrupt
	mov ax, 0xE801			; BIOS Get Memory Size
	int 0x15				; Call interrupt

	; Error checks
	jc .Method2				; If error, try the second method
	cmp ah, 0x86			; AH = 0x86 means unsupported function
	je .Method2				; If unsupported, try second method
	cmp ah, 0x80			; AH = 0x80 means invalid command
	je .Method2				; If it's invalid, try second method

	; No error, get results
	cmp ax, 0				; If AX = 0, the result is in CX:DX
	je .InCX				; If in CX:DX, go parse it
	mov cx, ax				; If in AX:BX, move to CX:DX
	mov dx, bx				; Move second part
	
	; CX = # of KB between 1MB and 16MB
	; DX = # of 64KB blocks above 16MB
	.InCX:
		xor eax, eax		; Clear EAX
		mov ax, 64			; DX is in 64KB blocks
		mul dx				; Convert 64KB blocks to KB
		add ax, cx			; Add # of KB between 1MB and 16MB
		add ax, 1024		; Add the first MB
		clc					; Success, clear CF
		pop edx				; Restore EDX
		pop ebx				; Restore EBX
		ret					; EAX = Amount of KB in the system
	
	; E801 didn't work, try this one
	.Method2:
		clc					; May have used a JC to get here
		
		; Registers already cleared
		mov ax, 0xE881		; BIOS Get Memory Size
		int 0x15			; Call interrupt
		
		; Error checks
		jc .Fail			; Fail if error
		cmp ah, 0x86		; Is it unsupported?
		je .Fail			; If so, fail
		cmp ah, 0x80		; Is it an invalid command?
		je .Fail			; If so, fail
		
		; No error, check results
		cmp eax, 0			; If EAX = 0, result is in ECX:EDX
		je .InCX			; If in ECX:EDX, go parse it		
		mov ecx, eax		; Otherwise, move it to ECX:EDX
		mov ecx, ebx		; Move second part
		jmp .InCX			; Same for E801 and E881, go parse it
	.Fail:
		stc					; Set CF, there was an error
		ret 8				; Fix stack and return
		
;****************************************************
;* 	GetMemoryMap()									*
;* 		- Gets memory map from the BIOS				*
;*		- Input										*
;*			- EAX 		= Size of buffer (B)		*
;*			- ES:DI 	= Base address for map		*
;*		- Output									*
;*			- ES:DI		= Memory map				*
;*			- ECX 		= Number of map entries		*
;*			- CF is set on error					*
;*		- Notes										*
;*			- Length of entries is always 24B		*
;*			- Length is prefixed for multiboot		*
;*			- Entry structure (24B)					*
;*				- 0:  Length						*
;*				- 4:  Base address of memory region	*
;*				- 12: Length of region described	*
;*				- 16: Region type					*
;*				- 20: ACPI							*
;*		- Error code in AL (valid if CF is set)		*
;*			- 0: General error						*
;*			- 1: BIOS Error							*
;*			- 2: Buffer size too small				*
;*		- Requirements								*
;*			- Unreal mode active for DS				*
;*		- EAX, ECX, ESI, and EDI clobbered			*
;****************************************************

GetMemoryMap:
	push ebx						; Save EBX
	push edx						; Save EDX
	push ebp						; Save EBP
	
	mov esi, eax					; Save buffer size
	xor ebp, ebp					; EBP will be our counter
	
	xor eax, eax					; Upper 16 bits of EAX should be 0
	xor ebx, ebx					; EBX is the index into map
	mov word [es:di], 24			; Size of entry (for multiboot)
	add di, 2						; Advance pointer
	mov eax, 0xE820					; BIOS Get Memory Map function
	mov ecx, 24						; We want 24 bytes
	mov edx, 0x534D4150				; Magic number for the BIOS, 'SMAP'
	mov [es:di + 20], dword 1		; Make ACPI valid if not present
	int 0x15						; Call interrupt
	
	jc .BIOSError					; Carry flag means error
	cmp eax, 0x534D4150				; BIOS returns this on success
	jne .BIOSError					; Fail if it's not there
	cmp cl, 0						; CL = bytes stored
	jz .BIOSError					; If it's zero, fail
	cmp ebx, 0						; EBX = 0 means list is 1 entry
	je .BIOSError					; If so, it's useless
	
	.MemoryMapLoop:
		add di, 24					; Advance pointer
		inc ebp						; Increment counter
		sub esi, 28					; Update remaining space
		cmp esi, 28					; Can we fit another entry in?
		jb .OutOfSpace				; If not, die
		
		mov word [es:di], 24		; Size of entry (for multiboot)
		add edi, 2					; Advance pointer

	; Call the function again
	.Skip:
		cmp ebx, 0					; Is EBX 0?
		je .Done					; If so, no more entries
		xor eax, eax				; Upper 16 bits of EAX should be 0
		mov eax, 0xE820				; BIOS Get Memory Map function
		mov ecx, 24					; Read 24 bytes
		mov edx, 0x534D4150			; Magic number, BIOS may trash EDX
		mov [es:di + 20], dword 1	; Make ACPI valid if not present
		int 0x15					; Call BIOS interrupt
		jc .Done					; CF means end of list
		cmp eax, 0x534D4150			; BIOS returns this on success
		jne .BIOSError				; Fail if it's not there
		cmp cl, 0					; Is the entry length zero?
		je .Skip					; Skip any zero length entries
		cmp cl, 20					; Did we get the ACPI dword?
		jbe .NoACPI					; If not, we don't need to test it
		test byte [es:di + 20], 1	; If so, should we ignore it?
		je .Skip					; If so, skip this entry
	.NoACPI:
		mov ecx, [es:di + 8]		; Memory region length low dword
		or ecx, [es:di + 12]		; Test for 0 by ORing with high
		jz .Skip					; If memory length is 0, skip entry
		jmp .MemoryMapLoop			; It's good, read some more
	.BIOSError:
		mov al, 1					; Set error code
		jmp .Fail					; Die
	.OutOfSpace:
		mov al, 2					; Set error code, then fall through
	.Fail:
		stc							; Set CF, there was an error
		ret	12						; Fix stack and return to caller
	.Done:
		mov ecx, ebp				; Set number of entries read
		pop ebp						; Restore EBP
		pop edx						; Restore EDX
		pop ebx						; Restore EBX
		clc							; We used a JC
		ret							; Return
		