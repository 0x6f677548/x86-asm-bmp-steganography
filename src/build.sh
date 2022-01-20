#!/bin/bash


nasm -F dwarf -f elf64 IO_utils.asm
nasm -F dwarf -f elf64 hide_msg.asm
ld -o hide_msg hide_msg.o IO_utils.o

nasm -F dwarf -f elf64 show_msg.asm
ld -o show_msg show_msg.o IO_utils.o

