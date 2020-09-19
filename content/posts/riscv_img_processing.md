---
title: "Edge-detection and kernel convolution on RISC-V"
date: 2020-09-19T14:40:36-07:00
draft: true
---

It's unfair to paint RISC-V as an underpowered ISA. After all, it's extraordinarily extensible.
However, when I decide to try my hand at image processing on my own RISC-V CPU, underpowered was
exactly the right word to describe what I was working with. The first version of the MCU boasted a
50 MHz clock, 64 KiB of memory, and a multicycle architecture that gave a CPI (cycles per
instruction) just over 2. In short, this is not a lot of power.

## The plan ##

So, I already knew my limitations hardware-wise. But _exactly_ what kind of image processing was I
looking to do? It was hard to choose, so I ultimately decided to implement kernel
convolution with Sobel edge-detection being the main feature.


## Getting an image on the CPU ##

Putting an image on the CPU is certainly easier said that done. Normally, I might just load the
image onto a USB thumb drive or transfer it over SSH. That's not easy to without an OS. Any
sort of I/O would require me to write a hardware driver for the FPGA/CPU in Verilog and the accompanying
software driver in bare-metal C/assembly--not ideal. The easiest solution was going to be to
hard-code the image into the program. I figured each pixel could be a byte such that the bits were
`RRRGGGBB`. It was actually pretty simple to convert an image to a 320x240 array (the size of my
frame buffer) using Python and Pillow.

```python
def image_to_bytes(img_name):
    # open image in read mode
    img = Image.open(img_name, 'r')
    # convert it to 24bit RGB
    img = img.convert(mode='RGB', colors=256)
    # scale it down to 320x240
    img = img.resize((320, 240))
    # get pixel data as a list
    pixels = list(img.getdata())
    # empty list containing new 8bit RGB data
    rgb8_values = []
    for pixel in pixels:
        # scale R value to 3 bits
        # bitshift left 5 times to put it in the most significant bits
        rgb = int((pixel[0]/255.0)*8) << 5
        # scale G value to 3 bits and bitshift
        rgb += int((pixel[1]/255.0)*8) << 2
        # scale B value to 2 bits and bitshift
        rgb += int((pixel[2]/255.0)*4)
        # add the 8bit value to the list of RGB data
        rgb8_values.append(min(rgb, 0xFF))
    # return the completed list
    return rgb8_values
```

I chose to load the array into the program with assembly. It looks something like this:

```
.data
    img:    .byte 0x49, 0x49, 0x49, ...
```

The contents of this array was then copied to the frame buffer, and an image would display on the
screen. Neat!
