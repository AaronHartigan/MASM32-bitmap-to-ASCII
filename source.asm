.586
.MODEL  FLAT
.STACK	4096

EXTERN  _ExitProcess@4:near
EXTERN  _GetStdHandle@4:near
EXTERN  _WriteConsoleA@20:near
EXTERN	_ReadFile@20:near
EXTERN  _CreateFileA@28:near
EXTERN	_WriteFile@20:near

.DATA
		hStdout		DWORD   ?		; handle to console
		hFile		DWORD	?
		hFileOut	DWORD	?
		read		DWORD	?		; stores how many bytes were read from file
		buffer		BYTE	100000 DUP (?)
		inFile		BYTE	"in.bmp", 0
		outFile		BYTE	"out.txt", 0
		bmHeader	BYTE	54 DUP (?)
		xPixels		DWORD	?
		yPixels		DWORD	?
		padBytes	DWORD	?
		fileSize	DWORD	?
		characters	BYTE	'#', 'M', 'N', 'F', 'V', '+', '*', '-', '|',  ':', '.', ' '
		numChars	DWORD	12
		greyVal		DWORD	?
		index		DWORD	?
		num			DWORD	?
		STD_OUTPUT_HANDLE	DWORD	-11
		BMP_HEADER_SIZE		DWORD	54
.STACK

.CODE
main	PROC 
		;##############################################################
		;#    Use CreateFile to get file handle for the output file   #
		;##############################################################
		; CreateFile(fileName, access, share, security, creation, flags, handle)
		pushd	0				; 7 param - handle (no template file)
		pushd	128				; 6 param - flag (NORMAL)
		pushd	2				; 5 param - creation (CREATE_ALWAYS)
		pushd	0				; 4 param - security (can not be used by child processes)
		pushd	0				; 3 param - share (cannot be shared)
		pushd	40000000h		; 2 param - access (GENERIC_WRITE)
		pushd	offset outFile	; 1 param - FileName
		call	_CreateFileA@28	; WINAPI automatically clears stack
		mov		hFileOut, eax

		;##########################################################
		;#    Get console output handle (so we can write to it)   #
		;##########################################################
        ; hStdout = GetStdHandle(STD_OUTPUT_HANDLE)
        pushd	STD_OUTPUT_HANDLE
        call	_GetStdHandle@4	; WINAPI automatically clears stack
        mov		hStdout, eax

		;#########################################################
		;#    Use CreateFile to get file handle for the file we  #
		;#    want to read (NOT to actually create a file)       #
		;#########################################################
		; CreateFile(fileName, access, share, security, creation, flags, handle)
		pushd	0				; 7 param - handle (ignored for reading files)
		pushd	1				; 6 param - flag (READONLY)
		pushd	3				; 5 param - creation (OPEN_EXISTING)
		pushd	0				; 4 param - security (can not be used by child processes)
		pushd	0				; 3 param - share (cannot be shared)
		pushd	80000000h		; 2 param - access (GENERIC_READ)
		pushd	offset inFile	; 1 param - FileName
		call	_CreateFileA@28	; WINAPI automatically clears stack
		mov		hFile, eax

		;##################################################################
		;#     Read the bitmap header to get information about the file   #
		;##################################################################
		; ReadFile(hFile, &buffer, fileLen, &read, 0)
        pushd	0				; 5 param - Overlap (ignored)
        pushd	offset read		; 4 param - Bytes read
        pushd	BMP_HEADER_SIZE	; 3 param - Maximum bytes to read
        pushd	offset bmHeader	; 2 param - buffer that recieves data read
        pushd	hFile			; 1 param - handle to file
        call	_ReadFile@20	; WINAPI automatically clears stack

		;##########################################################
		;#           Extract data from the bitmap header          #
		;##########################################################
		mov		edx, DWORD PTR bmHeader[18]
		mov		xPixels, edx					; store file width in xPixels

		mov		edx, DWORD PTR bmHeader[22]
		mov		yPixels, edx					; store file height in yPixels

		mov		edx, 0							; calculate xPixels % 4
		mov		eax, xPixels
		mov		ebx, 4
		div		ebx								; divide xPixels by 4
		mov		padBytes, edx					; store remainder in padBytes

		mov		edx, DWORD PTR bmHeader[2]		; file size stored at 2 byte offset
		sub		edx, 54							; subtract header size from file size
		mov		fileSize, edx					; store file size

		;##########################################################
		;#           Read the rest of the file contents           #
		;##########################################################
		; ReadFile(hFile, &buffer, fileLen, &read, 0)
        pushd	0				; 5 param - Overlap (ignored)
        pushd	offset read		; 4 param - Bytes read
        pushd	fileSize		; 3 param - Maximum bytes to read
        pushd	offset buffer	; 2 param - buffer that recieves data read
        pushd	hFile			; 1 param - handle to file
        call	_ReadFile@20	; WINAPI automatically clears stack

		;############################################################
		;#            Loop through file and output a character      #
		;#              representation of it to the console.        #
		;#                                                          #
		;#     Outer loop goes through rows from the bottom up      #
		;#          beacuse bitmap stores images upside down.       #
		;#                                                          #
		;#	            Inner loop goes through columns             #
		;#		   (each complete inner loop outputs a row).        #
		;############################################################
		mov		ecx, yPixels	; ecx is outer loop counter (row)
		dec		ecx
outerLoop1:						; for (row = yPixels - 1; row >= 0; row--)
		mov		edx, 0			; edx is inner loop counter (col)
innerLoop1:						; for (col = 0; col < xPixels; col++)
		;################################################################
		;#      Calculate the index of the bytes we want to look at     #
		;################################################################
		; index = (col + row * xPixels) * 3 + padBytes * row
		mov		greyVal, 0		; greyVal = 0
		mov		eax, ecx		; mov current Row to eax
		imul	eax, xPixels	; multiply row by xPixels
		add		eax, edx		; add current Col
		imul	eax, 3			; multiply by 3 (1 byte for each color)
		mov		index, eax		; store in index (calculation not done)
		mov		eax, padBytes	; move number of PadBytes to eax
		imul	eax, ecx		; multiply PadBytes by current Row
		add		index, eax		; add PadBytes calculation to index

		;####################################################
		;#     Get color values from the bits and convert   #
		;#             them to a greyscale value            #
		;#                                                  #
		;#     Since the eye is most sensitive to green     #
		;#       and red, we give them a higher weight      #
		;#       when calculating the greyscale value       #
		;####################################################
		lea		eax, buffer						; load pointer to file data
		add		eax, index						; add offset to pointer
		movzx	ebx, BYTE PTR [eax]				; get blue value
		add		greyVal, ebx					; add 1 * blue to greyVal
		movzx	ebx, BYTE PTR [eax + 1]			; get green value
		imul	ebx, ebx, 6						; green value * 6
		add		greyVal, ebx					; add 6 * green to greyVal
		movzx	ebx, BYTE PTR [eax + 2]			; get red value
		imul	ebx, ebx, 3						; red value * 3
		add		greyVal, ebx					; add 3 * red to greyVal

		;#########################################################
		;#     Calculate index of the character array that       #
		;#          corresponds to the greyscale value.          #
		;#                                                       #
		;#        GreyVal is a value between 0 and 2550.         #
		;#  Divide by 2551 to prevent an index off-by-one error  #
		;#########################################################
		; index = greyVal * numChars / 2551
		mov		eax, greyVal					; store greyVal in eax
		imul	eax, numChars					; greyVal * numChars
		push	edx								; save edx
		mov		edx, 0							; set edx to 0 for division
		mov		num, 2551						; get ready to divide by 2551
		div		num								; index /  2551
		pop		edx								; restore edx
		mov		index, eax						; save calculation in index

		;#####################################################
		;#        Print the character to the console         #
		;#####################################################
		lea		eax, characters				; load pointer to characters array
		add		eax, index					; add offset to pointer
		movzx	eax, BYTE PTR [eax]			; store characters[index] in eax
		pushd	eax							; push characters[eax]
		call	prntCh						; print char represented in eax
		add		esp, 4						; clear stack

		;#####################################################
		;#            Print the character to file            #
		;#####################################################
		lea		eax, characters				; load pointer to characters array
		add		eax, index					; add offset to pointer
		movzx	eax, BYTE PTR [eax]			; store characters[index] in eax
		pushd	eax							; push characters[eax]
		call	prntChF						; print char represented in eax to file
		add		esp, 4						; clear stack

		inc		edx							; increment inner loop counter
        cmp		edx, xPixels				; compare loop counter to file width
        jl		innerLoop1					; loop while less than file wdith
endInnerLoop1:
		call	endl						; print new line to console
		call	endlF						; print new line to file
		dec		ecx							; decrement outer loop counter
		cmp		ecx, 0						; check if we are at beginning of file
		jge		outerLoop1					; if not, loop again
endOuterLoop1:

		;######################################################
		;#                   Exit Program                     #
		;######################################################
        ; ExitProcess(0)
        pushd    0
        call    _ExitProcess@4				; free memory from std_handle
main	ENDP


;######################################################
;#      prntCh(char) outputs a char to console        #
;######################################################
prntCh	PROC
		push	ebp
		mov		ebp, esp
		push	eax				; save eax
		push	ebx				; save ebx
		push	ecx				; save ecx
		push	edx				; save edx
		sub		esp, 4			; space on stack for local variable

		lea		eax, [ebp + 8]	; store pointer to parameter in eax
		lea		ebx, [ebp - 4]	; store pointer to local variable in ebx

		; WriteConsole(hStdout, &msg[0], msgLen, &written, 0)
		pushd	0				; 5 param - MUST be 0
		pushd	ebx				; 4 param - pointer to variable that stores how many characters actually written
		pushd	1				; 3 param - num of characters to write
		pushd	eax				; 2 param - pointer to message
		pushd	hStdout			; 1 param - handle to console screen buffer
		call	_WriteConsoleA@20

		add		esp, 4			; deallocate local variable
		pop		edx				; restore edx
		pop		ecx				; restore ecx
		pop		ebx				; restore ecx
		pop		eax				; restore eax
		pop		ebp				; restore ebp
		ret
prntCh	ENDP

;############################################################
;#       Use WriteFile to output a character to a file      #
;############################################################
prntChF	PROC
		push	ebp
		mov		ebp, esp
		push	eax				; save eax
		push	ebx				; save ebx
		push	ecx				; save ecx
		push	edx				; save edx
		sub		esp, 4			; space on stack for local variables

		lea		eax, [ebp + 8]	; store pointer to parameter in eax
		lea		ebx, [ebp - 4]	; store pointer to local variable in ebx

		; WriteFile(handle, buffer, numBytesToWrite, numBytesWritten, overlap)
		pushd	0				; 5 param - overlap (ignored)
		pushd	ebx				; 4 param - pointer to variable that stores how many characters actually written
		pushd	1				; 3 param - num of bytes to write
		pushd	eax				; 2 param - pointer to buffer containing data to write
		pushd	hFileOut		; 1 param - handle (file to write to)
		call	_WriteFile@20	; WINAPI automatically clears stack

		add		esp, 4			; deallocate local variable
		pop		edx				; restore edx
		pop		ecx				; restore ecx
		pop		ebx				; restore ecx
		pop		eax				; restore eax
		pop		ebp				; restore ebp
		ret
prntChF	ENDP

;######################################################
;#           outputs a new line to console            #
;######################################################
endl	PROC
		pushd	13			; carriage return
		call	prntCh		; call print character
		add		esp, 4		; clear stack
		pushd	10			; line feed
		call	prntCh		; call print character
		add		esp, 4		; clear stack
		ret
endl	ENDP

;######################################################
;#            outputs a new line to file              #
;######################################################
endlF	PROC
		pushd	13			; carriage return
		call	prntChF		; call print character
		add		esp, 4		; clear stack
		pushd	10			; line feed
		call	prntChF		; call print character
		add		esp, 4		; clear stack
		ret
endlF	ENDP

END