; "show_msg.asm"
; 0x6f677548 - 2021
; License: GNU v3

; Shows a text message hidden in a bitmap (steganography)
; text bytes are recovered using LSB of each RGB byte, and ignores anything in A byte
; recovered bytes are built using 1 bit of each RGB byte (LSB). Bitmap Spec used: ARGB32
; 
; compile:
;   nasm -F dwarf -f elf64 show_msg.asm
;   ld -o show_msg show_msg.o IO_utils.o
; execute:
;   ./show_msg <bmpfile>
; execution example:
;   ./show_msg mybitmap_mod.bmp

extern openFileForReading   ;external function available at IO_utils.asm/o
extern printString          ;external function available at IO_utils.asm/o
extern printChar            ;external function available at IO_utils.asm/o
    
section .data

    ;const for codes on syscall - readable code :)
    SYS_READ    equ 0
    SYS_CLOSE   equ 3
    SYS_EXIT    equ 60
    
    NULL equ 0 ; end of string
    LF equ 10 ; line feed
    
    
    ; default file to be used on tests
    testDefaultFileName db "./testbitmap.bmp", NULL
    testMode db 0  ; 1 = true - activates some test code, defaulting to testDefaultFileName ; false otherwise

    
    INPUT_BUFFER_SIZE equ 1024    ;we'll work with 1k and refill it as needed. 

    ; error messages
    errMsgOpen db "Error opening the file.", LF, NULL
    errMsgRead db "Error reading from the file.", LF, NULL
    errMsgNoArgs  db "Please provide a filename. ", LF, "Usage: show_msg «file.bmp»",LF, "Example: show_msg mybitmap_mod.bmp", LF, NULL
    errMsgTooManyArgs  db "No more than one argument with filename is allowed.",LF, "Usage: show_msg «file.bmp»",LF, "Example: show_msg mybitmap.bmp", LF, NULL
    

section .bss
    inputBmpFileBuffer resb INPUT_BUFFER_SIZE
    
    fileDescriptor resq 1   ; keeps the file descriptor
    fileSize resd 1 ; keeps file size
    hiddenByte resb 1

section .text   
global _start

_start:
    
    ; block of code that initializes test/dev code in the beginning of the program, when activated
    ; see testMode var (0/1)
    mov dil, [testMode]
    cmp dil, 1
    jne readArguments
    
    mov rdi, testDefaultFileName
    jmp openFileAndStart
 
readArguments:
    
    pop rdx   ; get argc
    cmp rdx, 2; verify if at least one argument

    jb errorNoArgs     ; check for no arguments (other than program name)
    ja errorTooManyArgs ; check for too many arguments
    
    pop rdx ; name of executable ./Recuperar
    pop rdi ; ARG0 address (filename)

            
openFileAndStart:

    call openFileForReading
    cmp rax, 0
    jl errorOnOpen              ; exiting if error (-XXX on rax)
    mov [fileDescriptor], rax   ; store file descriptor

    call readNextToInputBmpFileBuffer       ; reads the next block of bytes that fit in buffer
    
    
    mov edx, [inputBmpFileBuffer+2]         ; file size - 32bit number
    mov [fileSize], edx

    ; preparing execution
    xor rcx, rcx
    xor r12, r12;   
    xor r13, r13;
    xor r14, r14
    xor r15, r15

    
    mov ecx, [inputBmpFileBuffer+10]  ; offset where RGBA start - 32 bit number
                          ; byte counter - starting at offset
    
    mov r12b, 7           ; current bit index to be used while building the byte
    mov r13b, 0           ; byte value being built
    mov r14b, 1;          ; byte counter inside pixel (each pixel has 4 bytes BGRA)
    mov r15d, ecx;        ; index inside inputBmpFileBuffer


recovernextbyte:

    cmp r15d, INPUT_BUFFER_SIZE   ; have we reached end of buffer?
    jb inputBmpFileBufferOk          
    
    push rcx
    call readNextToInputBmpFileBuffer   ; reads the next block of bytes that fit in inputBmpFileBuffer
    pop rcx
    mov r15d, 0             ; reset the index to be used in inputBmpFileBuffer

    
inputBmpFileBufferOk:

    cmp r14b, 4;
    je resetpixelbytecounter    ; if we're at A (transparency), we'll skip the reading block
      
    push rcx
    push rdx
    
    ; prepare extractBitToByte execution
    mov dil, [inputBmpFileBuffer+r15d]      ; byte where bit will be extracted
    mov sil, r12b               ; bit index 
    mov dl,  r13b               ; byte to be changed;
    call extractBitToByte
    mov r13b, al;               ; manipulated byte
    ;----
    
    
    pop rdx
    pop rcx
    
    
    cmp r12b, 0                 ; bit index - if zero, we have our byte ready
    je byteready
    dec r12b
    jmp updatecounters
    
byteready:
    mov r12b, 7                 ; reset the bit index    
    cmp r13b, NULL              ; are we in the last byte of the obfuscated string? 
    je closeFileAndExit_0 
    
    push rdi
    push rcx
    push rdx

    mov [hiddenByte], r13b      
    mov rdi, hiddenByte         ; preparing rdi for function call
    call printChar              ; sending the byte to the output

    mov r13b, 0                 ;  resetting the next obfuscated byte to build
    pop rdx
    pop rcx
    pop rdi
    jmp updatecounters

resetpixelbytecounter: 
    mov r14b, 0                 ; byte counter inside pixel   


updatecounters:
    inc r14b                    ; byte counter inside pixel (1 to 4)
    inc ecx                     ; file - byte counter
    inc r15d                    ; inputBmpFileBuffer - byte counter
    cmp ecx, [fileSize]         ; did we reached eof? this may happen on bmp with no hidden messages or malformed ones
    jb recovernextbyte
    
 

closeFileAndExit_0:
    mov rax, SYS_CLOSE
    mov rbx, [fileDescriptor]
    syscall
    
    call _sys_exit_0
    
_sys_exit_0:
    mov rax, SYS_EXIT
    mov rdi, 0
    syscall
    
errorNoArgs:
    mov rdi, errMsgNoArgs
    xor rsi, rsi
    call printString
    jmp _sys_exit_1

errorTooManyArgs:
    mov rdi, errMsgTooManyArgs
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
; Error on read.
errorOnRead:
    mov rdi, errMsgRead
    xor rsi, rsi
    call printString
    jmp _sys_exit_1


; exiting with code 1
_sys_exit_1:
    mov rax, SYS_EXIT
    mov rdi, 1
    syscall
    



; **********************************************************
; Reads the next buffer of bytes of fileDescriptor into buffer
readNextToInputBmpFileBuffer: 
    mov rax, SYS_READ
    mov rdi, [fileDescriptor]
    mov rsi, inputBmpFileBuffer
    mov rdx, INPUT_BUFFER_SIZE
    syscall
    cmp rax, 0      ; did we have an error?
    jl errorOnRead
    ret

   


; **********************************************************
; Extracts the less significant bit from the provided byte,
; and adds it to the byte to be worked in the index provided
; Arguments:
; 1) rdi/dil: byte to extract bit
; 2) rsi/sil: index where to position the bit
; 3) rdx/dl: byte to be worked
; Returns: byte changed with the new bit (al)
extractBitToByte:
    
    mov r10b, dil   ; byte to extract lsb
    and r10b, 1b    ; 0000 0001 - discarding all other bits
    
    mov cl, sil     ; index where to position the bit
    shl r10b, cl    ; shifting the new bit to the position where we need it. bitidx starts at 7 
    
    mov al, dl
    or  al, r10b    ; adding the bit to the current character
    ret;    



    

