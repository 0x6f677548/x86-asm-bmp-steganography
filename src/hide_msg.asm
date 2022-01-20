; "hide_msg.asm"
; 0x6f677548 - 2021


; Hides a text message hidden in a bitmap (steganography)
; text bytes are hidden using LSB of each RGB byte, and ignores anything in A byte
; Hidden bytes are built using 1 bit of each RGB byte (LSB). Bitmap Spec used: ARGB32
; 
; compile:
;   nasm -F dwarf -f elf64 hide_msg.asm
;   ld -o hide_msg hide_msg.o IO_utils.o
; execute:
;   ./hide_msg <messagefile> <bmporiginfile> <bmpdestinationfile>
; execution example:
;   ./hide_msg message.txt mybitmap.bmp mybitmap_mod.bmp

extern openFileForReading   ;external function available at IO_utils.asm/o
extern printString          ;external function available at IO_utils.asm/o
extern printChar            ;external function available at IO_utils.asm/o
extern createFileForWriting ;external function available at IO_utils.asm/o
extern appendToFile         ;external function available at IO_utils.asm/o

section .data

    ;const for codes on syscall - readable code :)
    SYS_READ    equ 0
    SYS_WRITE   equ 1
    SYS_CLOSE   equ 3
    SYS_EXIT    equ 60

    NULL equ 0          ; end of string
    LF equ 10           ; line feed

    ; ----- buffers used ---------
    INPUT_TXT_BUFFER_SIZE equ 1024    ;we'll work with 1k for the txt file
    INPUT_BMP_BUFFER_SIZE equ 5120    ;we'll work with 5k for the bmp file (remarks: buffer needs to be at least the size of offset)
    ; ---------------

    ; error messages
    errMsgOpen db "Error opening the file.", LF, NULL
    errMsgRead db "Error reading from the file.", LF, NULL
    errMsgNoBmp db "Error: input bmp file is not a bitmap.", LF, NULL
    errMsgWrite db "Error while writing output file.", LF, NULL
    errMsgArgs  db "Invalid arguments.",LF, "Usage: hide_msg «file.txt» «input.bmp» «output.bmp»",LF, NULL
    

section .bss
    inputTxtBuffer resb INPUT_TXT_BUFFER_SIZE
    inputBmpBuffer resb INPUT_BMP_BUFFER_SIZE
    inputTxtFileName resq 1         
    inputBmpFileName resq 1
    outputBmpFileName resq 1
    
    inputTxtFileDescriptor resq 1   ; keeps the file descriptor of the input text file
    inputBmpFileDescriptor resq 1   ; keeps the file descriptor of the input bmp file
    outputBmpFileDescriptor resq 1  ; keeps the file descriptor of the output bmp file

    inputBmpBytesRead resq 1        ; keeps the number of bytes that were read into the buffer. 
                                    ; (We're not working with fixed buffer sizes, so we'll discard file size )
    

section .text   
global _start

_start:

    ; -------- loading arguments (addresses)
    pop rdx                              ; get argc
    cmp rdx, 4                           ; verify correct number of arguments. 
    jne errorArgs                        ; we'll accept 3 exact arguments only
    
    pop rdx                              ; name of executable ./Esconder
    pop rdi                              ; ARG0 address (txt filename)
    mov [inputTxtFileName], rdi

    pop rdi                              ; ARG1 address (bmp input)
    mov [inputBmpFileName], rdi
    
    pop rdi                              ; ARG2 address (bmp output)
    mov [outputBmpFileName], rdi

openFilesAndInit:   

    ;--------opening txt file
    mov rdi, [inputTxtFileName]         ; preparing rdi with the address of the filename
    call openFileForReading             ; opens the file in the rdi register
    cmp rax, 0                          ; rax returns file descriptor
    jl errorOnOpen                      ; exiting if error (-XXX on rax)
    mov [inputTxtFileDescriptor], rax   ; store file descriptor
    
   
    ; -------opening input bmp file
    mov rdi, [inputBmpFileName]         ; preparing rdi with the address of the filename
    call openFileForReading             ; opens the file in the rdi register
    cmp rax, 0                          ; rax returns file descriptor
    jl errorOnOpen                      ; exiting if error (-XXX on rax)
    mov [inputBmpFileDescriptor], rax   ; store file descriptor
    
    
    ; ------- creating the destination file
    mov rdi, [outputBmpFileName]        ; preparing rdi with the address of the filename
    call createFileForWriting           ; creates the file in the rdi register
    cmp rax, 0                          ; rax returns file descriptor
    jl errorOnWrite                     ; exiting if error (-XXX on rax)
    mov [outputBmpFileDescriptor], rax  ; store file descriptor


    ; -------reading input bmp to buffer 
    call readNextToInputBmpFileBuffer   ; reads the next block of bytes that fit in buffer
    cmp rax, 0                          ; verify if we have read any bytes. 
    je errorOnRead                      ; this is an error at this point. bmp file is empty. exiting
    mov [inputBmpBytesRead], rax        ; rax returns bytes read


    
    ; ----- preparing execution
    xor rbx, rbx                        ; rbx: index inside txt buffer
    xor r15, r15                        ; r15: number of bytes read from txt file (buffer size or 
                                        ; file size, depending if file fits inside the buffer)

    xor r12, r12                        ; r12: current position at inputBmpBuffer
    xor r13, r13                        ; r13: RGBA index (1 to 4)
    mov r13b, 1                         ; starting at 1 - pixel RGBA byte position (1 to 4 where 4 is A)


    ; ------ obtaining info from the file
    mov dx, [inputBmpBuffer]            ; obtaining file type for validation
    cmp dx, 0x4D42                      ; checking for bitmap file type (0x4D42)
    jne errorNoBmp                      ; this isn't a bitmap - exiting
    
    mov r12d, [inputBmpBuffer+10]       ; reading offset. starting current position at offset 
                                        ; where RGBA start - 32 bit number. 

            
; ------- main cycle (we'll read 1 txt bytes at a time and hide it in 8 bytes of the bmp)
readNextByteToHide:  

    cmp rbx, r15                        ; have we reached end of txt buffer? (this may happen on "loop")
    jb inputTxtFileBufferOk             ; buffer is ok - proceed
    
    ; ----- (re)fill input TXT buffer - this will happen on 1st run and on larger files
    call readNextToInputTxtFileBuffer   ; reads the next block of bytes from the txt file that fit into buffer
    cmp rax, 0                          ; have we reached end of file? (this may also happen on empty txt files)
    je writeEndOfMessageToBuffer        ; if we have no more bytes, we'll jump to EoM writing
    mov r15, rax                        ; update the number of bytes read from the txt file 
                                        ; (buffer size or remaining bytes)
    xor rbx, rbx                        ; reset the index to be used in inputTxtBuffer

      
inputTxtFileBufferOk:

    ; ------- calling hideByteIntoBuffer  - preparing    
    mov dil, [inputTxtBuffer+rbx]     ; reads the next byte to hide into dil;                  
    mov rsi, r12                      ; rsi: current index in the inputBmpBuffer 
                                      ; (from offset to filesize/buffersize)
    mov dl, r13b                      ; dl: current index in the pixel (RGBA) (1 to 4), where 4 is A
    call hideByteIntoBuffer           ; calling the main function that knows how to hide this byte into buffer
    ;keeping return values
    mov r13b, dl                      ; rdx: current index in the pixel
    mov r12, rax                      ; rax: current index in the inputBmpbuffer
    

    ; ---- incrementing rbx and looping back (next byte)
    inc rbx                           ; rbx: index inside txt buffer
    jmp readNextByteToHide
  ; --


; --- we've reached end of TXT file - 
writeEndOfMessageToBuffer:

    ; ------- calling hideByteIntoBuffer  - preparing    
    mov dil, 0x00                     ; 0x00 is used as the byte that triggers end of hidden string in the BMP pixels
    mov rsi, r12                      ; rsi: current index in the inputBmpBuffer (from offset to filesize/buffersize)
    mov dl, r13b                      ; dl: current index in the pixel (RGBA) (1 to 4), where 4 is A
    call hideByteIntoBuffer           ; calling the main function that knows how to hide this byte into buffer

writeOutputFile: 

    ; ------- append to file the current buffer
    mov rdi, [outputBmpFileDescriptor]  ; prepare rdi with the destination file descriptor
    mov rsi, inputBmpBuffer             ; prepare rsi with the inputBmpBuffer to write
    mov rdx, [inputBmpBytesRead]        ; prepare rdx with the number of bytes to write
    call appendToFile                   ; calling appendToFile - this appends the current buffer to the file 
    cmp rax, 0                          ; rax returns bytes written
    jl errorOnWrite                     ; exiting if error (-XXX on rax)


    ; ----- write the remainder unchanged bytes from input bmp
    ; we need to read the remainder input bmp file, and write to the ouput file all unchanged bytes
    ; loop until we write the rest of the input file
    call readNextToInputBmpFileBuffer   ; reads the next block of bytes that fit in buffer
    mov [inputBmpBytesRead], rax        ; rax returns bytes read
    cmp rax, 0                          ; check if we have written bytes. 
    jg writeOutputFile                  ; in that case, loop back and write that buffer to the output file
    
    
    
; ---- close all working files and exit with success
closeFilesAndExit_0:

    mov rax, SYS_CLOSE
    mov rbx, [inputTxtFileDescriptor]
    syscall
    
    mov rax, SYS_CLOSE
    mov rbx, [inputBmpFileDescriptor]
    syscall

    mov rax, SYS_CLOSE
    mov rbx, [outputBmpFileDescriptor]
    syscall

_sys_exit_0:
    mov rax, SYS_EXIT
    mov rdi, 0                           ; while xor rdi, rdi could be faster, we're exiting and this is clearer to read.
    syscall

; ---- end of main block - success run should end here


; exiting with code 1
_sys_exit_1:
    mov rax, SYS_EXIT
    mov rdi, 1
    syscall    
    
; error with input arguments
errorArgs:
    mov rdi, errMsgArgs
    xor rsi, rsi
    call printString
    jmp _sys_exit_1
    
; error when input bmp file is not a bmp
errorNoBmp:
    mov rdi, errMsgNoBmp
    xor rsi, rsi
    call printString
    jmp _sys_exit_1
        
; -----
; Error on read.
errorOnRead:
    mov rdi, errMsgRead
    xor rsi, rsi
    call printString
    jmp _sys_exit_1
    
; -----
; Error on open.
errorOnOpen:
    mov rdi, errMsgOpen
    xor rsi, rsi
    call printString
    jmp _sys_exit_1
    
; -----
; Error on writing.
errorOnWrite:
    mov rdi, errMsgWrite
    xor rsi, rsi
    call printString
    jmp _sys_exit_1
    
; **********************************************************
; Reads the next buffer of bytes of fileDescriptor into buffer
; no arguments. uses global vars inputBmpFileDescriptor, inputBmpBuffer and INPUT_BMP_BUFFER_SIZE
; checks for erros on rax before returning
; returns the number of bytes read (rax)
readNextToInputBmpFileBuffer: 
    mov rax, SYS_READ
    mov rdi, [inputBmpFileDescriptor]
    mov rsi, inputBmpBuffer
    mov rdx, INPUT_BMP_BUFFER_SIZE
    syscall
    cmp rax, 0      ; did we have an error?
    jl errorOnRead
    ret

    
; **********************************************************
; Reads the next buffer of bytes of fileDescriptor into buffer
; no arguments. uses global vars inputTxtFileDescriptor, inputTxtBuffer and INPUT_TXT_BUFFER_SIZE
; checks for erros on rax before returning
; returns the number of bytes read (rax)
readNextToInputTxtFileBuffer: 
    mov rax, SYS_READ
    mov rdi, [inputTxtFileDescriptor]
    mov rsi, inputTxtBuffer
    mov rdx, INPUT_TXT_BUFFER_SIZE
    syscall
    cmp rax, 0      ; did we have an error?
    jl errorOnRead
    ret
    

; **********************************************************
; Hides a byte into the inputBmpBuffer, using the provided index arguments
; 1) rdi/dil: byte to hide
; 2) rsi: current index in the buffer (inputBmpBuffer) of the byte to manipulate(from offset to filesize/buffersize)
; 3) rdx/dl: current index in the pixel (RGBA) (1 to 4), where 4 is A
; returns:
; dl: current index in the pixel  (we're not in a lib, and we want to avoid memory usage, so we'll use a register)
; rax: current index in the buffer being manipulated (inputBmpBuffer)
hideByteIntoBuffer:


    ; ------ preparing execution
    xor r10, r10                        ; keeps the bit index inside the byte to hide
    mov r10b, 7                         ; bit index starting at 7 (7 to 0)
    

hideByteIntoBufferNextBit: 


    ; ------ check the current index in the RGBA byte    
    cmp dl, 4                           ; are we at transparency?
    jb hideByteIntoBufferPixelIndexOk   ; we're not. proceeding

    inc rsi                             ; yes, we're at transparency: move one byte further
    mov dl, 1                           ; move to the next pixel block and starting at 1. 
    
    
    
hideByteIntoBufferPixelIndexOk:

    ; ---- checking input BMP buffer 
    cmp rsi, [inputBmpBytesRead]        ; are we at the end of current BMP buffer
    jb hideByteIntoBufferInputBufferOk  ; buffer is ok - proceeding
    
    ; ------- we're out of buffer. append to file, and refill the buffer
    ; pushing to stack non preserved registers being used
    push rdi                        
    push rsi
    push rdx
    push r10

    ; preparing append file execution
    mov rdi, [outputBmpFileDescriptor]  ; prepare rdi with the destionation file descriptor
    mov rsi, inputBmpBuffer             ; prepare rsi with the inputBmpBuffer to write
    mov rdx, [inputBmpBytesRead]        ; prepare rdx with the number of bytes to write
    call appendToFile                   ; calling appendToFile - this appends the current buffer to the file 
    cmp rax, 0                          ; rax returns bytes written
    jl errorOnWrite                     ; exiting if error (-XXX on rax)


    ; refilling BMP buffer
    call readNextToInputBmpFileBuffer   ; reads the next block of bytes that fit in buffer
    mov [inputBmpBytesRead], rax        ; getting bytes read

    ; popping out non preserved registers being used    
    pop r10
    pop rdx
    pop rsi
    pop rdi
    
    xor rsi, rsi                        ; we have refilled the buffer: reset the index inside bmp buffer
    ; -------


; buffer is ok, and we're at a non transparency byte - let's hide the bit here
hideByteIntoBufferInputBufferOk:

    mov r11b, [inputBmpBuffer+rsi]      ; byte that will be changed in the buffer
    
    
    ; ------ preparing hideBitIntoByte execution
    ; pushing to stack non preserved registers being used
    push rdi
    push rsi
    push rdx
    push r10
    
    ; mov dil, dil                      ; not needed: for documentation only - rdi is the byte to hide and to extract bit
    mov sil, r10b                       ; index of the bit to extract
    mov dl, r11b                        ; byte where bit will be hidden
    call hideBitIntoByte 
    
    ; popping out non preserved registers being used    
    pop r10
    pop rdx
    pop rsi
    pop rdi
    
    mov [inputBmpBuffer+rsi], al   ; move manipulated byte back to buffer, before changing index
    

    ; ------ increment counters and evaluate if we should loop back
    inc rsi                             ; buffer index position. 
    inc dl                              ; RGBA (1 to 4)
        
    cmp r10b, 0                         ; have we reached the last bit of byte to hide
    je hideByteIntoBufferEnd            ; this byte is done : next!
    
    dec r10b                            ; bit index (7 to 0)
    jmp hideByteIntoBufferNextBit       ; looping back and proceed with next bit .
                                        ;(this jump/logic could eventually be done with loop, but 
                                        ; code is cleaner using the bit index, avoiding dec/inc inside hideBitIntoByte)

hideByteIntoBufferEnd:
    xor rax, rax                        ; preparing rax for return
    mov rax, rsi                        ; return current index in the buffer
    ; mov dl, dl                        ; not needed. for documentation only - return current index in the pixel

    ret



; **********************************************************
; Extracts the bit at the provided index from the provided byte,
; and adds it to the byte to be worked in the LSB
; Arguments:
; 1) rdi/dil: byte to hide and to extract bit
; 2) rsi/sil: index where to extract the bit
; 3) rdx/dl: byte where bit will be hidden (lsb)
; Returns: byte changed with the new bit (al)
hideBitIntoByte:
    
    mov r10b, 1b                        ; 00000001b mask
    mov cl, sil                         ; preparing cl for the bit shift
    shl r10b, cl                        ; positioning the bit at the index provided
    and r10b, dil                       ; discarding all other bits from byte to extract
    
    shr r10b, cl                        ; positioning the bit to record in the lsb
    
    xor rax, rax                        ; preparing rax
    mov al, dl                          ; moving the byte to change to al (result)
    and al, 11111110b                   ; clearing the lsb from the byte to change 
    or  al, r10b                        ; adding the bit to the current character

    ret
