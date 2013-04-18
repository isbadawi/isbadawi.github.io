---
layout: post
title: "Writing a code coverage tool for Java"
date: 2013-04-17 22:11
comments: true
categories: [code, java, coverage]
---

Code coverage is a metric which measures roughly how much (and which parts)
of the source code of a program was exercised in a given execution of that
program (or more often, during the execution of a test suite for that
program). There exist many different flavors of coverage data, for example
describing which lines were executed, which statements were executed, which
functions were called, which branches or control flow paths were taken. In
this post, we'll walk through writing a simplistic coverage collection tool
for Java.

The typical way code coverage is measured is by taking the input program
and rewriting it so that as it executes, it records somewhere which parts
are executing. For simplicity, we'll focus on line coverage. For line
coverage, the rewritten code might maintain a little table in memory, mapping
class names and line numbers to booleans representing whether that line
in that class has been executed. As each statement is executed, the appropriate
entry in the table will be updated.

Here's a simple example, the standard hello world in Java:

```java An contrived example class.
package io.badawi.hello;

public class Hello {
  public static void main(String[] args) {
    System.out.println("hello, world");
  }
}
```

We'd like to rewrite this so that after it's done executing, it will have
produced a little coverage report in a text file, saying that line 5 was
executed. Of course, that's not enough information; we need to know not
just that line 5 was executed, but which lines could possibly have executed,
so that we can produce a metric (for example, a percentage).

Notice that even though there are seven lines in this file, we really only
care about line 5. Line 5 is the only executable line; the rest are noise.
If line 5 is executed, logically we should say 100% of the class was covered
(as opposed to 1/7, 14.28%). In general, when measuring code coverage, we'll
want to ignore things like package declarations, imports, blank lines,
comments and so on. So before we have the program start marking off lines
as executed, we have to make it start with an initial *baseline coverage*,
which will have an entry mapping to false for every executable line.

With that in mind, a coverage tool could transform the code into this:

```java The same class, primed for code coverage.
package io.badawi.hello;

import io.badawi.coverage.CoverageTracker;

public class Hello {
  public static void main(String[] args) {
    CoverageTracker.markExecutable("io.badawi.hello.Hello", 5);

    CoverageTracker.markExecuted("io.badawi.hello.Hello", 5);
    System.out.println("hello, world");

    CoverageTracker.writeCoverageToFile("coverage_report.txt");
  }
}
```

Straightforward, right? You start by listing off all the executable lines.
Then, after the line executes, you mark it as executed. Then, before the
program exits, you write out the coverage information somewhere.

The implementation of `CoverageTracker` could be as simple as this:

```java The coverage tracker.
package io.badawi.coverage;

import com.google.common.collect.Table;
import com.google.common.collect.HashBasedTable;

public class CoverageTracker {
  // Maps classnames and line numbers to true (executed) or false (not executed).
  private static Table<String, Integer, Boolean> coverage = HashBasedTable.create();

  // Serializes coverage in some format; we'll revisit this.
  public static void writeCoverageToFile(String filename) { }

  public static void markExecutable(String className, int line) {
    coverage.put(className, line, false);
  }

  public static void markExecuted(String className, int line) {
    coverage.put(className, line, true);
  }
}
```

Not too complicated. The rewriting process -- generating this code
automatically -- might be a bit involved, but conceptually what we're doing
should be easy to understand. Here's another contrived example, this time
with branching control flow:

```java The input class.
package io.badawi.hello;

public class HelloAgain {
  public static void main(String[] args) {
    if (1 < 2) {
      System.out.println("1 < 2");
    } else {
      System.out.println("1 >= 2");
    }
  }
}
```

```java The same class, instrumented.
package io.badawi.hello;

import io.badawi.coverage.CoverageTracker;

public class HelloAgain {
  public static void main(String[] args) {
    CoverageTracker.markExecutable("io.badawi.hello.HelloAgain", 5);
    CoverageTracker.markExecutable("io.badawi.hello.HelloAgain", 6);
    CoverageTracker.markExecutable("io.badawi.hello.HelloAgain", 8);

    CoverageTracker.markExecuted("io.badawi.hello.HelloAgain", 5);
    if (1 < 2) {
      CoverageTracker.markExecuted("io.badawi.hello.HelloAgain", 6); 
      System.out.println("1 < 2");
    } else {
      CoverageTracker.markExecuted("io.badawi.hello.HelloAgain", 8); 
      System.out.println("1 >= 2");
    }
    
    CoverageTracker.writeCoverageToFile("coverage_report.txt");
  }
}
```

Instrumenting code
------------------
