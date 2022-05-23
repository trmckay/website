---
title: "Rust on baremetal RISC-V"
date: 2021-06-08
tags: ["risc-v", "rust", "no-std", "baremetal", "embedded"]
author: "Trevor McKay"
showToc: false
TocOpen: false
draft: false
hidemeta: false
comments: false
description: "Set up a development environment for Rust on RISC-V rv32i"
canonicalURL: "https://trmckay.dev/posts/"
disableShare: true
disableHLJS: false
hideSummary: false
searchHidden: true
ShowReadingTime: true
ShowBreadCrumbs: true
ShowPostNavLinks: true
ShowWordCount: false
ShowRssButtonInSectionTermList: true
UseHugoToc: true
cover:
    hidden: false
    image: "https://raw.githubusercontent.com/aldeka/rustacean.net/master/site/more-crabby-things/rustbook-emotes/unsafe.png"
---

I have been experimenting with Rust lately and it has been really fun. One of my recent challenges
to myself was to see if I could get baremetal Rust running on my pretty barebones RISC-V chip. It's
rv32i with a very limited amount of space and sort-of weird memory map. This sort of thing is
trivial to deal with when writing assembly, and still not too bad when writing C. However, step
further away from the metal, and your very precise target becomes harder and harder to hit. However,
Rust is AOT-compiled and LLVM, so this should be possible, right? By the end of this tutorial I will
show you how and hopefully make your baremetal a bit Rustier in the process.

The process boils down to a few steps:

* Compile some code for your target.
* Compile some code without fancy stuff like the standard library or a main routine.
* Jump to Rust from assembly.
* Link everything up correctly.
* Program your device.


# Toolchain setup

I'll assume some familiarity with Rust and Cargo in this tutorial. But one thing to note is that I
would use `rustup` to manage your Rust toolchains. I suspect it isn't 100% necessary depending on
what your distro packages, but I found it easiest. Navigate to [rustup.rs](https://rustup.rs/).
They'll tell you to run this command:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

Let's install the toolchains for our target architecture. I'll use rv32i (`riscv32i-unknown-none-elf`),
but you can check out the supported architectures by running `rustup target list`. Also, for some of
the assembly features, we need the nightly toolchain.

Let's let `rustup` take care of those things:

```bash
rustup toolchain add nightly
rustup toolchain default nightly
rustup target add riscv32i-unknown-none-elf
```

Give that some time to run and you should good to go. Let's make a project.


# Rust

```bash
mkdir rust-baremetal
cd rust-baremetal
cargo init
```

This will initialize a new binary crate in the `rust-baremetal` directory. By default, this targets
the host architecture. We can cross-compile by passing the `--target` flag to `cargo`. However,
we're under the assumption that this project is intended only for your embedded system, not just
occasionally cross-compiled.

We can configure these sorts of things in a `<project_root>/.cargo/config` file. For my target this
looks something like this:

```
[build]
target = "riscv32i-unknown-none-elf"
```

Now running `cargo build` or `cargo run` includes an implicit `--target riscv32i-unknown-none-elf`.

If your targeting ARM or something like rv32gc you may not see this, but for more barebones
architectures like rv32i, something like this appears when you `cargo build`:

```
   Compiling riscv-rust-sandbox v0.1.0 (/home/trevor/Development/riscv-rust-sandbox)
error[E0463]: can't find crate for `std`
```

This is because there is no standard library for the target architecture. My assumption is that this
is because the standard library depends on system calls that are unavailable for architectures like
rv32i with no mainstream OS support. Regardless, available or not, we don't want it.

We can add `#![no_std]` to the top of `main.rs` and remove the dependent calls like `println!()`.
Since the standard library also defines our panic handler, we need to include that, too. A simple
panic write print some debug information and exit (or loop on baremetal). No matter what it should
have this prototype and annotation:

```rust
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> !
```

Finally we need the `start` language item to define the entrypoint. I find it easiest to just call
the entrypoint from assembly. Plus it allows for setting up what ever state your MCU might need
before jumping into the main routine. As such, our Rust code will have no main. We'll more or less
be left with a binary object with a few symbols we can jump to from assembly.

We'll stick with just loops for now, since we don't really have any devices to use. With all that,
your main might look something like this:

```rust
#![no_std]
#![no_main]

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    loop {}
}

fn rs_main() {
    loop {}
}
```

This code is still, however, just a collection of functions—not quite a program. We need to write a
small assembly program to load our Rust program. Since we want to enter from assembly, we also need
our `rs_main` use the C ABI with an unmangled symbol name. This guarantees two things: the `rs_main`
will exist and we can reference it from assembly, and `rs_main` uses the calling convention that C
uses (register meanings, stack behavior, etc.). Once we are in Rust permanently, this is no longer a
problem. The `extern "C"` modifier takes care of the ABI, and the `#[no_mangle]` annotation does the
rest. Let's also do one more thing: give `rs_main` the `!` return type. This means the function
_cannot_ return and this will be enforced by the compiler. This way, when our assembly loader jumps
to Rust, we can be confident we aren't coming back.

So, with all that we have:

```rust
#![no_std]
#![no_main]

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    loop {}
}

#[no_mangle]
pub extern "C" fn rs_main() -> ! {
    loop {}
}
```

Now for the assembly loader. We will need to do the following:

* Make sure our assembly appears in the `.text.init` section, so it is executed first.
* Set up any necessary state (sometimes doable in Rust but often easier in assembly).
* Call `rs_main`.

```asm
.section .text.init

.global _start
_start:
    la   sp, __sp
    call rs_main
```

Ignore the labels for now, those will be defined in the linker script later. For now, let's just
focus on the assembly. It turns out to be very simple; the only "necessary" state we need (for my
target at least) is the stack pointer. Then we can immediately jump to Rust.

I included this in `<project_root>/src/asm/init.s`, but it won't automatically be compiled with the
Rust. We can, however, use the `global_asm` language feature to do this (this is why we needed to
use nightly Rust). So, let's enable the feature and use the macro to include our file.

This should go at the top of `main.rs`:

```rust
#![feature(global_asm)]

global_asm!(include_str!("asm/init.s"));
```

Now we have something that very nearly works. Let's take a look at what we get if we compile as
is (I will comment out the stack-pointer line for now)[^fn1].

[^fn1]: To do any of this binary manipulation, you need to build and install the
[`riscv-gnu-toolchain`](https://github.com/riscv/riscv-gnu-toolchain.git) (or whatever the relevent
toolchain is to gain access to `objcopy` and `objdump` for your target).

```
$ cargo build && objdump -S target/riscv32i-unknown-none-elf/debug/rust-baremetal-sandbox

target/riscv32i-unknown-none-elf/debug/riscv-rust-sandbox:     file format elf32-littleriscv


Disassembly of section .text:

0001117c <_start>:
   1117c:	00000097          	auipc	ra,0x0
   11180:	018080e7          	jalr	24(ra) # 11194 <rs_main>

00011184 <rust_begin_unwind>:
#![feature(global_asm)]

global_asm!(include_str!("asm/init.s"));

#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
   11184:	ff010113          	addi	sp,sp,-16
   11188:	00a12623          	sw	a0,12(sp)
   1118c:	0040006f          	j	11190 <rust_begin_unwind+0xc>
    loop {}
   11190:	0000006f          	j	11190 <rust_begin_unwind+0xc>

00011194 <rs_main>:
}

#[no_mangle]
pub extern "C" fn rs_main() {
   11194:	ff010113          	addi	sp,sp,-16
   11198:	00000513          	li	a0,0
    let mut i: u32 = 0;
   1119c:	00a12623          	sw	a0,12(sp)
    loop {
   111a0:	0040006f          	j	111a4 <rs_main+0x10>
        i += 1;
   111a4:	00c12583          	lw	a1,12(sp)
   111a8:	00158513          	addi	a0,a1,1
   111ac:	00a12423          	sw	a0,8(sp)
   111b0:	00b56a63          	bltu	a0,a1,111c4 <rs_main+0x30>
   111b4:	0040006f          	j	111b8 <rs_main+0x24>
   111b8:	00812503          	lw	a0,8(sp)
   111bc:	00a12623          	sw	a0,12(sp)
    loop {
   111c0:	fe5ff06f          	j	111a4 <rs_main+0x10>
        i += 1;
   111c4:	00010537          	lui	a0,0x10
   111c8:	0e050513          	addi	a0,a0,224 # 100e0 <str.0>
   111cc:	000105b7          	lui	a1,0x10
   111d0:	0cc58613          	addi	a2,a1,204 # 100cc <.L__unnamed_1>
   111d4:	01c00593          	li	a1,28
   111d8:	00000097          	auipc	ra,0x0
   111dc:	024080e7          	jalr	36(ra) # 111fc <_ZN4core9panicking5panic17h19ac0e09707907c5E>
   111e0:	c0001073          	unimp
```

I've omitted some of the binary, but we begin to get an idea of what is happening.

As for linking, we can easily include this with some flags passed to `rustc`. This is configured
in `.cargo/config`, again. You can put your linker script in the project root, and include it with a
line like this:

```
rustflags = ['-Clink-arg=-Tlink.ld']
```

This will ensure that objects are linked according to this script.

This covers most of the basics. We can now compile code for the right architecture, link it for our
specific target, and start executing it from an assembly entrypoint. Here is my example of an
actually useful program:

```rust

#![no_std] // No standard library. We can't use this.
#![no_main] // We do have a main, but not in the standard Rust way.
#![feature(asm, global_asm)]

// Include assembly file during compilation.
// We need to include some things at the top of
// the text section.
global_asm!(include_str!("asm/init.s"));

// Rust modules that we include with the project.
pub mod otter;
mod panic;

// Compute the nth Fibonacci number.
// fib(0) = 1, fib(1) = 1, fib(n) = fib(n-1) + fib(n-2)
fn fib(n: u32) -> u32 {
    match n {
        0 | 1 => 1,
        _ => fib(n - 1) + fib(n - 2),
    }
}

// main() is called by Rust, so we can drop the C ABI.
fn main() {
    loop {
        // Load in switches value.
        let sw = otter::switches_rd() as u32;

        // Calculate fibonacci number.
        let fib = fib(sw) as u16;

        // Write it to the seven segment display.
        otter::sseg_wr(fib);
    }
}

// While RISC-V is a supported platform for Rust, it does not have
// a stable ABI (on any platform, for that matter).
// 'no_mangle' and 'extern "C"' makes Rust use the C ABI.
// Once we are calling Rust from Rust, we don't need this anymore.
//
// Rust will not let you do a lot of unsafe things.
// Returning from your entry-point on baremetal is one of those
// things. This code will not compile if it is possible to
// return from _rust_entry(). Hence, the panic (which does not return).
#[no_mangle]
pub extern "C" fn _rust_entry() -> ! {
    main();
    panic!();
}
```

You can also check out [this repository](https://github.com/trmckay/rv-rust-baremetal) for an
implementation of the concepts described in the post. Thanks for reading!
