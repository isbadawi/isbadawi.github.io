---
layout: post
title: 'My "hardest bug" story'
date: 2014-01-19 02:03
comments: true
categories: [code, google, gwt, bug]
---

It's common to be asked a question like "what's the hardest bug you've debugged?"
at job interviews in tech. This post is about the bug I usually describe.
Somehow I feel like every time I explain it I'm less and less confident that I
understand it completely, and so the hope is that by writing it out and
fact checking it I'll have a better handle on it. It's also kind of strange
and interesting.

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
with JUnit, and measure code coverage using [EMMA][emma], a popular open source Java coverage tool.

To enable this, even though GWT application code ran as JavaScript in a browser in production, it would be made
to run as Java bytecode in a JVM in some contexts. 

For example, although GWT did support [fancy JUnit integration][gwttestcase]
where the code would run as JavaScript against either an emulated browser or a real browser, this would make tests
run pretty slowly, and often wasn't actually necessary, as big chunks of testable code consist of relatively standalone
application logic. So unless tests relied on browser APIs or things like that, they could be run as plain Java against
plain JUnit, which was nice and quick.

Now EMMA works on JVM bytecode -- it instruments the class file, so that as it runs, it creates some files containing
coverage data, which is later picked up to produce coverage reports. There's no way around this -- it is strictly
a JVM bytecode tool. This means that in order to support coverage runs using EMMA, the GWT application has to
run as Java on a JVM, and not as JavaScript. (There exists a wiki page with [some notes on EMMA support][emmagwtwiki],
but it's not very enlightening).

Now there is one aspect to this that I'm unsure about, which that it seems like whatever magic GWT performs to
support EMMA is not done for emulated classes. The only thing I could find related to this is 
[this old thread from the Scala+GWT project][scalagwt], which also isn't very enlightening. 
In any case, this means that for coverage runs, not only
does the code run as Java in a JVM, but it uses the "real" versions of classes even if emulated classes exist.

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
