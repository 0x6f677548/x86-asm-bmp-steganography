; "IO_utils.asm"
; 0x6f677548 - 2021

; Library of reusable IO functions that can be used across the project
; 
; compile:
;   nasm -F dwarf -f elf64 IO_utils.asm
;   ld -o Program program.o IO_utils.o

section .data

    ;const for codes on syscall - readable code :)
    SYS_WRITE   equ 1
    SYS_OPEN    equ 2
    SYS_CREATE  equ 85
    O_RDONLY    equ 0
    
    O_WRONLY    equ 1
    S_IRUSR equ 00400q  ; read permission
    S_IWUSR equ 00200q  ; write permission
   
    
    NULL equ 0 ; end of string
    STDOUT equ 1 ; standard output
    
    
section .text

; **********************************************************
; Opens the filename indicated in RDI for read only
; Arguments:
; 1) rdi: filename
; Returns: file descriptor (rax) or error code
global openFileForReading
openFileForReading:
    mov rax, SYS_OPEN
    mov rsi, O_RDONLY
    syscall
    ret

; **********************************************************
; Procedure to display a single character to the screen.
; Uses syscall to output characters
; Arguments:
; 1) rdi: character
; Returns: error code if any        
global printChar
printChar:
    mov rax, SYS_WRITE
    mov rsi, rdi
    mov rdi, STDOUT
    mov rdx, 1        ; size
    syscall
    ret
    
; **********************************************************
; Procedure to output a string to the console
; String must be NULL terminated.
; Arguments:
; 1) rdi: address of string
; 2) rsi: length of string (optional). if 0, function calculates the length by looking for NULL(0)
; Returns: error code if any        
global printString
printString:
    mov rdx, rsi
    cmp rdx, 0                      ; do we have the string length? 
    jne printStringSyscall

    mov rdx, rdi                    ; keep the address of the string start
printStringNextChar:
    cmp byte [rdx], NULL;           ; have we reached the eos
    jz printStringEndofstring
    inc rdx                         ; increment the address
    jmp printStringNextChar
    
printStringEndofstring:
    sub rdx, rdi                    ; subtracting the address of the end with beginning (length)
                                    ; rdx is supposed to have length here

printStringSyscall:      
    mov rax, SYS_WRITE
    mov rsi, rdi
    mov rdi, STDOUT
    syscall

    ret


; **********************************************************
; Creates the filename indicated in RDI for writing
; Arguments:
; 1) rdi: filename
; Returns: file descriptor (rax)
global createFileForWriting
createFileForWriting:
    ;output file - creating it
    mov rax, SYS_CREATE
    mov rsi, O_WRONLY | S_IRUSR | S_IWUSR
    syscall
    ret


; **********************************************************
; Procedure to append a buffer to the end of file
; Arguments:
; 1) rdi: file descriptor
; 2) rsi: address of buffer
; 3) rdx: buffer size
; returns 
; rax: number of bytes written (or error code)
global appendToFile
appendToFile:
    ; all arguments are a the correct register
    mov rax, SYS_WRITE
    syscall
    ret