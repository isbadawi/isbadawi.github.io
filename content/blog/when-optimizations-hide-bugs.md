+++
title = "When Optimizations Hide Bugs"
date = "2015-09-07"
tags = ["c", "code", "compilers"]
aliases = ["/blog/2015/09/07/when-optimizations-hide-bugs/"]
+++

The past few months at work I've been working with a large legacy codebase,
mostly written in C. In order to debug problems as they come up, I wanted to
use gdb -- but it seemed like the program was only ever compiled with
optimizations turned on (`-O2`), which can make using gdb a frustrating
experience, as every interesting value you might want to examine has been
optimized out.

After grappling with the build system to pass `-O0` in all the right places (a
surprisingly difficult task), I found that the program did not link with
optimizations turned off. Once I got around that, I ran into a crash in some
basic functionality, easily reproducible at `-O0`, but not `-O2`. This post
contains two tiny contrived programs reproducing those issues.

<!--more-->

## Optimizing away a reference to an undefined variable

As I mentioned, although the program compiled at `-O0`, it did not link. Here's
a small program that reproduces this. This program is totally contrived, but it
should hopefully not be too difficult to imagine seeing something like this in
real code.

There are three files involved here.

```c foo.h
#pragma once

extern int foo_global;

static inline int use_foo_global(void) {
  return foo_global;
}
```

```c foo.c
#include "foo.h"

int foo_global = 10;
```

```c main.c
#include "foo.h"

int ok_to_use_foo(void) {
  return 0;
}

int main(void) {
  if (ok_to_use_foo()) {
    return use_foo_global();
  }
  return 0;
}
```

`main.c` includes `foo.h`, which contains a `static inline` function which
references a global variable which is defined in `foo.c`.

Here's the thing, though -- although `main.c` includes `foo.h`, it is actually
not linked with `foo.c`. It is built on its own. (In the real code, this
`foo.c` was sometimes included in the build and sometimes not, depending on
which variant of the program you were building.)

When I compile this with clang without optimizations, I predictably get this
undefined reference error:

```bash
$ clang main.c
Undefined symbols for architecture x86_64:
  "_foo_global", referenced from:
      _use_foo_global in test-11ddda.o
ld: symbol(s) not found for architecture x86_64
clang-3.6: error: linker command failed with exit code 1 (use -v to see invocation)
```

The program references `foo_global`, but `foo_global` is defined in `foo.c`
which is not linked into the program.

Of course, if you look closely, you'll see that the program actually never ends
up using `foo_global` at runtime, based on some simple logic which is
actually constant, but since it includes a function call, clang won't figure
out at `-O0` that it is constant. (In the real code, this `ok_to_use_foo`
function contained logic involving a few different preprocessor variables, but
it was still ultimately constant).

At `-O2`, clang will easily figure out that the conditional is always false, so
it will optimize away the branch, which included the only call to that inline
function, so the function will be optimized away entirely also, taking with it
the reference to `foo_global`. Thus the program compiles cleanly and does what
you'd expect:

```bash
$ clang -O2 main.c
$ ./a.out
$ echo $?
0
```

## Optimizing away a corrupted stack variable

Consider this small program:

```c
#include <stdio.h>

static void obtain_two_pointers(void **a, void **b) {
  *a = &a;
  *b = &b;
}

int main(void) {
  void *c;
  int b;
  void *a;

  c = &b;
  printf("%c: %p\n", c);
  obtain_two_pointers(&a, &b);
  printf("%c: %p\n", c);
  return 0;
}
```

In this contrived program, `obtain_two_pointers` returns two pointers via
output parameters. The calling code only cares about the first, so it passes in
the address of a dummy local variable `b` to hold the second one.

When I compile this program with clang without optimizations and run it, I get this:

```bash
$ clang foo.c
foo.c:14:24: warning: incompatible pointer types passing 'int *' to parameter of type 'void **'
      [-Wincompatible-pointer-types]
  obtain_two_pointers(&a, &b);
                       ^~
foo.c:3:47: note: passing argument to parameter 'b' here
static void obtain_two_pointers(void **a, void **b) {
                                              ^
1 warning generated.
$ ./a.out
c: 0x7fff5118947c
c: 0x7fff00007fff
```

The problem is that the code was written assuming that pointers were 32 bits
wide, so that you could fit a pointer inside an `int` variable. On my machine,
however, pointers are 64 bits wide, so that when `obtain_two_pointers` writes
64 bits into the address of `b`, it corrupts the value of `c`, which is next to
it on `main`'s stack. This explains the output: after calling the function, the
lower 32 bits of `c` are overwritten with the beginning of a pointer value. If
we were to dereference `c` at this point, the program might crash.

Incidentally, the warning clang gives here is totally on-point, but this being
a huge legacy codebase, clang actually generates thousands of warnings, so this
one went unnoticed. While there are efforts underway to go through and address
all the warnings, it will probably take years before the program compiles
cleanly.

Now let's compile and run this program with optimizations turned on:

```bash
$ clang -w -O2 foo.c
$ ./a.out
c: 0x7fff5c9f9470
c: 0x7fff5c9f9470
```

What happens here is that `c` gets optimized out, and the address of `b` is
passed to the two `printf` invocations directly. There is still an extra 32
bits written onto the stack, but they're harmless. (Actually in this case the
call to `obtain_two_pointers` gets inlined so it's not quite that simple. If
the function is declared `extern` and defined in another file, like it was in
the real code, then it's easy to see that `c` is just optimized out.)

## Lessons learned

* Optimizations are behavior preserving, but not undefined behavior preserving.
In the second program, the implicit cast from `int*` to `void**` when `&b` is
passed to the function is undefined behavior. That's why optimizing out `c`
is a valid transformation even though it changes the behavior of the program.
(I think.)

* Being conscientious about compiler warnings can pay off. I've encountered
people who say that compiler warnings are more trouble than they're worth,
because the issues they find are either false positives, or trivial bugs that
anyone would see. It is true that the bug in the second program is not hard
to see -- if anyone had had cause to read through that part of the code, they
would have likely spotted it immediately. Unfortunately, in very large
codebases, a lot of code is left to rot, only examined if it appears in the
stack trace of a core file after a crash; at least, that's how I found this
bug. But the compiler always reads all of the code, so if nothing else it can
help find these trivial bugs in rarely-read code.
