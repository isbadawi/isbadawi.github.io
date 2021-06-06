+++
title = "Read Only File in Writable Directory"
date = "2016-03-25"
tags = ["unix"]
aliases = ["/blog/2016/03/25/read-only-file-in-writable-directory/"]
+++

This is a small gotcha about file permissions I ran into recently.

<!--more-->

Let's say there is a file on which you don't have write permission:

```bash
$ ls -l file
-rw-r--r--  1 notyou  somegroup  68 25 Mar 21:12 file
```

You can't write to this file:

```bash
$ echo "some text" > file
bash: file: Permission denied
```

However, let's say this file is in a directory on which you do have write
permission (assuming here that you are in `somegroup`):

```bash
$ ls -ld .
drwxrwxr-x  2 notyou  somegroup  68 25 Mar 21:12 dir
```

Now even though you can't modify the file, write permission on the directory
lets you remove the file and write a new file in its place:

```bash
$ rm file
$ echo "some text" > file
```

Depending on the situation, this can be just as good. You don't even have to do
this manually --
[if you're using vim, then `:w!` will automatically do this if the file is not writable][vim-w!].

I encountered a system at work that would inspect the contents of certain files
to decide whether to allow certain dangerous operations. These files had
clearly defined owners that you were meant to get in touch with to ask for
approval -- if approval was granted, they would edit the relevant files for
you, so that you could go ahead and do what you needed to do. But since the
files were set up in this way -- read-only in a group-writable directory -- in
practice anyone could edit them, bypassing whatever restrictions were in place.

If you're relying on a file being read-only, be mindful of the permissions
set on any parent directories.

[vim-w!]: https://github.com/vim/vim/blob/1e7885abe8daa793fd9328d0fd6c456214cb467e/src/fileio.c#L4300-L4307
