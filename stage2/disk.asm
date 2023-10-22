;****************************************************
;* 	LoadFileHeaders()								*
;* 		- Loads the first 8KB of a file				*
;*		- Input 									*
;*			- SI		= Pointer to file name		*
;* 			- FS:DI		= Destination address		*
;*		- Output									*
;*			- File data at FS:DI					*
;*			- CF set on error						*
;*		- Error code in AL (valid if CF = 1)		*
;*			- 0: General error						*
;*			- 1: File not found (does it exist?)	*
;*			- 2: Subsystem error when loading file	*
;* 		- All registers preserved					*
;****************************************************

LoadFileHeaders:
	pushad									; Preserve registers
	call word [FindFile]					; Find the file
	jc .ErrorFindingFile					; If error, signal
	
	; Address is already in FS:DI
	xor dx, dx								; Prepare DX
	mov ax, 8192							; We want 8KB (or until EOF)
	div word [BytesPerSector]				; Divide to get sectors
	mov bp, ax								; Screw the remainder
	inc bp									; Add one just in case
	call word [LoadFile]					; Load the file
	jc .ErrorLoadingFile					; Die on error
	popad									; Restore saved registers
	ret										; Return to caller
	
	.ErrorFindingFile:
		popad								; Restore saved registers
		mov al, 1							; Set error code
		stc									; Set CF, error
		ret									; Return to caller
	.ErrorLoadingFile:
		popad								; Restore saved registers
		mov al, 2							; Set error code
		stc									; Set CF, error
		ret									; Return to caller
		
;****************************************************
;* 	LoadFileHigh()									*
;* 		- Loads files above 1MB						*
;*		- Input 									*
;*			- ES:EAX 	= Destination address		*
;*			- EBX 		= Length (in bytes)			*
;*			- EDI 		= Offset within image		*
;*			- DS:SI 	= Address of file name		*
;*		- Output									*
;*			- ES:EAX	= File contents				*
;*			- CF set on error						*
;*		- Error code in AL (valid if CF = 1)		*
;*			- 0: General error						*
;*			- 1: Bad arguments						*
;*			- 2: File not found (does it exist?)	*
;*			- 3: Subsystem error when loading file	*
;*		- Requirements								*
;*			- ES limit is 4GB						*
;*			- STAGE2_TEMP_BUF_HIGH constant			*
;*			- STAGE2_TEMP_BUF_LOW constant			*
;*		- Additional information					*
;*			- Will not load under 1MB				*
;*			- Unable to load above 4GB				*
;* 		- All registers preserved					*
;****************************************************

LoadFileHigh:
	pushad									; Preserve registers
	push fs									; Save FS
	
	; Sanity check address
	cmp eax, 0x100000						; Is the dest. addr < 1MB?
	jl .BadArgument							; If so, signal error
	
	; Find the file
	call word [FindFile]					; Call FindFile
	jc .FileNotFound						; If it errors, die
	
	; Load address of temp buffer
	push word STAGE2_TEMP_BUF_HIGH			; Push segment onto stack
	pop fs									; Pop into FS
	mov edx, edi							; EDX = Offset
	
	; Current state: EDX = Offset, ES:EAX = Address, EBX = Length
	.LoadFile:
		mov bp, 2							; Load two sectors
		mov di, STAGE2_TEMP_BUF_LOW			; Move offset into DI
		call word [LoadFile]				; Load to temp buffer
		jc .SubSysErrorLoadingFile			; Signal error on failure
		
		movzx ecx, word [BytesPerSector]	; Get bytes per sector
		movzx edi, word [BytesPerSector]	; Must be the same size
		add ecx, edi						; We read two sectors
		
		cmp dword [esp + 18], 0				; Is there a length arg?
		je .CheckOffset						; If not, load until EOF
		
		cmp ebx, ecx						; Is length left < 2 sectors?
		jl .FinishCopy						; If so, copy last bytes
		
	.CheckOffset:
		cmp edx, ecx						; Is the offset > 2 sectors?
		jnge .KeepLoading					; If it's not, go load
		
		sub edx, ecx						; Otherwise, skip these two
		jmp .LoadFile						; Read next two sectors
		
	; Current state: EDX = Offset remaining, ES:EAX = Address,
	; EBX = Length, ECX = Bytes per sector * 2. Offset is < 2 sectors 
	; rep movsb is used to support byte aligned offsets
	.KeepLoading:
		sub ecx, edx						; Subtract offset
		sub ebx, ecx						; Subtract from bytes left
		push ecx							; Save number of bytes
		mov esi, STAGE2_TEMP_BUF_LOW		; Reading from temp buffer
		add esi, edx						; Index into tmp buffer
		xor edx, edx						; Offset done, zero it
		mov edi, eax						; Set destination addr
		rep movs byte [es:edi], [fs:esi]	; FS = Tmp buffer segment
		pop ecx								; Restore bytes read
		add eax, ecx						; Update destination pointer
		cmp bp, 0xFFFF						; Did we load it all?
		jne .LoadFile						; If not, load more
		pop fs								; Fix FS
		popad								; Restore registers
		ret									; If so, return
	; EAX = Address, EBX = Bytes to copy, EDX = Offset remaining
	; ECX = Bytes per sector * 2
	.FinishCopy:
		cmp ebx, 0							; Do we have to copy 0 bytes?
		je .Done							; If so, we're done here
		mov edi, ebx						; Move length to EDI
		add edi, edx						; Add the offset
		cmp edi, ecx						; Will we run off the buffer?
		jg .HandleOverflow					; If so, handle it
		mov ecx, ebx						; Set counter for rep movs
		mov esi, STAGE2_TEMP_BUF_LOW		; Reading from the tmp buf
		add esi, edx						; Adjust for offset
		mov edi, eax						; Set destination address
		rep movs byte [es:edi], [fs:esi]	; Copy ECX bytes
	.Done:
		pop fs								; Restore FS
		popad								; Pop registers
		clc									; Success, clear CF
		ret									; Return to caller
		
	; If the amount of bytes we have to copy isn't a multiple of the
	; sector size times two, it will eventually land between zero and
	; the sector size times two. Usually, the offset is handled when
	; the first two sectors are loaded, but in the rare case that
	; we have an offset, and a length under bytes per sector * 2 to
	; begin with, and the length plus the offset is above what was
	; loaded, i.e. BPS * 2, .FinishCopy will run off the buffer. This
	; subroutine handles this case.
	
	; EAX = Address, EBX = Bytes to copy, EDX = Offset remaining
	; ECX = Bytes per sector * 2
	.HandleOverflow:
		cmp bp, 0xFFFF						; Have we hit EOF?
		je .BadArgument						; Arguments are fucked
		
		cmp edx, ecx						; Is the offset > 2 sectors?
		jge .SkipSectors					; If so, load two more
		
		; We know the amount we need to copy and the offset are
		; both under BPS * 2 now, the latter due to the check we
		; just did, the former because we can only be called from
		; .FinishCopy, which itself can only be called if the
		; length is less than BPS * 2. So, both must be under
		; BPS * 2, however, both added together might still exceed
		; BPS * 2. To handle this, we will load two more sectors 
		; if it becomes necessary.
		
		mov edi, edx						; EDI = offset remaining
		add edi, ebx						; Add the length left
		cmp edi, ecx						; Is it under BPS * 2?
		jng .FinishCopy						; If so, we're done
		
		; Subtracting the offset from BPS * 2 ensures that we
		; complete the offset without running over the buffer.
		; Then, we subtract the bytes we copied from the length,
		; load two more sectors, fix the registers, and send the
		; rest off, if there is any, to .FinishCopy
		
		sub ecx, edx						; Otherwise, load this chunk
		push ecx							; Save number of bytes
		mov esi, STAGE2_TEMP_BUF_LOW		; Reading from temp buf
		add esi, edx						; Adjust for offset
		xor edx, edx						; We're done with offsets
		mov edi, eax						; Set destination address
		rep movs byte [es:edi], [fs:esi]	; Copy ECX bytes
		pop ecx								; Restore bytes copied
		add eax, ecx						; Advance pointer
		sub ebx, ecx						; Update length
		
		; Load two fresh sectors to finish the rest
		mov bp, 2							; Load two sectors
		mov di, STAGE2_TEMP_BUF_LOW			; Move offset into DI
		call word [LoadFile]				; Load to temp buffer
		jc .SubSysErrorLoadingFile			; Signal error on failure
		
		; .FinishCopy expects ECX to be BPS * 2
		movzx ecx, word [BytesPerSector]	; Get bytes per sector
		movzx edi, word [BytesPerSector]	; Must be the same size
		add ecx, edi						; Two sectors
		
		; No offset, and length is < BPS * 2, time to make it SOP
		jmp .FinishCopy
		
	.SkipSectors:
		mov bp, 2							; Load two sectors
		mov di, STAGE2_TEMP_BUF_LOW			; Move offset into DI
		call word [LoadFile]				; Load to temp buffer
		jc .SubSysErrorLoadingFile			; Die on failure
		
		sub edx, ecx						; Subtract BPS * 2
		jmp .HandleOverflow					; Possibly more overflow
	
	.BadArgument:
		pop fs								; Fix FS
		popad								; Restore registers
		mov al, 1							; Set error code
		stc									; Set CF to signal error
		ret									; Return to caller
	.FileNotFound:
		pop fs								; Fix FS
		popad								; Restore registers
		mov al, 2							; Set error code
		stc									; Set CF to signal error
		ret									; Return to caller
	.SubSysErrorLoadingFile:
		pop fs								; Fix FS
		popad								; Restore registers
		mov al, 3							; Set error code
		stc									; Set CF to signal error
		ret									; Return to caller
	