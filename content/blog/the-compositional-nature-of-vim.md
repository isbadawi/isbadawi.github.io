+++
title = "The Compositional Nature of Vim"
date = "2014-04-23"
tags = ["vim"]
aliases = ["/blog/2014/04/23/the-compositional-nature-of-vim/"]
+++

I use vim. I've used vim since I started programming; the very first program I
wrote -- hello world in C, following along a cprogramming.com tutorial -- was
typed out in vim, inside a cygwin environment on Windows. Naturally, at first
it was hard and intimidating. I didn't know how to do anything, least of all
edit text. I learned about insert mode and normal mode. I learned about
navigating using `hjkl`, and deleting the current line with `dd`, and saving
and quitting with `:wq`, and for a long time that was it.

<!-- more -->

Over time I learned more and more. I learned that I could copy the current line
with `yy`, and paste it somewhere with `p`. This meant that `yyp` duplicated
the current line! I learned that I could indent the current line with `>>`, and
also that I could indent the next 5 lines with `5>>`. I learned that `gg`
jumped to the top of the file. I learned that I could jump to line 34 with
`34G`. I also learned a strange incantation -- I could write `%s/foo/bar/g` to
replace all occurrences of `foo` with `bar` in the whole file. I used this all
the time, and vim felt really powerful!

I went on like this for *years*. What I'm trying to get at is that I never
really took the time to learn how vim worked. I had no clue about the big
picture. I didn't know any concepts. Even though I used vim for hours each day,
and I felt like I was constantly improving and learning new things, and my
peers in university thought me knowledgeable enough to come to me with their
vim questions, really I was just getting by on ad-hoc memorization.

I think this is actually not uncommon. There is this mystical aura around vim;
people have a tendency to think that becoming an effective vim user just means
memorizing enough arcane commands that eventually you'll just know which
incantation to type in to do what you want in any given situation. Want to copy
the whole file to the clipboard?  Easy -- it's `gg"*yG`, right? Yes, that's it.
I have it here in my notes -- "copy file to clipboard: `gg"*yG`". Copying the
next two paragraphs? Gee, I don't know, let me look that up -- ah, here. It's
`{"*y2}`. I'll just write that down and next time it comes up I'll know.

Some people are (rightly) turned off by this. Others -- like me -- take it in
stride and spend years memorizing opaque formulas like the above, motivated in
large part by the oft-touted idea that knowing vim inside and out will make you
orders of magnitude more productive (and in no small part by garden-variety
hipsterism). I know from experience that this approach can take you quite a long
way. It'll only take you so far though -- in the end it's as silly as learning
to speak English by trying to memorize all the possible sentences you can say,
without learning about verbs or nouns.

## Composition

The magic of vim is that it's comprised of lots of small primitives that
compose well together. Among these primitives are motions, operators, and text
objects.

### Motions

Pressing `l` moves your cursor one character to the right. Pressing `h` moves
it one character to the left. `j` moves it one character down, and `k` one
character up.

`w` moves it to start of the next word. `e` moves it to the end of the next
word. `b` moves it to the start of the previous word.

`$` moves it to the end of the current line, and `0` to the start of the
current line. `gg` moves it to the top of the file, and `G` to the bottom of
the file.  `{` moves it to the start of the paragraph, and `}` to the end of
the paragraph.

You can use `G` with a line number to jump to that line number.

The `t` and `f` motions move forward until a character. For instance, `tb`
moves forward until (but not including) the next occurrence of b. `fb` moves
forward until (and including) the next occurrence of b. Both of these have
uppercase versions that move backwards instead of forwards.

You can search forwards with `/regex`, and backwards with `?regex`. After
searching, you can use `n` to jump forwards to the next match, and `N` to jump
backwards to the last match.

Where it makes sense, the previous motions can be prefaced with a count. For
instance, `10j` moves down 10 lines instead of 1, and `3tg` moves forward
to the third occurrence of `g`.

Now it might seem like I'm just confirming the prejudice I was decrying
earlier. To a certain extent, these primitives are just things you should
commit to muscle memory. What you get in return is substantial, however.

### Operators

We just learned a bunch of motions. Now suppose we want to delete something,
instead of moving. There is only one new thing to learn: the `d` operator. `d`
stands for delete. What can you delete? Any motion, for one thing. `j` moves
down a line, so `dj` deletes down a line (that is, from the current position
until the same column on the next line). `gg` moves to the top of the file, so
`dgg` deletes to the top of the file. `/foo` jumps to the next occurrence of
`foo`, so `d/foo` deletes until the next occurrence of `foo`.

Another operator is `c`, which stands for change. `c` is like `d`, except that
it puts you in insert mode after. So `cj` behaves like `dj`, except that it
puts you in insert mode. Similarly `cgg` behaves like `dgg` and so on.

Another operator is `y`, which stands for yank. It copies things into
registers.  You can learn more about registers later; to start with, you can
just use `y` to yank things into the default register, and use `p` to put them
somewhere else. As with `c` and `d`, you can use `yj` to yank down a line,
`ygg` to yank to the top of the file, and so on.

Another operator is `gu`, which is used for lowercasing. `gu4j` lowercases four
lines down, `gugg` lowercases to the top of the file, `guG` lowercases to the
bottom of the file, and so on. There's also `gU` for uppercasing, `g~` for
swapping case and (strangely enough) `g?` for rot13 encoding.

Another operator is `>`, which handles indentation. You can use `>j` to indent
down a line, `>4k` to indent up four lines, `>gg` to indent to the top of the
file, `>}` to indent to the end of the paragraph, and so on. The `<` operator
is similar, only it dedents instead of indenting. These two are a little
different than the previous ones, since they operate on lines. For instance,
`>l` will indent the entire line.

Another operator is `gq`, which is used for formatting. The specifics are
configurable, but by default it reflows text so it's wrapped to `textwidth`
characters. This is useful if you're looking to use no more than 80 characters
per line, for instance. As before, you can use `gqgg` to reflow text to the top
of the file, `gqG` to reflow text to the bottom of file, `gq10k` to reflow ten
lines up, and so on.

The nice thing here is that each operator we learn about can be composed with
all the motions we know. Operators can also be used with these other things
called text objects.

### Text objects

Text objects are like motions in that they can be passed as arguments to
operators. They're not like motions in that they don't move you; instead, they
just refer to a region of text.

For example, the `_` text object refers to the current line. You can write `d_`
to delete the current line, `c_` to delete it and enter insert mode, `y_` to
yank it, `>_` to indent it, `gu_` to lowercase it, `gU_` to uppercase it, `g~_`
to toggle its case, `g?_` to rot13 encode it and so on. Since operating on the
current line is very common, repeating an operator is shorthand for applying it
on the current line.  For instance, `dd` does the same thing as `d_`, `cc` does
the same as `c_`, and so on.

Another text object is `iw`. If your cursor is within a word, then `iw` refers
to the whole word. You can write `diw` to delete the word under the cursor,
`ciw` to delete it and enter insert mode, `yiw` to yank it, `guiw` to lowercase
it, `gUiw` to uppercase it, `g~iw` to toggle its case, `g?iw` to rot13 encode
it and so on.

Another text object is `ip`. If your cursor is within a paragraph, then `ip`
refers to the whole paragraph. You can write `dip` to delete the paragraph
under the cursor, `cip` to delete it and enter insert mode, `yip` to yank it,
`guip` to lowercase it, `gUip` to uppercase it, `g~ip` to toggle its case,
`g?ip` to rot13 encode it, and so on. Personally, I find `gqip` very useful
when writing prose.

There are text objects that refer to regions of text between delimiters, which
can be very useful when editing code.  If your cursor is within a double quoted
string, then `i"` refers to the text between the quotes, and `a"` refers to the
same but also includes the quotes.  Similarly you have `i'` and `a'`, `i(` and
`a(`, `i[` and `a[`, `i{` and `a{`, `i<` and `a<`, and ``i` `` and ``a` ``. As
with the other text objects, you can use `d`, `c`, `y`, `gu`, `gU`, `g~`, and
any other operators you know.

## The power of composition

There's a combinatorial effect here. If I know about `o` operators, `m` motions
and `t` text objects, I can do up to `o * (m + t)` different things. Every new
operator I learn lets me do up to `m + t` new things, and every motion or text
object I learn lets me do up to `o` new things. Once you internalize vim's
language for editing text, then not only does editing text efficiently become
easier, but you also start learning at a much faster rate, as every new thing
you learn interacts with all the things you already know.

This doesn't just apply to the functionality built in to vim. There are many
ways in which one can extend vim through plugins. Assuming these plugins are
well behaved, then they too benefit from composing with everything else.

One can add new operators, for instance. An example is the
[commentary][commentary] plugin, which adds the `gc` operator to toggle
commenting lines. Since this is an operator, it can be used like `d` or
`c`; `gcc` comments the current line, `gc4j` comments four lines down, `gcgg`
comments to the top of the file, and so on.

One can also add new text objects. For example, the [textobj-rubyblock][]
plugin adds the `ar` and `ir` text objects to refer to the current ruby block,
or just its contents, respectively. This lets you write things like `dar` to
delete the entire block the cursor is in, or `<ir` to dedent its contents.

One can also add new motions. For example, the
[CamelCaseMotion][camelcasemotion] plugin defines camel-case analogues of the
`w`, `b`, and `e` motions, so that, for instance, you can jump to the start of
the next word in a camel-cased identifier. It also defines text objects
analogous to `iw` and so on for camel-cased words.

The interaction between plugins like these is what led me to a sort of aha
moment a while ago. At some point I'd installed commentary, and a while later
I'd installed textobj-rubyblock, never thinking of them together. One day, I
happened to want to comment out the contents of a ruby block, and intuitively I
reached for `gcir`. This wasn't something I'd learned. It certainly wasn't
documented anywhere that this would work; the two plugins had been written
independently by two different people. Not only did I not learn this, but I
didn't even explicitly think about it. This was just intuition -- since one of
the operators at my disposal is `gc`, and one of the text objects at my
disposal is `ir`, then `gcir` ought to work. And it did!

## Parting thoughts

While vim sports many more features than just normal mode editing like this
(and there are [many][vimcasts] [good][pvim] [resources][slj] for learning
about these), internalizing this idea of composing together many small text
editing primitives is one of the most important steps towards efficient vim
use, and is the main thing I try to impress upon beginning vim users whenever
the opportunity arises. Having this pointed out to me would certainly would
have saved me a lot of time, as many of the "tricks" that I learned piecemeal
during my first few years using vim were just instances of this sort of
composition.

[commentary]: https://github.com/tpope/vim-commentary
[camelcasemotion]: https://github.com/bkad/CamelCaseMotion
[textobj-rubyblock]: https://github.com/nelstrom/vim-textobj-rubyblock
[vimcasts]: http://vimcasts.org/
[pvim]: http://pragprog.com/book/dnvim/practical-vim
[slj]: http://learnvimscriptthehardway.stevelosh.com/
