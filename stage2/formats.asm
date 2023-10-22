;************************************************************************
; TODOs:																*
;	TODO #1: Sanity check the HeaderAddress value. Although it should	*
;		be zero if invalid, people do stupid things. If loading from 	*
;		the Clara structure, use BaseAddress and EndAddress to make	 	*
;		sure it's in the first 8KB. If using the format headers, use 	*
;		the format's file size and base address values to check it. 	*
;		Note that, as usual, the format's headers should be preferred 	*
;		when performing the sanity check; the Clara structure values  	*
;		should only be used for this check if the file is being loaded	*
;		from them. If the flags designate the kernel wishes the loader	*
;		to prefer the Clara structure, then use it unless it's corrupt.	*
;		If the HeaderAddress value isn't needed, such as when loading	*
;		from the format headers and the Modules list pointer is NULL,	*
;		sanity checking it is optional.									*
; 	TODO #3: In error code 3.1, make suberrors to differentiate			*
;		between issues. This will directly help with #5.				*
;	TODO #4: In error code 3.1, differentiate between bits 1 and 17.	*
;		If only bit 17 is set, the error may be recoverable; if bit 1	*
;		is set, the error is almost certainly fatal.					*
;	TODO #5: Support unpacking the PE format, necessary for loading		*
;		files with alignments other than 512 and such.					*
; 	TODO #6: Support command line arguments								*
;	TODO #7: Support the ELF file format. Although it may be used with	*
;		this loader using a Clara structure, add native support for it.	*
;	TODO #8: Create and implement errors for LoadModules				*
;	TODO #9: In LoadModules(), check for errors in function calls		*
;************************************************************************ 

;****************************************************
;* 	FixPointer()									*
;* 		- Translates a pointer						*
;*		- Input										*
;*			- EAX	= Pointer to fix				*
;8			- ECX	= Base of file buffer			*
;*			- ESI	= File information structure	*
;*			- No errors								*
;*		- Output									*
;*			- EAX	= Fixed pointer					*
;*		- EDX clobbered								*
;**************************************************** 
FixPointer:
	push eax								; Save EAX
	push ecx								; Save ECX
		
	mov eax, [esi+28]						; Clara struct offset (real)
	mov ecx, [esi+32]						; Low dword of HeaderAddress
	sub ecx, dword [esi]					; Subtract base of kernel
	cmp eax, ecx							; Compare offsets
	je .SameSize							; If equal, jump
	jng .HeaderAddressLarger				; Otherwise, which is larger?
	
	.RealAddressLarger:
		sub eax, ecx						; EAX = Offset to add
		mov ecx, [esp+4]					; ECX = Address to fix
		sub ecx, dword [esi+4]				; Subtract kernel base addr
		add ecx, eax						; Add offset
		add ecx, dword [esp]				; Add base of headers
		mov eax, ecx						; Store in EAX
		jmp .CalculateDone					; Done, jump
	.HeaderAddressLarger:
		sub ecx, eax						; ECX = Offset to subtract
		mov eax, [esp+4]					; EAX = Address to fix
		sub eax, dword [esi+4]				; Subtract kernel base addr
		sub eax, ecx						; Subtract offset
		add eax, ebx						; Add base of headers
		mov edx, eax						; Store in EDX
		jmp .CalculateDone					; Done, jump
	.SameSize:
		mov ecx, [esp+4]					; ECX = Address to fix
		sub ecx, dword [esi]				; Subtract kernel base addr
		add ecx, [esp]						; Add base of headers
		mov [esp+4], ecx					; Store fixed pointer
		
	.CalculateDone:
		pop ecx								; Restore ECX
		pop eax								; Restore EAX
		ret									; Return to caller

;****************************************************
;* 	LoadModules()									*
;* 		- Loads modules into memory					*
;*		- Input										*
;*			- EAX	= File information structure	*
;8			- ECX	= Base of file buffer			*
;*		- Output									*
;*			- Modules at their specified addresses	*
;*		- Module list format						*
;*			- Bytes 0-7  : Base address				*
;*			- Bytes 8-11 : Length of name (bytes)	*
;*			- Bytes 12-15: Filename					*
;*			- Bytes 16-23: Pointer to next entry	*
;*		- Error code in AL (valid if CF = 1)		*
;*			- 0: General error						*
;*				- ECX = Pointer to file name		*
;*			- 1: Name format unsupported			*
;*				- ECX = Pointer to file name		*
;*			- 2: Error calling LoadFileHigh()		*
;*				- AH = Sub code						*
;*					- Code from LoadFileHigh()		*
;*				- ECX = Pointer to file name		*
;*			- 3: Address above 4GB					*
;*		- All registers preserved					*
;*		- Loading to temp area not yet supported	*
;****************************************************

; Remember that the dwords are reversed
ModuleName		rb 12						; Name buffer under 1MB
 
LoadModules:
	pushad									; Save registers

	; Find out if it's a NULL pointer
	mov ebx, [eax+20]						; EBX = High dword of ptr
	or ebx, [eax+16]						; OR with the low dword
	cmp ebx, 0								; Is it a NULL pointer?
	je .Done								; If so, no modules, done
	
	; Set up registers for the loop
	mov esi, eax							; ESI = Information struct
	mov eax, [esi+16]						; EAX = Module list low dword
	
	.LoadLoop:
		call FixPointer						; Fix the pointer
		mov ebx, eax						; EBX = Fixed pointer
		push ebx							; Save it for later
		mov eax, dword [ebx+8]				; EAX = Filename length
		cmp eax, 11							; Is it 11?
		jne .NameFormatUnsupported			; If not, signal error
		
		mov eax, dword [ebx+4]				; Base address high dword
		cmp eax, 0							; Is it zero?
		jne .AddressTooHigh					; If not, load to temp area
		mov eax, dword [ebx+12]				; Get the filename pointer
		call FixPointer						; Fix the pointer
	
		; Copy the name under 1MB
		cld									; Clear direction flag
		push esi							; Save info struct pointer
		mov esi, eax						; Move filename ptr to ESI
		mov edi, ModuleName					; Reading into the buffer
		mov ecx, 11							; Reading 11 bytes
		rep movs byte [es:edi], [ds:esi]	; Copy the string
		
		mov eax, [ebx]						; Base addr low dword
		xor ebx, ebx						; Load to EOF
		xor edi, edi						; No offset within file
		mov si, ModuleName					; Load name into SI
		call LoadFileHigh					; Load the module
		jc .ErrorLoadingFile				; If it fails, signal error
		
		; Check if there are any more modules to load
		pop esi								; Pop info structure pointer
		pop ebx								; Pop the module structure
		cmp dword [ebx+20], 0				; Check low dword of pointer
		je .Done							; If it's NULL, we're done
		
		; ESI is already set
		mov eax, [ebx+20]					; EAX = Low dword of pointer
		jmp .LoadLoop						; Load the next module
		
	; Fix the stack and return success
	.Done:
		popad								; Restore registers
		ret									; Return to caller
	
	.NameFormatUnsupported:
		pop ecx								; ECX = Module name pointer
		mov dword [ModuleName], ecx			; Save pointer
		popad								; Pop saved registers
		mov ecx, dword [ModuleName]			; Restore pointer
		mov al, 1							; Set error code
		stc									; Set CF to signal error
		ret									; Return to caller
	.ErrorLoadingFile:
		pop ecx								; Discard the top dword
		pop ecx								; ECX = Module name pointer
		mov byte [ModuleName], al			; Save sub error code
		mov dword [ModuleName+1], ecx		; Save module name pointer
		popad								; Restore saved registers
		mov ah, byte [ModuleName]			; Set sub error code
		mov ecx, dword [ModuleName+1]		; Restore module name pointer
		mov al, 2							; Set error code
		stc									; Set CF to signal error
		ret									; Return to caller
	.AddressTooHigh:
		pop ecx								; ECX = Module name pointer
		mov dword [ModuleName], ecx			; Save pointer
		popad								; Pop saved registers
		mov ecx, dword [ModuleName]			; Restore pointer
		mov al, 3							; Set error code
		stc									; Set CF to signal error
		ret									; Return to caller
	

;****************************************************
;* 	ParseFileHeaders()								*
;* 		- Parses file headers						*
;*		- Input 									*
;*			- EAX 	= Pointer to memory map buffer	*
;*			- ECX	= Size of memory map buffer		*
;*			- ESI 	= Pointer to file headers		*
;*			- EDI 	= Pointer to kernel info buffer	*
;*		- Output									*
;*			- EAX 	= File information structure	*
;*			- DF  	= Long Mode flag				*
;*			- CF set on error						*
;*			- Error code in AL (valid if CF = 1)	*
;*				- 0: Unknown/General error			*
;*				- 1: Unsupported format				*
;*					- ECX = First dword	of image	*
;*				- 2: Machine mismatch				*
;*					- AH = Sub code					*
;*						- 0: General error			*
;*						- 1: x64 image on x86		*
;*						- 2: x86 image on x64		*
;*						- 3: System x64 incapable	*
;*				- 3: Invalid format					*
;*					- AH = Sub code					*
;*						- 0: General error			*
;*						- 1: Clara struct error		*
;*							- CL = Sub sub code		*
;*								- 0: General error	*
;*								- 1: Bad checksum	*
;*								- 2: Reserved val	*
;*								- 3: Bit 1/16 err	*
;*								- 4: Flag/machine	*
;*								- 5: Offset 16 req	*
;*								- 6: Offset 16 inv	*
;*						- 2: Invalid file headers	*
;*							- CL = Sub sub code		*
;*								- 0: General error	*
;*								- 1: Invalid PE		*
;*								- 2: Invalid ELF	*
;*				- 4: Subsystem error				*
;*					- AH = Sub code					*
;*						- 0: General error			*
;*						- 1: Error fetching low mem	*
;*						- 2: Error fetching mem		*
;*						- 3: Error fetching mem map	*
;*							- CL = Code from call	*
;*		- Requirements								*
;*			- 32 or 64 bit x86 that supports CPUID	*
;*			- All segment limits at 4GB (except CS)	*
;*			- 8KB of, or entire, file is loaded		*
;*			- Structure buffer 48 bytes or more		*
;* 		- Preserves EBX, EDX, and EBP				*
;**************************************************** 

; Remember, dwords are reversed
; Return a structure (0x30 bytes)
FileInfo rb 44

ParseFileHeaders:

	; Save registers that must be preserved and make a stack frame
	push ebp								; Save old EBP
	mov ebp, esp							; Set EBP to base of stack
	push ebx								; Save EBX
	push edx								; Save EDX
	
	; Save info passed to us
	push eax								; Save memory map buffer
	push ecx								; Save buffer size
	push edi								; Save kernel info buffer
	
	; Clear structure (EDI = structure buffer)
	xor eax, eax							; Store zeros
	mov ecx, 0x0C							; 0x0C * 0x04 = 0x30
	rep stos dword [es:edi]					; Store dwords
	
	push esi								; Save file buffer
	mov ecx, 256							; 256 32B chunks = 8KB
	
	.FindSig:
		cmp dword [esi], 'SWAP'				; 'PAWS'
		je .ParseClaraStruct				; If found, check it
		add esi, 32							; Else, skip to next chunk
		loop .FindSig						; Loop while inside 8KB
	
	pop esi									; Restore file buffer
	pop ecx									; Save kernel info buffer
	add esp, 8								; Pop memory map info
	push ecx								; Push kernel info buffer
	xor ebx, ebx							; No Clara struct, clear it
	mov edx, 0xFFFFFFFF						; We don't know the mode yet
	jmp .ParseFileFormatHeaders				; No structure, try headers
	
	; State: ESI = Clara struct address; Stack: EBP, EBX, EDX, memory 
	; map buffer, mem map buffer size, kernel info buffer, file buffer
	
	;****************************************
	; Clara structure parsing code			*
	;**************************************** 
	
	.ParseClaraStruct:
		mov eax, dword [esi]				; EAX = Signature
		add eax, dword [esi+4]				; Add the OptionFlags value
		add eax, dword [esi+8]				; Add the TargetMachine value
		add eax, dword [esi+12]				; Add the Checksum value
		cmp eax, 0							; Is it zero?
		jne .ClaraBadChecksum				; If not, it's corrupt
		
	; Check TargetMachine value
	.CheckTargetMachine:
		cmp word [esi+10], 0x01				; Check high word for x86
		jne .CheckForUnspecifiedMachine		; Check if it's not specified
		jmp .CheckLoadInformation			; Otherwise, skip this
	
	; Handle the case of an unspecified arch/family
	.CheckForUnspecifiedMachine:
		cmp word [esi+10], 0				; Is the family unspecified?
		jne .WrongArch						; If not, wrong arch
		
		; If we get here, the family is unspecified
		cmp word [esi+8], 0					; Check low word
		jne .ClaraReservedValueSet			; Only zero is allowed
		
	; Check if bit 1 is set with bit 16 clear	
	.CheckLoadInformation:
		bt dword [esi+4], 1					; Must we use struct values?
		jnc .CheckModeRequirement			; If not, skip this check
		bt dword [esi+4], 16				; If so, bit 16 is required
		jnc .ClaraBit16RequiredWithBit1		; If not set, handle it
		clc									; Otherwise, fall through
	
	; Check if kernel needs long mode or not
	.CheckModeRequirement:
		bt dword [esi+4], 3					; Long mode bit?
		jnc .CheckModuleInformation			; If not, skip this part
		
	; Check if the TargetMachine is 64 bit compatible
	; Note that if the high word is zero, the low word must be
	; zero, or this wouldn't be executing. Therefore, we can
	; effectively ignore the high word, because it will be zero
	; if the arch is unspecified, or only the subtype is. If either
	; is true, we skip this check.
	.CheckTargetMachineConsistency:
		cmp word [esi+8], 0x00				; Is the subtype 'Any'?
		je .CheckSystemLongModeSupport		; If so, skip this check
		cmp word [esi+8], 0x02				; Is the subtype 'x64'?
		jne .ClaraFlagsAndMachineConflict	; If not, something's wrong
	
	; Check if the processor is capable of long mode
	.CheckSystemLongModeSupport:
		mov eax, 0x80000000					; Highest extended function
		cpuid								; Call CPUID
		cmp eax, 0x80000001					; Extended flags support?
		jb .x64Unsupported					; Long mode not supported
	
		mov eax, 0x80000001					; Get extended feature flags
		cpuid								; Call CPUID
		bt edx, 29							; Query long mode support
		jnc .x64Unsupported					; If unsupported, error
		
		mov edx, 1							; Set long mode flag							
		clc									; Reset CF and fall through
	
	; Handle module information, if any
	.CheckModuleInformation:
		mov edi, FileInfo					; EDI = Kernel info buffer
		bt dword [esi+4], 2					; Is there module info?
		jnc .SetClaraStructOffset			; If not, skip this part
		mov ebx, dword [esi+44]				; Otherwise, get low dword
		mov dword [edi+16], ebx				; Store in output structure
		mov ebx, dword [esi+48]				; Get high dword
		mov dword [edi+20], ebx				; Store in output structure
		mov ebx, dword [esi+16]				; HeaderAddress low dword
		mov dword [edi+32], ebx				; Store in output structure
		mov ebx, dword [esi+20]				; HeaderAddress high dword
		mov dword [edi+36], ebx				; Store in output structure
		or ebx, dword [edi+32]				; OR high dword with low
		cmp ebx, 0							; Are any bits set?
		je .ClaraHeaderAddressRequired		; If not, error, handle it
		clc									; Clear CF and continue
		
	.SetClaraStructOffset:
		mov ebx, esi						; EBX = Clara structure addr
		sub ebx, dword [esp]				; Make it an offset
		mov dword [edi+28], ebx				; Store in output structure
		mov ebx, esi						; Store struct addr in EBX
	
	; Current state: EBX and EDX must be preserved. 
	; Create the information structure for the kernel
	; Stack: EBP, EBX, EDX, memory map buffer, mem map buffer size, 
	; kernel info buffer, file buffer
	.CreateInformationStructure:
		mov edi, [esp+4]					; EDI = Kernel info struct
		
		; Get amount of low memory in KB and store
		mov dword [edi], 'SWAP'				; Set signature 'PAWS'
		call GetMemoryLow					; Get low memory size
		jc .ErrorGettingLowMemorySize		; Handle any errors
		mov word [edi+4], ax				; Store low memory size
		
		; Get amount of memory in KB and store
		call GetMemorySize					; Get memory size
		jc .ErrorGettingMemorySize			; Handle any errors
		mov dword [edi+6], eax				; Store total memory size
		
		; Get boot device and store
		xor eax, eax						; Clear EAX
		mov al, [BootDrive]					; Move boot drive into AL
		mov word [edi+14], ax				; Set boot device
		
		; Get memory map and store pointer and entry count
		push edi							; Save kernel info addr
		push es								; Save ES value
		push word [ebp-12]					; Push mem map buffer segment
		pop es								; Pop into ES
		mov di, word [ebp-10]				; DI = mem map buffer offset
		mov eax, dword [ebp-16]				; EAX = mem map buffer size
		call GetMemoryMap					; Call routine
		pop es								; Restore ES
		pop edi								; Restore structure address
		jc .ErrorGettingMemoryMap			; Handle any errors
		
		mov dword [edi+16], ecx				; Set number of entries
		mov dword [edi+24], 0				; Clear high dword
		
		; Turn segment:offset into a linear address
		push edx							; EDX must be preserved
		xor edx, edx						; Clear for multiply
		xor eax, eax						; Clear for multiply
		mov ax, word [ebp-12]				; Get segment
		mov cx, 0x10						; Segment * 16
		mul cx								; Result in DX:AX
		shl edx, 16							; Shift up 16 bits
		or edx, eax							; OR in the low 16 bits
		add edx, dword [ebp-10]				; Add offset
		
		mov dword [edi+20], edx				; Store address in structure
		pop edx								; Restore EDX
		
		; TODO: Add command line support
		mov dword [edi+28], 0				; Set low dword
		mov dword [edi+32], 0				; Set high dword
	
	;****************************************
	; Code to decide method of loading file	*
	;**************************************** 
	
	; Current state: EBX = Clara structure pointer (or zero); 
	; EDX = Long mode flag; Stack: EBP, EBX, EDX, mem map buffer,
	; mem map buffer size, kernel info buffer, file buffer

	.DecideLoadingMethod:
		pop esi								; Pop file buffer address
		add esp, 12							; Clean out old info
		cmp ebx, 0							; Is there no structure?
		je .ParseFileFormatHeaders			; If so, try using headers
		bt dword [ebx+4], 1					; Must we use struct values?
		jc .LoadFromClaraStructValues		; If set, yes
		bt dword [ebx+4], 17				; Prefer struct values?
		jc .LoadFromClaraStructValues		; If set, yes

	;****************************************
	; File format discovery/parsing code	*
	;****************************************
	
	; Current state: EBX = Pointer to Clara structure (or zero);
	; EDX = Long mode flag; ESI = Pointer to file buffer;
	; Stack: EBP, EBX, EDX
	
	; TODO #4
	; TODO #7
	; TODO #9
	; Find out why this doesn't work
	; Discover file format, and invoke the correct loading routine
	.ParseFileFormatHeaders:
		xchg bx, bx
		cmp word [esi], 'MZ'				; Check for MZ header
		je .ParseMZFormat					; If so, go parse it
		jmp .UnsupportedFormat				; Check for ELF here
	
	; Parse the MZ format. Only used to reach PE, raw MZ is not supported
	.ParseMZFormat:
		mov eax, dword [esi+60]				; EAX = RVA of NT headers
		add eax, esi						; Convert RVA to linear addr
		mov ecx, dword [eax]				; Move sig to ECX
		cmp ecx, 0x00004550					; Is the PE sig valid?			
		jne .UnsupportedFormat				; If not, handle error
	
	
	; Type							32 bit		64 bit
	; Optional Header Signature		0x010B		0x020B
	; Offset to ImageBase: 			28 bytes	24 bytes
	; Size of ImageBase:			4 bytes		8 bytes
	; Note: The TargetMachine value was checked when the Clara
	; struct was originally parsed. If the high word isn't 0x01, the
	; value must be 0x0000, or we wouldn't have gotten here. The low
	; word was checked as well, for a 32/64 bit mismatch.
	
	; Current state: EAX = NT header address; EBX = Pointer to Clara
	; structure; EDX = 64 bit flag; ESI = Pointer to file buffer;
	; Stack: EBP, EBX, EDX
	; Note that EAX is BEHIND the PE sig
	; Parse the PE file format
	.ParsePEFormat:
		mov edi, FileInfo					; Restore file info struct
		add eax, 24							; Skip to optional header

		mov ecx, dword [eax+16]				; Get entry point RVA
		mov dword [edi+24], ecx				; Store in output structure
		cmp word [eax], 0x10B				; Is the sig 0x10b?
		je .PE32							; If so, 32 bit PE
		cmp word [eax], 0x20B				; Is it 64 bit?
		jne .InvalidPE						; If not, invalid
		cmp edx, 0xFFFFFFFF					; Is the mode unknown?
		je .UnknownMode64					; If so, skip the next check
		cmp edx, 0							; Is the long mode flag set?
		je .x64onx86						; If not, throw an error
	.UnknownMode64:
		std									; Set 64 bit flag
		mov ecx, dword [eax+24]				; BaseAddress low dword
		mov dword [edi], ecx				; Move into struct
		mov ecx, dword [eax+28]				; BaseAddress high dword
		mov dword [edi+4], ecx				; Move into struct
		jmp .FinishPE						; Done here, let's finish up
	
	; Note: High dword is undefined for 32 bit kernels
	.PE32:
		cmp edx, 0xFFFFFFFF					; Is the mode unknown?
		je .UnknownMode32					; If so, skip the next check
		cmp edx, 0							; Is the long mode flag set?
		jne .x86onx64						; If so, throw an error
	.UnknownMode32:
		cld									; Clear 64 bit flag
		mov ecx, dword [eax+28]				; Get low dword
		mov dword [edi], ecx				; Move into variable, done
	
	; Note that PE doesn't support an end address or load offset
	; Finishes up parsing PE and returns
	.FinishPE:
		mov dword [edi+40], 0				; No load offset
		mov dword [edi+8], 0				; No end address (high dword)
		mov dword [edi+12], 0				; No end address (low dword)
		mov eax, edi						; Set structure pointer
		pop edx								; Restore EDX
		pop ebx								; Restore EBX
		pop ebp								; Restore EBP
		ret									; Return to caller
	
	; Incomplete
	; Untested, I hate this method of loading
	; Current state: EBX = Clara structure pointer (or zero); 
	; EDX = Long mode flag; Stack: EBX, EDX, mem map buffer, mem map
	; buffer size, kernel info buffer, file buffer
	.LoadFromClaraStructValues:
		push edx							; Save long mode flag
		push ebp							; Save module list pointer
		mov eax, [edi+24]					; EAX = Base address
		mov ebx, dword [esp+8]				; EBX = Base of file buffer
		mov ecx, [edi+36]					; ECX = Entry point addr
		mov esi, edi						; ESI = Current struct addr
		sub esi, ebx						; ESI = Real struct offset
		call FixPointer						; Fix entry point
		
		sub edx, ebx						; EDX = Entry point offset
		pop ecx								; ECX = Module list pointer
		
		cmp dword [edi+24], 0				; Is BytesToLoad zero?
		je .NoEndAddr						; If so, just zero EBX
		mov ebx, eax						; EBX = Base address
		add ebx, dword [edi+24]				; Add bytes to load
		je .EndAddrDone						; Done
	.NoEndAddr:
		xor ebx, ebx						; Load until EOF
	
	.EndAddrDone:
		mov ebp, dword [edi+16]				; EBP = HeaderAddress value
		sub ebp, eax						; Sanity check HeaderAddress
		cmp ebp, 0x2000						; Is it larger than 8KB?
		jg .ClaraHeaderAddressInvalid		; If so, invalid
		xor edi, edi						; Struct doesn't support this
		
		bt dword [esp], 3					; Check long mode flag
		jc .FlagSet							; If it is, go set DF
		cld									; Otherwise, clear DF
		jmp .FlagDone
	.FlagSet:
		std									; Set DF, long mode needed		
	.FlagDone:
		clc									; Reset CF
		ret 4								; Fix the stack and return
	
	;************************************
	; Error Codes						*
	;************************************
	
	; Error code 0: Unknown error or general error (unimplemented)
	
	; Error code 1: Unsupported format
	; ESI = file base address
	.UnsupportedFormat:
		mov al, 1							; Set error code
		mov ecx, dword [esi]				; ECX = First dword of file
		pop edx								; Restore EDX
		pop ebx								; Restore EBX
		pop ebp								; Restore EBP
		stc									; Set CF
		ret									; Return to caller
		
	; Error code 2: Machine mismatch
	.WrongArch:
		mov al, 2							; Set error code
		xor ah, ah							; Set sub error code
		add esp, 12							; Fix stack
		pop edx								; Restore EDX
		pop ebx								; Restore EBX
		pop ebp								; Restore EBP
		stc									; Set CF
		ret									; Return to caller
	
	; Error code 2.1: 64 bit binary to run in 32 bit mode
	.x64onx86:
		mov al, 2							; Set error code
		mov ah, 1							; Set sub error code
		pop edx								; Restore EDX
		pop ebx								; Restore EBX
		pop ebp								; Restore EBP
		stc									; Set CF
		ret									; Return to caller
	
	; Error code 2.2: 32 bit binary to run in 64 bit mode
	.x86onx64:
		mov al, 2							; Set error code
		mov ah, 2							; Set sub error code
		pop edx								; Restore EDX
		pop ebx								; Restore EBX
		pop ebp								; Restore EBP
		stc									; Set CF
		ret									; Return to caller
	
	; Error code 2.3: 64 bit specified, but machine is incapable
	.x64Unsupported:
		mov al, 2							; Set error code
		mov ah, 3							; Set sub error code
		add esp, 16							; Fix stack
		pop edx								; Restore EDX
		pop ebx								; Restore EBX
		pop ebp								; Restore EBP
		stc									; Set CF
		ret									; Return to caller
	
	; Error code 3: Invalid information structure (unimplemented)
	
	; Error code 3.1: Invalid Clara structure (unimplemented)
	
	; Error code 3.1.1: Clara structure contains bad checksum
	.ClaraBadChecksum:
		mov al, 3							; Set error code
		mov ah, 1							; Set sub error code 
		mov cl, 1							; Set sub sub error code
		add esp, 16							; Fix stack
		pop edx								; Restore EDX
		pop ebx								; Restore EBX
		pop ebp								; Restore EBP
		stc									; Set CF
		ret									; Return to caller
	
	; Error code 3.1.2: Reserved value set in Clara structure
	.ClaraReservedValueSet:
		mov al, 3							; Set error code
		mov ah, 1							; Set sub error code
		mov cl, 2							; Set sub sub error code
		add esp, 16							; Fix stack
		pop edx								; Restore EDX
		pop ebx								; Restore EBX
		pop ebp								; Restore EBP
		stc									; Set CF
		ret									; Return to caller
	
	; Error code 3.1.3: Bit 1 requires bit 16 to be set
	.ClaraBit16RequiredWithBit1:
		mov al, 3							; Set error coder
		mov ah, 1							; Set sub error code
		mov cl, 3							; Set sub sub error code
		add esp, 16							; Fix stack
		pop edx								; Restore EDX
		pop ebx								; Restore EBX
		pop ebp								; Restore EBP
		stc									; Set CF
		ret									; Return to caller
	
	; Error code 3.1.4: OptionFlags and TargetMachine conflict
	.ClaraFlagsAndMachineConflict:
		mov al, 3							; Set error code
		mov ah, 1							; Set sub error code
		mov cl, 4							; Set sub sub error code
		add esp, 16							; Fix stack
		pop edx								; Restore EDX
		pop ebx								; Restore EBX
		pop ebp								; Restore EBP
		stc									; Set CF
		ret									; Return to caller
	
	; Error code 3.1.5: HeaderAddress value required but not supplied
	.ClaraHeaderAddressRequired:
		mov al, 3							; Set error code
		mov ah, 1							; Set sub error code
		mov cl, 5							; Set sub sub error code
		add esp, 16							; Fix stack
		pop edx								; Restore EDX
		pop ebx								; Restore EBX
		pop ebp								; Restore EBP
		stc									; Set CF
		ret									; Return to caller
	
	; Error code 3.1.6: HeaderAddress value invalid
	.ClaraHeaderAddressInvalid:
		mov al, 3							; Set error code
		mov ah, 1							; Set sub error code
		mov cl, 6							; Set sub sub error code
		stc									; Set CF
		ret									; Return to caller
		
	; Error code 3.2: Invalid file format header (unimplemented)
	
	; Error code 3.2.1: Invalid PE header
	.InvalidPE:
		mov al, 3							; Set error code
		mov ah, 2							; Set sub error code
		mov cl, 1							; Set sub sub error code
		pop edx								; Restore EDX
		pop ebx								; Restore EBX
		pop ebp								; Restore EBP
		stc									; Set CF
		ret									; Return to caller
	
	; Error code 3.2.2: Invalid ELF header (unimplemented)
	
	; Error code 4: Subsystem Error (unimplemented)
	
	; Error code 4.1: Error getting size of conventional memory
	.ErrorGettingLowMemorySize:
		mov al, 4							; Set error code
		mov ah, 1							; Set sub error code
		add esp, 16							; Fix stack
		pop edx								; Restore EDX
		pop ebx								; Restore EBX
		pop ebp								; Restore EBP
		stc									; Set CF
		ret									; Return to caller
	
	; Error 4.2: Error getting total amount of memory
	.ErrorGettingMemorySize:
		mov al, 4							; Set error code
		mov ah, 2							; Set sub error code
		add esp, 16							; Fix stack
		pop edx								; Restore EDX
		pop ebx								; Restore EBX
		pop ebp								; Restore EBP
		stc									; Set CF
		ret									; Return to caller
	
	; Error 4.3: Error getting memory map from BIOS
	.ErrorGettingMemoryMap:
		mov cl, al							; Set sub sub error code
		mov al, 4							; Set error code
		mov ah, 3							; Set sub error code
		add esp, 16							; Fix stack
		pop edx								; Restore EDX
		pop ebx								; Restore EBX
		pop ebp								; Restore EBP
		stc									; Set CF
		ret									; Return to caller