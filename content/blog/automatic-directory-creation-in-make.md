+++
title = "Automatic Directory Creation in Make"
date = "2017-03-28"
tags = ["code", "make"]
aliases = ["/blog/2017/03/28/automatic-directory-creation-in-make/"]
+++

I like out-of-tree builds. Out-of-tree builds are nice for lots of reasons. You
can have multiple builds of the same project coexisting side-by-side -- for
example a debug build for development, a release build, and an instrumented
build for code coverage runs. All the generated build artifacts are together
underneath one directory which you can easily delete without having to maintain
a `make clean` target, or place under `.gitignore` without having to maintain a
growing set of patterns for the different kinds of artifacts. I was going to
write a post about this, but came across
[this one by Jussi Pakkanen][out-of-tree builds] which covers a lot of the
ground I would have, so I'll just link to it here.

Instead, this post is about an issue that arises when implementing out-of-tree
builds in make, and the best approach I've found for dealing with it.

<!--more-->

Let's say we have a hypothetical source tree like
this with source files nested in different directories:

```
$ tree
.
├── foo
│   └── bar
│       └── baz.c
├── main.c
└── util
    └── log.c

3 directories, 3 files
```

We'd like our build directory to mirror this structure, like this:

```
$ tree build
build
├── foo
│   └── bar
│       └── baz.o
├── main.o
├── program
└── util
    └── log.o

3 directories, 4 files
```

The build system needs to ensure that each subdirectory within the build
directory exists before we compile the source files inside it. We'd like to
write our makefile to achieve this in a nice way that won't require too much
maintenance as our project grows. Here's a first attempt:

```makefile
BUILD_DIR := build

SRCS := main.c foo/bar/baz.c util/log.c
OBJS := $(addprefix $(BUILD_DIR)/,$(patsubst %.c,%.o,$(SRCS)))

.PHONY: program
program: $(BUILD_DIR)/program

$(BUILD_DIR)/%.o: src/%.c
	mkdir -p $(@D)
	$(CC) -c $< -o $@

$(BUILD_DIR)/program: $(OBJS)
	mkdir -p $(@D)
	$(CC) $^ -o $@

```

Here `$(@D)` is an [automatic variable][] which expands to the directory part
of the target path. If we run `make program`, we get this:

```bash
$ make program
mkdir -p build
cc -c src/main.c -o build/main.o
mkdir -p build/foo/bar
cc -c src/foo/bar/baz.c -o build/foo/bar/baz.o
mkdir -p build/util
cc -c src/util/log.c -o build/util/log.o
mkdir -p build
cc build/main.o build/foo/bar/baz.o build/util/log.o -o build/program
```

This does what we want, but it's a bit awkward. One issue is that in
incremental builds, the `mkdir` steps will be run again, even though the
directories definitely exist:

```bash
$ touch src/foo/bar/baz.c
$ make program
mkdir -p build/foo/bar
cc -c src/foo/bar/baz.c -o build/foo/bar/baz.o
mkdir -p build
cc build/main.o build/foo/bar/baz.o build/util/log.o -o build/program
```

For this reason, we should instead modify the rule for object files to specify
the target directory as a prerequisite. In particular, creating directories like
this is the typical use case for [order-only prerequisites][]. So we'd like to
write something like this:

```makefile
$(BUILD_DIR)/%.o: src/%.c | $(@D)
	$(CC) -c $< -o $@
```

One issue here is that automatic variables can't be used within prerequisite
lists, so that `$(@D)` will expand to nothing. That is easily fixed by enabling
[secondary expansion][], which is a feature of make whereby the prerequisite
list is expanded twice, and the second time around, automatic variables are in
scope. That looks like this:

```makefile
.SECONDEXPANSION:

$(BUILD_DIR)/%.o: src/%.c | $$(@D)
	$(CC) -c $< -o $@
```

We escape the `$(@D)` reference so that we expand it only during the second expansion.

The next issue with this approach is that there now need to be targets for each
directory that we'll need (`build`, `build/util`, and `build/foo/bar`). We definitely
don't want to write these out manually:

```makefile
$(BUILD_DIR):
	mkdir -p $@

$(BUILD_DIR)/util:
	mkdir -p $@

$(BUILD_DIR)/bar/baz:
	mkdir -p $@
```

One option is to define a template and evaluate it for each object file:

```makefile
define define_mkdir_target
$(1):
	mkdir -p $(1)
endef

$(foreach dir,$(sort $(dir $(OBJS))),$(eval $(call define_mkdir_target,$(dir))))
```

This is a bit hairy -- we call `$(dir $(OBJS))` to extract the directory part
of each object path, and then call `$(sort)` to filter out duplicates, because
we don't want to define multiple rules for the same directory if there are
multiple files in it. Then we evaluate the template for each directory we end
up with, defining a target for each.

This does everything we want and works correctly with incremental builds. It's
good enough for this toy example because we have this handy `$(OBJS)` variable
that has all of our targets in it, so we can do this once and forget about it.
In more complicated projects, we may have many different kinds of targets
defined in many different places, such that making sure we evaluate this
template for all of them is a maintenance burden.

What would be nicer is to define a [pattern rule][] in order to match any
directory. There isn't really a way to do this for real, but we can cheat a bit
by defining a naming convention; we'll make sure to always use a trailing slash
when referring to a directory. Then we can write this:

```makefile
.PRECIOUS: $(BUILD_DIR)/ $(BUILD_DIR)%/

$(BUILD_DIR)/:
	mkdir -p $@

$(BUILD_DIR)%/:
	mkdir -p $@

$(BUILD_DIR)/%.o: src/%.c | $$(@D)/
	$(CC) -c $< -o $@
```

We need both the first and second targets because the `%` in a pattern rule
won't match an empty string. And for reasons I don't fully understand, make
seems to treat the directories as intermediate files and tries to delete them
(unsuccessfully, since they're not empty) after the build is done, so we mark
both targets as `.PRECIOUS` to get around this. But that's all we ever need --
as we grow our project and add new build rules for different kinds of
artifacts, everything will work as expected as long as we specify `$$(@D)/` as
an order-only prerequisite for every target.

One last little snag is that this doesn't work in make 3.81. There, the
trailing slash in the prerequisite is apparently ignored, so our pattern rule
doesn't match. For [historical reasons][make-381-kernel], 3.81 was quite a
long-lived release of make and is the default version of make available in many
Linux distributions, as well as the version that ships with OS X, so we may
want to support it.

We can work around the make 3.81 behavior by changing our naming convention to
also include a trailing `.`. While this looks a bit funny, it doesn't change
the path being referred to, and make 3.81 won't strip it out. So our final
Makefile looks like this:

```makefile
BUILD_DIR := build

SRCS := main.c foo/bar/baz.c util/log.c
OBJS := $(addprefix $(BUILD_DIR)/,$(patsubst %.c,%.o,$(SRCS)))

.PHONY: program
program: $(BUILD_DIR)/program

.PRECIOUS: $(BUILD_DIR)/. $(BUILD_DIR)%/.

$(BUILD_DIR)/.:
	mkdir -p $@

$(BUILD_DIR)%/.:
	mkdir -p $@

.SECONDEXPANSION:

$(BUILD_DIR)/%.o: src/%.c | $$(@D)/.
	$(CC) -c $< -o $@

$(BUILD_DIR)/program: $(OBJS)
	$(CC) $^ -o $@

```

[out-of-tree builds]: http://voices.canonical.com/jussi.pakkanen/2013/04/16/why-you-should-consider-using-separate-build-directories/
[automatic variable]: https://www.gnu.org/software/make/manual/html_node/Automatic-Variables.html
[order-only prerequisites]: https://www.gnu.org/software/make/manual/html_node/Prerequisite-Types.html
[secondary expansion]: https://www.gnu.org/software/make/manual/html_node/Secondary-Expansion.html
[pattern rule]: https://www.gnu.org/software/make/manual/html_node/Pattern-Rules.html
[make-381-kernel]: https://savannah.gnu.org/bugs/index.php?33034
