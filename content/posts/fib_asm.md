---
title: "Exercises in assembly: recursion"
date: 2021-01-31T18:48:09-08:00
draft: false
---

Trying to implement a recursive algorithm in assembly is both a challenging puzzle
and very informative exercise to demonstrate some important properties
of recursion and function calls in general.

# Recursion

Recursion is super important for writing clean and concise solutions
to a whole subset of programming tasks. That's not to say it's without
its drawbacks.

Some problems can be solved both iteratively and recursively. Due to the
way a computer works—specifically the stack—the recursive solution often
produces _less efficient_ code.

Each time a new function is called, the CPU has to allocate a new stack frame,
a section of memory that belongs to the new function call. Usually this
involves saving a bunch of registers to the stack. The reverse is performed
as the function exits.

```
------------------

    Caller's
    stack frame

------------------

    Fn(0)

------------------

    ...

------------------

    Fn(n-1)

__________________

    Fn(n)

------------------
                        Stack grows down
    ...
                               |
------------------             v
```

Depending on the architecture of your CPU, the stack memory is probably cached
unless you have a very deep call-stack, so this is less of a problem with
shallow recursion, especially if your algorithm does not frequently access
dynamic memory.

# Fibonacci

Let's take a look at this in practice with a function that calculates
the `n`th number of the Fibonacci sequence.

You have maybe seen a function like this to perform that task:

```c
int fib(int n) {
    if (n <= 1)
        return n;
    else
        return fib(n - 1) + fib(n - 2);
}
```

This solution is borderline trivial once one has a grasp of recursion.

The amount of work done by the compiler is drastically understated by the text.
Especially this line:

```c
return fib(n - 1) + fib(n - 2);
```

The compiler needs to:

- Make two function calls, where each:
    - Saves all temporary registers to the stack.
    - Decrements the stack pointer.
    - Jumps to the program count of the function.
    - Pops the temporary registers and return address from the stack.
- Combine each result into a single result.
- Deallocate the current scope's stack frame.
- Jump to the return address.

That's a lot of information packed into just a few characters. Implementing `fib` in
assembly may start to seem a little daunting given this understanding. But don't worry!
If you take it slow and take advantage of abstractions the same way a high-level
language like C does, it is very possible.

# Black-box model of the function

Let's take a look at what our function is expected to do.

```c
/* Arguments: n = Which Fibonacci number to calculate
 * Returns:   fib(n) = The nth Fibonacci number */
int fib(int n);
```

This is simple enough. Give an `int`, get an `int`.

Lets translate this into assembly. I'm going to use RISC-V assembly for the
purposes of this post.

There's some preliminary assembly info we need first. The RISC-V ABI says that
arguments go into the `a0`-`a7` registers. The same is true for return values.
Additionally, functions (generally referred to as subroutines in the context of
assembly) are prefixed with a label (like `FIB`) so they can be jumped/branched to.

With this is mind we should define our `FIB` subroutine like this:

```
# a0 <- fib(n)
# Arguments: a0 = n
# Returns:   fib(n) in a0
FIB:
```

Notice there's not a single instruction here. We just have a label and some
commented assumptions our function makes. Unlike when writing a function
signature in C, we have no compiler to enforce type compatibility or calling
conventions. So, all we do is give our program counter somewhere to jump to.

# Planning the structure

Before we start writing any more assembly, it would benefit us to plan out our
approach a little bit.

First off, there is going to be some preliminary work that our subroutine only
needs to do once. This includes pushing some registers onto the stack. Since
inflating the stack infinitely is widely considered bad manners, we don't want to
include this in the recursive part of the function.

With our next revision we won't much code, but we can narrow down the structure
a bit more.

```
# a0 <- fib(n)
# Arguments: a0 = n
# Returns:   fib(n) in a0
FIB:
    # Save some registers to the stack.

    # Call the recursive helper routine, _R_FIB
    call         _R_FIB

    # Pop from the stack.

    ret

    # Helper subroutine.
    # Does the actual calculating, no stack manipulation.
    # a0 <- fib(a0)
    _R_FIB:
        # Calculate fib(n) into a0
        ret
```

`_R_FIB` has the same side effects as `FIB`, except it does not do any unnecessary
stack manipulation.

Also, we have added two important instructions here who's behavior is crucial to
understanding the later parts of the program.

- `call`: This instruction jumps to the given label and saves the next program
  count as the return address.
- `ret`: This instruction jumps to the return address.

The return address is stored in a named register (`ra`). Each time we use `call` we
are overwriting this register. Because of this, we need to make sure we are saving
the return address to the stack each time we `call` a subroutine.

Let's have this be our first real addition to our subroutine. Again, before we
`call _R_FIB` we need to save the return address. To do this we need to understand
the stack pointer. The stack pointer (`sp` in RISC-V) is another special register
that stores the memory address of the bottom of the stack. Loading from the address
in the stack pointer register is equivalent to popping from the stack.

Some architectures have built in instructions for pushing and popping, but RISC-V does
not. So we will implement this functionality with a combination of loads/stores and
addition/subtraction to the `sp` register.

Further looking at the C-version of our algorithm, you would deduce that we are
going to checking <=1 frequently. We can save an instruction by keeping this in a
saved register. This is one more register we need to save to the stack when our
subroutine is called.

```
FIB:
    addi    sp,  sp, -8    # Decrement by 8 because each register is 4 bytes.
    sw      s0,  0(sp)     # Push s0 to stack.
    sw      ra,  4(sp)     # Push return address to stack.

    call         _R_FIB

    lw      ra,  4(sp)     # Pop return address from stack.
    lw      s0,  0(sp)     # Pop s0 from stack.
    addi    sp, sp, 8      #

    ret

    _R_FIB:
        ret
```

We are beginning to see some of the overhead that goes into each function call.
Those pushes and pops can add up.

# Fleshing out the recursive helper

This sub-subroutine is going to be the potato stew of our program. About 75% of
our subroutine consists of assembly that corresponds to the line I pointed out
earlier. Restated here, that line is:

```c
return fib(n - 1) + fib(n - 2);
```

Before writing any more assembly, we can actually benefit from breaking this
apart into a few more lines of C. Something like this:

```c
temp1 = fib(n - 1);
result = fib(n - 2);
result += temp1;
return result;
```

This is less readable at a glance, but its corresponding assembly functionally
equivalent (and likely identical) to what we had before.

I write it like this because this allows us to glean the structure of our recursive
helper routine. It's now obvious that it should:

1. Calculate `fib(n - 1)` and hang on to it.
2. Calculate `fib(n - 2)`.
3. Add them together.
4. Return the result.

For the first two, we will leverage the abstractions that subroutines and functions
allow us to build.

We also should not forget to check for a base case.

Let's revisit some assembly. Here we are just looking at the recursive part. Keep
in mind, there are several issues with this still.

```
# a0 <- fib(n)
# Arguments: a0 = n
# Returns:   a0 = fib(n)
_R_FIB:
    # We need a base case that jumps to EXIT.

    # fib(n - 1)
    # Set a0 equal to n - 1.
    addi    a0,  a0, -1
    # We assume this puts fib(a0) in a0.
    call         _R_FIB

    # Hang on to fib(n - 1).
    mv      t0,  a0

    # fib(n - 2)
    # Set a0 equal to n - 2.
    # We can't actually do this since n - 1 was
    # overwritten with the return value from the
    # first _R_FIB call.
    # But, let's assume we get n - 1 back into
    # a0 somehow.
    # Set a0 equal to n - 2.
    addi    a0,  a0, -1
    call         _R_FIB

    # a0 <- fib(n - 1) + fib(n - 2)
    add     a0,  a0, t0

    EXIT: ret
```

Let's discuss the simplest issue first: the base case. For Fibonacci, this
is simply `fib(0) = 0` and `fib(1) = 1`.

If we load 2 into our saved register `s0` at the beginning of the subroutine,
we can use a branch-if-less-than instruction, i.e. `blt a0, s0, EXIT`.

The more troublesome issue is dealing with all the register interference that
the recursive calls will undoubtedly incur upon us.

Thinking back to the initial call of `_R_FIB` by the outer subroutine, we can
at least be sure that we need to push the return address onto the stack as
to not get lost.

For the `fib(n - 1)` call of `_R_FIB`, we should also save `a0` to the stack
so we can retrieve it and use its value for the `fib(n - 2)` call. Let's add
these instructions before the first call to save those values on the stack:

```
addi    sp,  sp, -8    #
sw      ra,  4(sp)     # Don't forget the return address or you will get lost.
sw      a0,  0(sp)     # Push to the stack, preparing for a function call.
```

After our `fib(n - 1)` call exits and we move the result to `t0`, we can start
popping from the stack.

```
lw      a0,  0(sp)     # Get a0 back by popping once from the stack.
addi    sp,  sp, 4     #
```

Also, we shouldn't pop the return address since we are about to make another
function call anyway.

For the second call we don't need to save `a0`; we are done with `n`. However,
there's one more thing we need to save. We just loaded a value into `t0`
and we are dependent on it staying there. If call `_R_FIB` again, it will
put _its own_ value into `t0`. We can't lose our value when that happens,
so we have to push it onto the stack. Combining the push and pop it looks
like this:

```
addi    sp,  sp, -4    #
sw      t0,  0(sp)     # Push t0 onto the stack.

call         _R_FIB    # fib(n-1) gets loaded into a0

lw      t0,  0(sp)     # Pop once for t0.
lw      ra,  4(sp)     # Once more for the return address.
addi    sp,  sp, 8
```

We are nearly done. We just need to add `fib(n - 1)` and `fib(n - 2)` together
and return.

We incorporate the add, base case, and loading 2 into the `s0` register to get
our finished subroutine.

```
# Arguments: a0: int = n
# Returns:   a0: int = fib(n)
# Summary:   a0 <- fib(a0)
FIB:
    # We only need two registers for this subroutine.
    addi    sp,  sp, -8    #
    sw      s0,  0(sp)     # Push s0 to stack.
    sw      ra,  4(sp)     # Push return address to stack.

    li      s0,  2         # 2 will be used for a conditional.

    # a0 <- fib(a0)
    call         _R_FIB    # Call recursive helper function.

    lw      ra,  4(sp)     # Pop return address from stack.
    lw      s0,  0(sp)     # Pop s0 from stack.
    addi    sp,  sp, 8     #

    ret

    _R_FIB:
        # This is the exit condition.
        # If a0 < 2, return a0.
        # fib(0) = 0 & fib(1) = 1
        blt     a0,  s0, EXIT

        # fib(n - 1)
        #############################################################################
        addi    a0,  a0, -1    # a0 <- a0 - 1

        addi    sp,  sp, -8    #
        sw      ra,  4(sp)     # Don't forget the return address or you will get lost.
        sw      a0,  0(sp)     # Push to the stack, preparing for a function call.

        call         _R_FIB    # fib(a0 - 1) gets loaded into a0.

        mv      t0,  a0        # Save result of fib(n-1) in t0, we need it later.

        lw      a0,  0(sp)     # Get a0 back by popping once from the stack.
        addi    sp,  sp, 4     #
        #############################################################################

        # Note: t0 contains fib(n-1) and a0 contains n-1.

        # fib(n - 2)
        #############################################################################
        addi    a0,  a0, -1    # a0 <- a0 - 1

        addi    sp,  sp, -4    #
        sw      t0,  0(sp)     # Push t0 onto the stack.

        call         _R_FIB    # fib(n-1) gets loaded into a0

        lw      t0,  0(sp)     # Pop once for t0.
        lw      ra,  4(sp)     # Once more for the return address.
        addi    sp,  sp, 8     #
        #############################################################################

        # At this point, a0 = fib(n-2) and t0 = fib(n-1)

        add     a0, a0, t0     #
        EXIT: ret              # return fib(n - 1) + fib(n - 2)
```

Not too bad when you break it down piece by piece. But, it certainly helps give
an appreciation for the amount of headache compilers save us.

# A look at the iterative version

Now that we've done this the hard way, let's take a look at the better approach.
Here is the same function but programmed iteratively.

```
# Arguments: a0: int = n
# Returns:   a0: int = fib(n)
# Summary:   a0 <- fib(a0)
FIB:
    addi    sp,  sp, -4    #
    sw      s0,  4(sp)     # Push s0 to the stack.

    li      s0,  s0, 2     # Constant used for comparisons.

    blt     a0,  s0, EXIT  # If n < 2, then fib(n) = n.

    li      t0,  1    # Initialize N.
    li      t1,  1    # fib(1) = 1
    li      t2,  0    # fib(0) = 0

    LOOP:
         addi,   t0,  t0, 1       # Increment counter.
         mv      t3,  t1          # Save fib(n-1) in temporary register.
         add     t1,  t1, t2      # fib(n-1)[next] <- fib(n-1)[curr] + fib(n-2)[curr]
         mv      t2,  t3          # fib(n-2)[next] <- fib(n-1)[curr]
         blt     t0,  a0, LOOP    # Loop again if counter < n.

    mv      a0,  t1    # Move fib(n-1)[next] = fib(n)[curr] into return register.
    EXIT:   ret        # Return.
```

It's more readable in my opinion. It has more going for
it than that, though.

- It has next to no memory accesses.
- It has fewer _static_ instructions (more on this in a second).
- It's not vulnerable to a stack overflow for large values of `n`.

It's difficult for me to come up with any advantages of the recursive
version other than it looks good in a high-level language. The most I can
say is that the difference in size is not as important as it seems at
first glance. Sure, the iterative version has fewer static instructions and
will therefore save you some space in your binary. But, as far as dynamic instructions
go, they'll be on the same order of magnitude.

What really hurts the recursive version is its excessive memory access. This is really
the key lesson to be learned from this exercise. This subroutine succinctly
demonstrates the overhead that is inherent to recursion and even function calls
in general. That's something to consider when writing recursive algorithms in the future.
Is your cache going to save you? Or will you suffer miss after miss, piling on 100s of
nanoseconds per call?
