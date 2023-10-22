;****************************************************
; Error messages									*
;****************************************************

MsgGenErr							db "A fatal error has occurred.", 10, 13, 0
MsgCPUErr							db "System requires an Intel 586 equivalent or greater.", 10, 13, 0
MsgMemErr							db "Error retrieving size of memory via BIOS interrupt 0x15 function 0xE801.", 10, 13, 0
;MsgLowMemErr						db "System requires 16MB or more of RAM.", 10, 13, 0
MsgA20Err							db "Unable to enable the A20 line.", 10, 13, 0
MsgPFHGenErr						db "Error while parsing kernel headers.", 10, 13, 0
MsgPFHUnknownFormatErr				db "Kernel binary in unknown format. Supported formats are... PE. Just PE right now.", 10, 13, 0
MsgPFHMachineGenErr					db "Kernel machine value incorrect or corrupt.", 10, 13, 0
MsgPFHMachinex64onx86				db "Kernel file format headers specify 64 bit, but the structure specifies 32 bit.", 10, 13, 0
MsgPFHMachinex86onx64				db "Kernel file format headers specify 32 bit, but the structure specifies 64 bit.", 10, 13, 0
MsgPFHMachinex64Unsup				db "Kernel requires 64 bit, but the system does not support it.", 10, 13, 0
MsgPFHFormatGenErr					db "Error parsing file headers.", 10, 13, 0
MsgPFHFormatClaraGenErr				db "Error parsing Clara structure.", 10, 13, 0
MsgPFHFormatClaraCsumErr			db "Clara structure checksum is invalid.", 10, 13, 0
MsgPFHFormatClaraRsvdErr			db "Reserved value set in Clara structure.", 10, 13, 0
MsgPFHFormatClaraBit1v16Err			db "Bit 1 set without bit 16 in OptionFlags.", 10, 13, 0
MsgPFHFormatClaraFlagsvMachErr		db "OptionFlags and TargetMachine values contradict. (such as setting a TargetMachine of x86, but setting the x64 flag in OptionFlags.)", 10, 13, 0
MsgPFHFormatClaraHdrAddrReqErr		db "HeaderAddress value required but not present.", 10, 13, 0
MsgPFHFormatClaraHdrAddrInvErr		db "HeaderAddress value is invalid.", 10, 13, 0
MsgPFHFileFormatHdrGenErr			db "Error parsing file format headers.", 10, 13, 0
MsgPFHFileFormatHdrPEErr			db "Error parsing PE file format header.", 10, 13, 0
MsgPFHFileFormatHdrELFErr			db "Error parsing ELF file format header.", 10, 13, 0
MsgPFHSubSysGenErr					db "Subsystem failed while parsing file headers.", 10, 13, 0
MsgPFHSubSysGetLowMemErr			db "Subsystem failure when getting amount of low memory using BIOS interrupt 0x12, function 0.", 10, 13, 0
MsgPFHSubSysGetAllMemErr			db "Subsystem failure when getting total amount of memory using BIOS interrupt 0xE801, with function 0xE881 as a fallback.", 10, 13, 0
MsgPFHSubSysGetMemMapGenErr			db "Subsystem failure when obtaining memory map using BIOS interrupt 0xE820.", 10, 13, 0
MsgPFHSubSysGetMemMapBIOSErr		db "Subsystem failure when obtaining memory map: BIOS interrupt 0xE820 failed.", 10, 13, 0
MsgPFHSubSysGetMemMapBufErr			db "Subsystem failure when obtaining memory map: Buffer is too small for memory map.", 10, 13, 0
MsgLMGenErr							db "Error loading modules.", 10, 13, 0
MsgLMNameErr						db "Error loading modules: File name is invalid.", 10, 13, 0
MsgLMAddrErr						db "Error loading modules: Address above 4GB.", 10, 13, 0
MsgLMSubSysLFHighGenErr				db "Error loading modules: Loading subsystem failed.", 10, 13, 0
MsgLMSubSysLFHighBadArgsErr			db "Error loading modules: Bad arguments to loading subsystem.", 10, 13, 0
MsgLMSubSysLFHighFileNotFoundErr	db "Error loading modules: File not found (does it exist?)", 10, 13, 0
MsgLFHdrsGenErr						db "Error loading kernel file headers.", 10, 13, 0
MsgLFHdrsFileNotFoundErr			db "Error loading kernel file headers: File not found (does it exist?)", 10, 13, 0
MsgLFHdrsSubSysLoadingErr			db "Error loading file: Disk subsystem failed.", 10, 13, 0
MsgLFHighGenErr						db "Error loading file.", 10, 13, 0
MsgLFHighBadArgsErr					db "Error loading file: Bad arguments passed to function.", 10, 13, 0
MsgLFHighFileNotFoundErr			db "Error loading file: File not found (does it exist?)", 10, 13, 0
MsgLFHighSubSysLoadingErr			db "Error loading file: Disk subsystem failed.", 10, 13, 0

;****************************************************
;* 	Errors()										*
;* 		- Main error dispatcher						*
;*		- Input										*
;*			- AL	= Any error codes				*
;*			- AH	= Any sub error codes			*
;*			- CL	= Any sub sub error codes		*
;*			- CH	= Any sub sub sub error codes	*
;*		- Output 									*
;*			- Prints appropriate error message		*
;*		- No errors									*
;*		- Requirements								*
;*			- BIOS interrupts are accessible		*
;*			- PrintLine() for C-style strings		*
;*		- Registers don't matter, does not return	*
;****************************************************

Errors:
	.OldCPU:
		mov si, MsgCPUErr
		call PrintLine
		cli
		hlt
	.GettingMemorySize:
		mov si, MsgMemErr
		call PrintLine
		cli
		hlt
	;.LowMemory:
		;mov si, MsgLowMemErr
		;call PrintLine
		cli
		hlt
	.A20:
		mov si, MsgA20Err
		call PrintLine
		cli
		hlt
	.ParseFileHeaders:
		jmp ParseFileHeadersInternalErrorDispatcher
	.LoadModules:
		jmp LoadModulesInternalErrorDispatcher
	.LoadFileHeaders:
		jmp LoadFileHeadersInternalErrorDispatcher
	.LoadFileHigh:
		jmp LoadFileHighInternalErrorDispatcher
	
	mov si, MsgGenErr
	call PrintLine
	cli
	hlt

;****************************************************
;* 	ParseFileHeadersInternalErrorDispatcher()		*
;* 		- Error dispatcher for ParseFileHeaders()	*
;*		- Input										*
;*			- AL	= Any error codes				*
;*			- AH	= Any sub error codes			*
;*			- CL	= Any sub sub error codes		*
;*			- CH	= Any sub sub sub error codes	*
;*		- Outputs									*
;*			- Prints appropriate error message		*
;*		- No errors									*
;*		- Requirements								*
;*			- BIOS interrupts are accessible		*
;*			- PrintLine() for C-style strings		*
;*		- Registers don't matter, does not return	*
;****************************************************

ParseFileHeadersInternalErrorDispatcher:
	cmp al, 0
	je .PFHGeneral
	cmp al, 1
	je .PFHUnknownFormat
	cmp al, 2
	je .PFHMachine
	cmp al, 3
	je .PFHFormat
	cmp al, 4
	je .PFHSubSys
	
		.PFHGeneral:
			mov si, MsgPFHGenErr
			call PrintLine
			cli
			hlt
	; TODO: Print ECX (the first dword of the image)
	.PFHUnknownFormat:
		mov si, MsgPFHUnknownFormatErr
		call PrintLine
		cli
		hlt
	.PFHMachine:
		cmp ah, 0
		je .PFHMachineGeneral
		cmp ah, 1
		je .PFHMachinex64onx86
		cmp ah, 2
		je .PFHMachinex86onx64
		cmp ah, 3
		je .PFHMachinex64Unsupported
		jmp .PFHMachineGeneral				; If unknown, show general
	.PFHMachineGeneral:
		mov si, MsgPFHMachineGenErr
		call PrintLine
		cli
		hlt
	.PFHMachinex64onx86:
		mov si, MsgPFHMachinex64onx86
		call PrintLine
		cli
		hlt
	.PFHMachinex86onx64:
		mov si, MsgPFHMachinex86onx64
		call PrintLine
		cli
		hlt
	.PFHMachinex64Unsupported:
		mov si, MsgPFHMachinex64Unsup
		call PrintLine
		cli
		hlt
	
	.PFHFormat:
		cmp ah, 0
		je .PFHFormatGenErr
		cmp ah, 1
		je .PFHFormatClaraErr
		cmp ah, 2
		je .PFHFileFormatHdrErr
		jmp .PFHFormatGenErr
		
	.PFHFormatGenErr:
		mov si, MsgPFHFormatGenErr
		call PrintLine
		cli
		hlt
	.PFHFormatClaraErr:
		cmp cl, 0
		je .PFHFormatClaraGenErr
		cmp cl, 1
		je .PFHFormatClaraCsumErr
		cmp cl, 2
		je .PFHFormatClaraRsvdErr
		cmp cl, 3
		je .PFHFormatClaraBit1v16Err
		cmp cl, 4
		je .PFHFormatClaraFlagsvMachErr
		cmp cl, 5
		je .PFHFormatClaraHdrAddrReqErr
		cmp cl, 6
		je .PFHFormatClaraHdrAddrInvErr
	
	.PFHFormatClaraGenErr:
		mov si, MsgPFHFormatClaraGenErr
		call PrintLine
		cli
		hlt
	.PFHFormatClaraCsumErr:
		mov si, MsgPFHFormatClaraCsumErr
		call PrintLine
		cli
		hlt
	.PFHFormatClaraRsvdErr:
		mov si, MsgPFHFormatClaraRsvdErr
		call PrintLine
		cli
		hlt
	.PFHFormatClaraBit1v16Err:
		mov si, MsgPFHFormatClaraBit1v16Err
		call PrintLine
		cli
		hlt
	.PFHFormatClaraFlagsvMachErr:
		mov si, MsgPFHFormatClaraFlagsvMachErr
		call PrintLine
		cli
		hlt
	.PFHFormatClaraHdrAddrReqErr:
		mov si, MsgPFHFormatClaraHdrAddrReqErr
		call PrintLine
		cli
		hlt
	.PFHFormatClaraHdrAddrInvErr:
		mov si, MsgPFHFormatClaraHdrAddrInvErr
		call PrintLine
		cli
		hlt
		
	.PFHFileFormatHdrErr:
		cmp cl, 0
		je .PFHFileFormatHdrGenErr
		cmp cl, 1
		je .PFHFileFormatHdrPEErr
		cmp cl, 2
		je .PFHFileFormatHdrELFErr
		jmp .PFHFileFormatHdrGenErr
	.PFHFileFormatHdrGenErr:
		mov si, MsgPFHFileFormatHdrGenErr
		call PrintLine
		cli
		hlt
	.PFHFileFormatHdrPEErr:
		mov si, MsgPFHFileFormatHdrPEErr
		call PrintLine
		cli
		hlt
	.PFHFileFormatHdrELFErr:
		mov si, MsgPFHFileFormatHdrELFErr
		call PrintLine
		cli
		hlt
	.PFHSubSys:
		cmp ah, 0
		je .PFHSubSysGenErr
		cmp ah, 1
		je .PFHGetLowMemErr
		cmp ah, 2
		je .PFHGetAllMemErr
		cmp ah, 3
		je .PFHGetMemMapErr
	
	.PFHSubSysGenErr:
		mov si, MsgPFHSubSysGenErr
		call PrintLine
		cli
		hlt
	.PFHGetLowMemErr:
		mov si, MsgPFHSubSysGetLowMemErr
		call PrintLine
		cli
		hlt
	.PFHGetAllMemErr:
		mov si, MsgPFHSubSysGetAllMemErr
		call PrintLine
		cli
		hlt
	.PFHGetMemMapErr:
		cmp cl, 0
		je .PFHSubSysGetMemMapGenErr
		cmp cl, 1
		je .PFHSubSysGetMemMapBIOSErr
		cmp cl, 2
		je .PFHSubSysGetMemMapBufErr
		jmp .PFHSubSysGetMemMapGenErr
		
	.PFHSubSysGetMemMapGenErr:
		mov si, MsgPFHSubSysGetMemMapGenErr
		call PrintLine
		cli
		hlt
	.PFHSubSysGetMemMapBIOSErr:
		mov si, MsgPFHSubSysGetMemMapBIOSErr
		call PrintLine
		cli
		hlt
	.PFHSubSysGetMemMapBufErr:
		mov si, MsgPFHSubSysGetMemMapBufErr
		call PrintLine
		cli
		hlt

;****************************************************
;* 	LoadModulesInternalErrorDispatcher()			*
;* 		- Error dispatcher for LoadModules()		*
;*		- Input										*
;*			- AL	= Any error codes				*
;*			- AH	= Any sub error codes			*
;*			- CL	= Any sub sub error codes		*
;*			- CH	= Any sub sub sub error codes	*
;*		- Outputs									*
;*			- Prints appropriate error message		*
;*		- No errors									*
;*		- Requirements								*
;*			- BIOS interrupts are accessible		*
;*			- PrintLine() for C-style strings		*
;*		- Registers don't matter, does not return	*
;****************************************************

LoadModulesInternalErrorDispatcher:
	cmp al, 0
	je .LMGenErr
	cmp al, 1
	je .LMNameErr
	cmp al, 2
	je .LMSubSysLFHighErr
	cmp al, 3
	je .LMAddrErr
		
	.LMGenErr:
		mov si, MsgLMGenErr
		call PrintLine
		cli
		hlt
	.LMNameErr:
		mov si, MsgLMNameErr
		call PrintLine
		cli
		hlt
	.LMSubSysLFHighErr:
		cmp ah, 0
		je .LMSubSysLFHighGenErr
		cmp ah, 1
		je .LMSubSysLFHighBadArgsErr
		cmp ah, 2
		je .LMSubSysLFHighFileNotFoundErr
	.LMAddrErr:
		mov si, MsgLMAddrErr
		call PrintLine
		cli
		hlt
	.LMSubSysLFHighGenErr:
		mov si, MsgLMSubSysLFHighGenErr
		call PrintLine
		cli
		hlt
	.LMSubSysLFHighBadArgsErr:
		mov si, MsgLMSubSysLFHighBadArgsErr
		call PrintLine
		cli
		hlt
	.LMSubSysLFHighFileNotFoundErr:
		mov si, MsgLMSubSysLFHighFileNotFoundErr
		call PrintLine
		cli
		hlt	

;****************************************************
;* 	LoadFileHeadersInternalErrorDispatcher()		*
;* 		- Error dispatcher for LoadFileHeaders()	*
;*		- Input										*
;*			- AL	= Any error codes				*
;*			- AH	= Any sub error codes			*
;*			- CL	= Any sub sub error codes		*
;*			- CH	= Any sub sub sub error codes	*
;*		- Outputs									*
;*			- Prints appropriate error message		*
;*		- No errors									*
;*		- Requirements								*
;*			- BIOS interrupts are accessible		*
;*			- PrintLine() for C-style strings		*
;*		- Registers don't matter, does not return	*
;****************************************************

LoadFileHeadersInternalErrorDispatcher:
	cmp al, 0
	je .LFHdrsGenErr
	cmp al, 1
	je .LFHdrsFileNotFoundErr	
	cmp al, 2
	je .LFHdrsSubSysLoadingErr
	
	.LFHdrsGenErr:
		mov si, MsgLFHdrsGenErr
		call PrintLine
		cli
		hlt
	.LFHdrsFileNotFoundErr:
		mov si, MsgLFHdrsFileNotFoundErr
		call PrintLine
		cli
		hlt
	.LFHdrsSubSysLoadingErr:
		mov si, MsgLFHdrsSubSysLoadingErr
		call PrintLine
		cli
		hlt
		
;****************************************************
;* 	LoadFileHighInternalErrorDispatcher()			*
;* 		- Error dispatcher for LoadFileHigh()		*
;*		- Input										*
;*			- AL	= Any error codes				*
;*			- AH	= Any sub error codes			*
;*			- CL	= Any sub sub error codes		*
;*			- CH	= Any sub sub sub error codes	*
;*		- Outputs									*
;*			- Prints appropriate error message		*
;*		- No errors									*
;*		- Requirements								*
;*			- BIOS interrupts are accessible		*
;*			- PrintLine() for C-style strings		*
;*		- Registers don't matter, does not return	*
;****************************************************

LoadFileHighInternalErrorDispatcher:
	cmp al, 0
	je .LFHighGenErr
	cmp al, 1
	je .LFHighBadArgsErr
	cmp al, 2
	je .LFHighFileNotFoundErr
	cmp al, 3
	je .LFHighSubSysLoadingErr
		
	.LFHighGenErr:
		mov si, MsgLFHighGenErr
		call PrintLine
		cli
		hlt
	.LFHighBadArgsErr:
		mov si, MsgLFHighBadArgsErr
		call PrintLine
		cli
		hlt
	.LFHighFileNotFoundErr:
		mov si, MsgLFHighFileNotFoundErr
		call PrintLine
		cli
		hlt
	.LFHighSubSysLoadingErr:
		mov si, MsgLFHighSubSysLoadingErr
		call PrintLine
		cli
		hlt
		