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
So far so good, but how do we actually do this rewriting automatically?
We need a solution that will allow us to distinguish executable lines
from noise lines, and let us insert those method calls at the right
places.

The wrong way to do this is to use some complicated regex-based solution.
The right way to do this is to parse the code, and work with an
abstract syntax tree representation. That way, we can work at the level
of statements and expressions, and not the level of lines in a file, so
figuring out what's executable is trivial. To generate code, we can
transform the abstract syntax tree as we see fit and then pretty-print it
to a file.

Writing a parser for a language like Java is way outside the scope of this
blog post. Instead, we'll use a library. There are a few of these for most
languages; if not, you can probably find a parser generator and a complete
grammar. I'm going to use [javaparser][javaparser], mostly for simplicity;
it looks nice and standalone. The downsides are it only supports Java 1.5,
and it hasn't been updated in a while, so there might be trouble if we run
into issues. The documentation is also kind of scarce.

The hello world example for javaparser might look like this. It parses
a class (given here as a string), then calls `toString()` on the resulting
object to reconstruct a string out of it.

```java Parse a class and pretty-print it using javaparser.
package io.badawi.hello;

import japa.parser.JavaParser;
import japa.parser.ParseException;
import japa.parser.ast.CompilationUnit;

import java.io.StringReader;

public class HelloJavaparser {
  public static void main(String[] args) throws ParseException {
    CompilationUnit unit = JavaParser.parse(new StringReader(new StringBuilder()
        .append("package io.badawi.hello;\n\n")
        .append("public class Hello {\n")
        .append("  public static void main(String[] args) {\n")
        .append("    System.out.println(\"hello, world\");\n")
        .append("  }\n")
        .append("}\n").toString()));

    System.out.println(unit.toString());
  }
}
```

Running this just spits out the class declaration for `Hello`:

```
package io.badawi.hello;

public class Hello {

    public static void main(String[] args) {
        System.out.println("hello, world");
    }
}
```

Going slightly further, we'll change this example to add a statement
to the main method before getting the text back. We do this by creating
the AST fragment corresponding to the call, getting at the AST node
corresponding to the `main` method, and adding the newly constructed
statement to its body. It looks like this:

```java Modify the class a bit before generating code.
package io.badawi.hello;

import japa.parser.ASTHelper;
import japa.parser.JavaParser;
import japa.parser.ParseException;
import japa.parser.ast.CompilationUnit;
import japa.parser.ast.body.MethodDeclaration;
import japa.parser.ast.body.TypeDeclaration;
import japa.parser.ast.expr.MethodCallExpr;
import japa.parser.ast.expr.NameExpr;
import japa.parser.ast.expr.StringLiteralExpr;

import java.io.StringReader;

public class HelloJavaparser {
  public static void main(String[] args) throws ParseException {
    CompilationUnit unit = JavaParser.parse(new StringReader(new StringBuilder()
        .append("package io.badawi.hello;\n\n")
        .append("public class Hello {\n")
        .append("  public static void main(String[] args) {\n")
        .append("    System.out.println(\"hello, world\");\n")
        .append("  }\n")
        .append("}\n").toString()));
              
    // Create an AST fragment representing System.out.println("hello, javaparser")
    NameExpr systemOut = ASTHelper.createNameExpr("System.out");
    MethodCallExpr call = new MethodCallExpr(systemOut, "println");
    ASTHelper.addArgument(call, new StringLiteralExpr("hello, javaparser"));
                              
    // Add this statement to the main method
    TypeDeclaration helloClass = unit.getTypes().get(0);
    MethodDeclaration mainMethod = (MethodDeclaration) hello.getMembers().get(0);
    ASTHelper.addStmt(mainMethod.getBody(), call);

    System.out.println(unit.toString());
  }
}
```

Running this spits out the following class:

```
package io.badawi.hello;

public class Hello {

    public static void main(String[] args) {
        System.out.println("hello, world");
        System.out.println("hello, javaparser");
    }
}
``` 

which is what we wanted.

[javaparser]: https://code.google.com/p/javaparser
