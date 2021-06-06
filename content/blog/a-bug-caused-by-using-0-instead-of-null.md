+++
title = "A Bug Caused by Using 0 Instead of Null"
date = "2015-09-08"
tags = ["c", "code"]
aliases = ["/blog/2015/09/08/a-bug-caused-by-using-0-instead-of-null/"]
+++

This is a quick post about a bug I ran into at work which turned out to be
caused by passing a literal `0` instead of `NULL` to a function. Here's a
small program reproducing it:

<!--more-->

```c
#include <stdarg.h>
#include <stdio.h>

void f(int arg, ...) {
  va_list args;
  va_start(args, arg);
  int *p;
  for (int i = 0; i < arg; ++i) {
    p = va_arg(args, int*);
  }
  if (p) {
    printf("p was non-null: %p\n", p);
  } else {
    printf("p was null\n");
  }
}

int main(void) {
  f(5, 0, 0, 0, 0, 0, 0);
  f(6, 0, 0, 0, 0, 0, 0);
  return 0;
}
```

Compiling this as a 64-bit program on an x86-64 processor with clang
and running it gives this output:

```bash
$ clang test.c
$ ./a.out
p was null
p was non-null: 0x7fff00000000
```

What is going on here?

First, what is this `f` function doing? It takes an integer argument,
followed by a variable number of arguments. It uses the first argument
to decide which of the variable arguments to look at (starting at 1),
and interprets it as a pointer value. Thus, if the call looked like this:

```c
f(3, 1, 2, 3, 4, 5);
```

Then `p` would take on the value `(int*)3`.

For the two calls in the program, I'm passing in 6 literal `0`s as the variable
arguments. The first call examines the 5th one, and the second the 6th one. In
the first case, `p` turns out be 0, as expected. But in the second case, it is
nonzero. How come?

There are two things going on.

1. In the [x86-64 calling convention][abi] (refer to section 3.2.3), up to six
integer arguments can be passed in registers. In the case of `f`, this
includes the fixed positional argument `arg`, and then up to 5 arguments. In
both calls I am passing six extra arguments, so the last one is passed on
the stack, instead of in a register.

2. In C, the literal `0` has type `int`, which is a 32-bit value. Thus, 32 bits
worth of zeros are placed on the stack at the call site. But when `f`
interprets the argument as a pointer, it reads 64 bits from the stack. The
first 32 bits are zeros, but the next 32 are garbage -- whatever happens to
be on the stack (which could happen to be all zeros, or it might not, as in
this case).

If the last argument was `NULL` instead of `0`, then 64 bits worth of zeros
would have been placed on the stack at the call site, since `NULL` is typically
defined as something like `((void*)0)`, which is an expression of pointer type.

I'm not sure how consistent this behavior is across platforms or compilers. In
particular, it seems that there exist ABIs where values passed as varargs are
automatically sign-extended to 64 bits -- so the program here would be fine.

I tend to avoid using varargs in C, unless I'm just wrapping `printf` or
something. They're not type-checked, which is already giving up a lot, and then
on 64-bit systems they can be pretty complicated to reason about. Here is an
[interesting article][varargs] about the implementation of varargs in the amd64
ABI.

[abi]: http://www.x86-64.org/documentation/abi.pdf
[varargs]: https://blog.nelhage.com/2010/10/amd64-and-va_arg/
