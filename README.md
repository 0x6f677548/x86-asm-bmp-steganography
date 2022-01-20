# x86-asm-bmp-steganography
Sample x86-64 assembly program, demonstrating how to hide a message in a bitmap by slightly manipulating its pixels.

## Language
x86-64 assembly

## Purpose
This repository demonstrates how to hide a text message inside a bitmap by slightly changing the RGB bytes of each pixel. It assumes that the original bitmap uses the [ARGB32 specification](https://en.wikipedia.org/wiki/RGBA_color_model#ARGB32). <br>
It has been written to practice x86 asm, and it demonstrates several fundamental asm techniques on file and byte manipulation and critical concepts on register manipulation and the x86 architecture. 

## The use of a bitmap
A bitmap is an uncompressed format where each pixel is described individually by a combination of 4 bytes. It has two sections: header and pixels. The header can have a variable size, and it follows one of the available specifications. The current project supports ARGB32. 
Since each pixel is represented by a combination of 4 bytes (RGBA), the code can manipulate the RGB bytes to hide a message without visual impact to the user.

## Approach
In order to hide the message, the program will manipulate each least significant bit (LSB) of the RGB bytes by replacing it with the message bits. The Alpha byte (A) will not be changed by the program, avoiding changes in the image that should not be detected by human vision.

The program will manipulate each pixel in 3 bytes (RGB), meaning each pixel will hold 3 bits of the message. This approach allows any image with ***N x N*** pixels, to hold ***(N^2 X 3 ) / 8*** message characters. 

The code demonstrates how to find the *size* and *offset* bytes in the header and then navigate through the bitmap using reader buffers and replace the RGB bytes with manipulated ones.

## Implementation files

## Usage
### Hiding a message
`./hide_msg <messagefile> <bmporiginfile> <bmpdestinationfile>` <br>
execution example:
`./hide_msg message.txt mybitmap.bmp mybitmap_mod.bmp`

### Showing a message hidden in a manipulated bitmap
`./show_msg <bmpfile>`<br>
execution example:
`./show_msg mybitmap_mod.bmp`


## Compiling
`build.sh` can be executed to compile executables `show_msg` and `hide_msg`.

You can also create object and executable files with the following commands:<br>
`nasm -F dwarf -f elf64 IO_utils.asm`<br> 
`nasm -F dwarf -f elf64 hide_msg.asm`<br>
`ld -o hide_msg hide_msg.o IO_utils.o`<br>
`nasm -F dwarf -f elf64 show_msg.asm`<br>
`ld -o show_msg show_msg.o IO_utils.o`<br>


## Requirements
This code was written targetting ubuntu x86, and it requires NASM installed. You can install it through:  
`sudo apt-get install nasm`
