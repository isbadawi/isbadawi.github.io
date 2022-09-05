+++
title = "Unintended Stopiteration in a Generator"
date = "2016-03-27"
tags = ["python", "code"]
aliases = ["/blog/2016/03/27/unintended-stopiteration-in-a-generator/"]
+++

*Update (2022-09-05): The issue described in this post was addressed by [PEP
479](https://peps.python.org/pep-0479/), which made it so that `StopIteration`
is automatically changed into a `RuntimeError` when raised inside a generator.
As of python 3.5 (which was already available when this post was written), it
was possible to opt into the new behavior with `from __future__ import
generator_stop`, and the default was changed in python 3.7.*

Sometimes, if I have a generator that I happen to know is non-empty, and I want
to get at the first element, I'll write code like this:

```python
output = next(f for f in os.listdir(dir) if f.endswith('.o'))
```

<!--more-->

In theory, the intended meaning of this code is something like this:

```python
outputs = [f for f in os.listdir(dir) if f.endswith('.o')]
assert len(outputs) > 0 # or maybe assert len(outputs) == 1
output = outputs[0]
```

These two pieces of code are similar, but differ in one important way -- if the
assumption is wrong (i.e. there is a bug in the program), then the second will
raise an `AssertionError`, while the first will raise a `StopIteration`
exception. If this code happens to be inside a generator, maybe like this:

```python
def outputs(dirs):
  for dir in dirs:
    yield next(f for f in os.listdir(dir) if f.endswith('.o'))
```

Then while an `AssertionError` would correctly bubble up to the caller, a
`StopIteration` exception would instead only prematurely signal that the
generator is exhausted, and it wouldn't be possible in general for the caller
to tell that something has gone wrong -- it's likely that the program would
just keep running and produce wrong results, making the bug potentially much
less straightforward to track down.

So while using `next` for this purpose is cute, its behavior in cases like this
might catch you off guard. If your intention is to communicate an assumption
you're making, you're probably better off using `assert`, even if it's slightly
more long-winded.
