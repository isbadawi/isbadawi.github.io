+++
title = "An Obscure Bug Story"
date = "2014-02-04"
tags = ["code", "google", "gwt"]
aliases = ["blog/2014/02/04/an-obscure-bug-story/"]
+++

It's common to be asked a question like "what's the hardest bug you've debugged?"
at job interviews in tech. This post is about the bug I usually describe.
The snag is that it's quite involved and I don't actually understand it all the
way through -- there are one or two aspects to it I often hand-wavingly gloss over.
The hope was that by writing it out and fact checking it I'd have a better handle
on it; this is what came out.

<!--more-->

This came up during my first internship at Google in 2012. I was on a team in
Ads, but I was mostly working on Google Web Toolkit, which was what many Ads
applications were written in. My project was to add support in the GWT compiler
for measuring code coverage from browser automation tests using WebDriver. This
has nothing to with the bug except that it also involved coverage runs and because
I had been messing with coverage stuff I'd been cc'd on the bug tracker and decided
to look into it.

The bug manifested like this. There was a team in Ads that had a GWT application
and a whole bunch of tests written against it. A single one of these tests had a
strange property: it would pass during regular test runs, but it would fail during
coverage runs. (In particular, there was an automatic nightly coverage run which
always showed up as failing because of this.)

So this was weird -- why would running a test for coverage change its outcome?

I don't remember what the test was actually testing, but modulo identifiers the
relevant bit looked something like this:

```java
@Test
public void testAllOptionsAreVisible() {
    ImmutableSet<Option> visibleOptions = methodContainingApplicationLogic();
    assertEquals(ImmutableSet.of(Option.values()), visibleOptions);
}
```

Here `ImmutableSet` refers to [this Guava collection][set-javadoc], and `Option` is some
enum defined by the application. In Java, all enums are automatically equipped with a
static `values()` method, which returns an array of all the values on that enum, and so
the intent here is to build a set containing all the enum values and compare that against
the set built up by the test's setup logic.

Digging through the error logs of the coverage run, the error looked liked this:

```
java.lang.AssertionError: expected:<[Lcom.google.ads.whatever.Option;@12345678> but was:<[FOO, BAR, BAZ]>
       at OptionsPageTest.testAllOptionsAreVisible(OptionsPageTest.java:42]
```

If you're a Java person, the problem is fairly obvious; the thing on the left (corresponding to the first argument
to `assertEquals`) is an `ImmutableSet<Option[]>` containing the result of calling `values()`,
instead of an `ImmutableSet<Option>` containing a copy of the array. If you look at the docs linked above,
you'll notice that `ImmutableSet` doesn't actually have
an `of(E[])` method, which means that it wouldn't copy the contents of the array. Instead the type inference
comes up with `ImmutableSet<Option[]>` and the method called is the `of(E)` method where `E = Option[]`.

So the fix was to use `copyOf` instead of `of`, and that's that. But now it seemed like the test shouldn't have
been passing in the first place, even during regular runs, since it was relying on this non-existent `of(E[])` method
that copies arrays. So what was going on really?

This requires a bit of background on GWT. GWT is a set of tools to write web apps, and its main premise is that
it's based on a Java to JavaScript compiler. You write apps in Java against a subset of the standard library, plus
a bunch of GWT-specific libraries, and the compiler takes in your Java source (not the compiled class files),
does a whole bunch of very aggressive optimizations, and spits out JavaScript.

Since the compiler takes in Java source code, it can't deal with native methods, which are common in the standard
library classes. It can also be useful to reimplement standard classes in such a way as to take advantage of
JavaScript features and browser APIs -- implementing `ArrayList` in terms of a JavaScript `Array`, for instance.
Given this, GWT has a notion of *emulated classes*; classes are reimplemented in GWT-friendly Java,
[a special directive][emul] can be passed to the GWT compiler to let it find the emulated source,
and the emulated classes are compiled to JavaScript alongside application code.
GWT includes emulated versions of [a subset of the standard library][jre-emul], and the abovementioned directive
is also available for applications or other libraries to use.

As it happens, one of these libraries was Guava -- several Guava collections, including `ImmutableSet`, have
emulated versions for use by GWT applications.

Switching gears slightly, one of the big selling points of GWT when it came out was that it was compatible with
a lot of popular Java tools -- you could step through your app using Eclipse's debugger, run tests
with JUnit, and measure code coverage using [Emma][emma], a popular open source Java coverage tool.

To enable this, even though GWT application code ran as JavaScript in a browser in production, it could also
be made to run as Java bytecode in a JVM in order to be more amenable to Java-based tools. Since the GWT compiler
has all the source, it can just forward it along to a Java compiler and execute the resulting
bytecode. There is just one snag, which is that GWT code can execute native JavaScript via GWT's
[JavaScript native interface (JSNI)][jsni] (either directly, or by calling into GWT libraries).
For those cases, GWT supports [fancy JUnit integration][gwttestcase] where the code still runs as Java,
except that a browser is brought up (either an emulated in-memory browser, or a real headless browser), native
JavaScript methods are injected into it, and those native methods have their bytecode rewritten so that they use
special wrappers that call the corresponding methods in the browser.

(As you might imagine, this is quite a bit slower -- it's often not necessary as big chunks of testable code
consist of relatively isolated application logic and can just run as plain Java instead of this hybrid mode.
GWT also supports a "web mode" when the tests run as full on JavaScript -- this is even slower, but is useful
to ward against possible behavior differences between Java and JavaScript.)

Now Emma is a coverage tool that works with JVM bytecode -- in a manner similar to what I described in [my last post][coverage-post],
it instruments class files, so that as they run, they create some files containing coverage data,
which are later picked up to produce coverage reports. GWT's Emma support is the aspect of this whole thing that I
understand least. (There exists a wiki page with [some notes on Emma support][emmagwtwiki], but it's not very enlightening).
It seems that whatever magic GWT needs to perform to play nice with Emma is not done for emulated classes.
The only thing I could find related to this is [this old thread from the Scala+GWT project][scalagwt],
which also isn't very enlightening, but seems to say that when Emma support was being developed it was decided that
emulated classes weren't worth supporting since, among other things, they weren't used much.
In any case, this means that for coverage runs, not only does the code run as Java in a JVM, but it runs against
the "real" versions of classes.

The final piece of the puzzle is that this mystery `ImmutableSet.of(E[])` method *used* to exist; you can browse
[an old version of the docs][oldset-javadoc] to see it. It was deprecated for a long time and eventually removed.
However, for whatever reason, the GWT-emulated version was not kept in sync with these changes. So the GWT-emulated
version still had that method, and this was why the regular test run, which ran against the emulated classes, passed.
The coverage run, which ran against the "real" Guava, failed.

[set-javadoc]: http://docs.guava-libraries.googlecode.com/git/javadoc/com/google/common/collect/ImmutableSet.html
[gwttestcase]: http://www.gwtproject.org/javadoc/latest/com/google/gwt/junit/client/GWTTestCase.html
[jre-emul]: http://www.gwtproject.org/doc/latest/RefJreEmulation.html
[emul]: http://code.google.com/p/google-web-toolkit-doc-1-5/wiki/DevGuideModuleXml#Overriding_one_package_implementation_with_another
[oldset-javadoc]: http://docs.guava-libraries.googlecode.com/git-history/v10.0/javadoc/com/google/common/collect/ImmutableSet.html
[emma]: http://emma.sourceforge.net/
[emmagwtwiki]: http://code.google.com/p/google-web-toolkit/wiki/EmmaSupport
[scalagwt]: https://groups.google.com/forum/#!msg/scalagwt/TE5O9hDTTd4/ENvpFnK2AkkJ
[jsni]: http://www.gwtproject.org/doc/latest/DevGuideCodingBasicsJSNI.html
[coverage-post]: /blog/2013/05/03/writing-a-code-coverage-tool
