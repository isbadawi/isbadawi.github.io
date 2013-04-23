---
layout: post
title: "Writing a code coverage tool"
date: 2013-04-23 22:11
comments: true
categories: [code, java, coverage]
---

Code coverage measures roughly how much, and which parts, of the source code
of a program were exercised in a given execution of that program 
(or more often, during the execution of a test suite for that
program). There are many different flavors of coverage data, for example
describing which lines were executed, which statements were executed, which
functions were called, which branches or control flow paths were taken. In
this post, we'll walk through writing a simplistic coverage collection tool
for Java.

The typical way code coverage is measured is by taking the input program
and rewriting it so that as it executes, it records somewhere which parts
are executing. For simplicity, we'll focus on line coverage. For line
coverage, the rewritten code might maintain a little table in memory, mapping
file names and line numbers to booleans representing whether that line
in that file has been executed. As each statement is executed, the appropriate
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
executed. 

Notice that even though there are seven lines in this file, we really only
care about line 5. Line 5 is the only executable line; the rest are noise.
If line 5 is executed, logically we should say 100% of the class was covered
(as opposed to 14.28%, or 1/7). In general, when measuring code coverage, we'll
want to ignore things like package declarations, imports, blank lines,
comments and so on. So before we have the program start marking off lines
as executed, we have to make it start with an initial *baseline coverage*,
which will have an entry mapping to false for every executable line.

With that in mind, a coverage tool could transform the code into this:

```java The same class, primed for code coverage.
package io.badawi.hello;

import io.badawi.coverage.runtime.CoverageTracker;

public class Hello {
  public static void main(String[] args) {
    CoverageTracker.markExecutable("/path/to/Hello.java", 5);

    System.out.println("hello, world");
    CoverageTracker.markExecuted("/path/to/Hello.java", 5);

    CoverageTracker.writeCoverageToFile("coverage_report.txt");
  }
}
```

Straightforward, right? You start by listing off all the executable lines.
Then, after the line executes, you mark it as executed. Then, before the
program exits, you write out the coverage information somewhere.
The rewriting process -- generating this code automatically -- might be a
bit involved, but conceptually what we're doing should be easy to understand.
Here's another contrived example, this time with branching control flow:

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

import io.badawi.coverage.runtime.CoverageTracker;

public class HelloAgain {
  public static void main(String[] args) {
    CoverageTracker.markExecutable("/path/to/HelloAgain.java", 5);
    CoverageTracker.markExecutable("/path/to/HelloAgain.java", 6);
    CoverageTracker.markExecutable("/path/to/HelloAgain.java", 8);

    if (1 < 2) {
      CoverageTracker.markExecuted("/path/to/HelloAgain.java", 5);

      System.out.println("1 < 2");
      CoverageTracker.markExecuted("/path/to/HelloAgain.java", 6); 
    } else {
      System.out.println("1 >= 2");
      CoverageTracker.markExecuted("/path/to/HelloAgain.java", 8); 
    }
    
    CoverageTracker.writeCoverageToFile("coverage_report.txt");
  }
}
```
 
The implementation of `CoverageTracker` could be as simple as this:

```java The coverage tracker.
package io.badawi.coverage.runtime;

import com.google.common.collect.Table;
import com.google.common.collect.HashBasedTable;

public class CoverageTracker {
  // Maps filenames and line numbers to true (executed) or false (not executed).
  private static Table<String, Integer, Boolean> coverage = HashBasedTable.create();

  // Serializes coverage in some format; we'll revisit this.
  public static void writeCoverageToFile(String filename) { }

  public static void markExecutable(String filename, int line) {
    coverage.put(filename, line, false);
  }

  public static void markExecuted(String filename, int line) {
    coverage.put(filename, line, true);
  }
}
```

Just a slight hiccup. In general, we can't really know ahead of time when or where
a program will terminate, so it won't do to just call `writeCoverageToFile` at the end of
`main`. The easiest way to ensure the coverage report is always generated to put the
call to `writeCoverageToFile` inside a JVM shutdown hook, so we can add this static initializer
block to `CoverageTracker`:

```java Write coverage to file on shutdown.
static {
  Runtime.getRuntime().addShutdownHook(new Thread() {
    @Override public void run() {
      writeCoverageToFile("coverage_report.txt");
    }
  });
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
it looks nice and standalone. The main downside is it only supports Java 1.5.
The documentation is also kind of scarce.

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

```text The output.
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

// snip imports

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

```text The output.
package io.badawi.hello;

public class Hello {

    public static void main(String[] args) {
        System.out.println("hello, world");
        System.out.println("hello, javaparser");
    }
}
``` 

which is what we wanted.

Okay, so now we know how to parse a class, make modifications to it, and get
back source code for the modified class. The last piece of the puzzle is
traversing the AST. For this javaparser has the AST nodes implement
[the Visitor pattern][visitor-wiki]; we can implement a Visitor interface that
has methods for all the different nodes we're interested in, and all the AST nodes
have an `accept` method that takes care of the dispatching. For example, we
could replace the `System.out.println(unit.toString());` at the end of the last
example with this:

```java Method call visitor.
unit.accept(new VoidVisitorAdapter<Object>() {
  @Override public void visit(MethodCallExpr node, Object arg) {
    System.out.println("found method call: " + node.toString());
  }
}, null);
```

and the output would be

```text The output.
found method call: System.out.println("hello, world")
found method call: System.out.println("hello, javaparser")
```

All the `Visitor` classes have a generic type parameter; each `visit` method
takes an extra argument of that type, and the `accept` method also takes
a value of that type. I guess this can be useful to pass around state that is
built up during the traversal, but for complicated visitors I tend to use
a proper, non-anonymous class, and use member variables to keep state. So
here and in what follows I'll always use `Object` as the type parameter, pass
in `null` to `accept`, and ignore the extra argument.

Now what we're looking to do is traverse the tree, find all the executable
statements and expressions, and insert our coverage tracking statements
after them.

This isn't as straightforward as it sounds, because if we do this naively
-- given a node in the tree, walk up its parents to find the statement
list containing it, and insert our coverage tracking statement after it
-- we'd be modifying lists of statements as we're iterating over them, which
causes trouble.

Javaparser already contains infrastructure -- a special visitor implementation
called `ModifierVisitorAdapter`, which has each `visit` method return a `Node`
to serve as the replacement for the current node. So we can replace an
arbitrary node with another. We can also use this to emulate inserting a statement
after the current statement; just replace the statement with a block statement
containing it and its new successor.

Given this, here's a first go at instrumenting our hello world example:

```java A first go at instrumenting code.
package io.badawi.coverage;

// snip imports

public class CoverageVisitor extends ModifierVisitorAdapter<Object> {
  // AST nodes don't know which file they come from, so we'll pass the information in
  private String filename;

  public CoverageVisitor(String filename) {
    this.filename = filename;
  }

  @Override
  public Node visit(ExpressionStmt node, Object arg) {
    BlockStmt block = new BlockStmt();
    ASTHelper.addStmt(block, makeCoverageTrackingCall("markExecuted", filename, node.getBeginLine()));
    ASTHelper.addStmt(block, n);
    return block;
  }

  private Statement makeCoverageTrackingCall(String methodName, String filename, int line) {
    NameExpr coverageTracker = ASTHelper.createNameExpr("io.badawi.coverage.runtime.CoverageTracker");
    MethodCallExpr call = new MethodCallExpr(coverageTracker, methodName);
    ASTHelper.addArgument(call, new StringLiteralExpr(filename));
    ASTHelper.addArgument(call, new IntegerLiteralExpr(String.valueOf(line)));
    return new ExpressionStmt(call);
  }
}
```

`makeCoverageTrackingCall` just creates a call to `markExecuted`. We insert the fully qualified name
of `CoverageTracker` there instead of adding an import; this wards against the case where the
subject code uses the name `CoverageTracker`. As arguments, we pass in the file name, and the line
number of the node in question. Parsers typically retain information about the positions of nodes
in order to generate useful error messages. This is what `node.getBeginLine()` does.

The interesting part is the `visit` method. When the traversal encounters an expression statement
(like a method call as a statement), it replaces it with a block statement containing the call
to `markExecuted`, followed by the original statement.

We can equip this class with a `main` method similar to our previous examples:

```java The main method.
public static void main(String[] args) throws ParseException {
  CompilationUnit unit = JavaParser.parse(new StringReader(new StringBuilder()
      .append("package io.badawi.hello;\n\n")
      .append("public class Hello {\n")
      .append("  public static void main(String[] args) {\n")
      .append("    System.out.println(\"hello, world\");\n")
      .append("  }\n")
      .append("}\n").toString()));

  unit.accept(new CoverageVisitor("/path/to/Hello.java"), null);

  System.out.println(unit.toString());
}
```

Running this prints out

```text The output.
package io.badawi.hello;

public class Hello {

     public static void main(String[] args) {
         {
             io.badawi.coverage.runtime.CoverageTracker.markExecuted("/path/to/Hello.java", 5);
             System.out.println("hello, world");
         }
     }
}

```

This is close to what we want. The only thing missing is the preamble where we call
`markExecutable` for each executable line. We can easily figure out which lines are
executable here; whenever we create a call to `markExecuted`, there should be a corresponding
call to `markExecutable` in the preamble. We can add a new field to the class and maintain it,
like this:

```java Keep track of executable lines.
private Multimap<String, Integer> executableLines = HashBasedTable.create();

private Statement makeCoverageTrackingCall(int line) {
  executableLines.put(filename, line);
  // same as before
}
```
 
Then we can add the preamble to the main method when we're done. In general
we won't know ahead of time which method in the main method, so we'll also
find it along the way, like this:

```java Add preamble to main method.
private boolean isMainMethod(MethodDeclaration method) {
  return ModifierSet.isPublic(method.getModifiers())
      && ModifierSet.isStatic(method.getModifiers())
      && method.getType() instanceof VoidType
      && method.getName().equals("main")
      && method.getParameters() != null
      && method.getParameters().size() == 1
      && method.getParameters().get(0).getType().equals(
      ASTHelper.createReferenceType("String", 1));
}  

private MethodDeclaration mainMethod;

@Override
public Node visit(MethodDeclaration node, Object arg) {
  if (isMainMethod(node)) {
    mainMethod = node;
  }
  return super.visit(node);
}

@Override
public Node visit(CompilationUnit node, Object arg) {
  Node result = super.visit(node);
  addPreamble(mainMethod);
  return result;
}

private void addPreamble(MethodDeclaration method) {
  List<Statement> body = mainMethod.getBody().getStmts();
  for (String filename : executableLines.keySet()) {
    for (Integer line : executableLines.get(filename)) {
      body.add(0, makeCoverageTrackingCall("markExecutableLine", filename, line);
    }
  } 
}
```

The `isMainMethod` method just checks the given method declaration against the expected signature
of the `main` method, i.e. that it's public, static, returns `void`, is named `main`, and has a
single argument of type `String[]`. (Javaparser calls array types reference types, for some reason.
The usual reference types are called "class or interface types").

When we visit a `MethodDeclaration`, we just check whether it's `main`, and if so remember it. Then, once we're done,
which is after visiting the entire `CompilationUnit`, we add the preamble to the main method. This just means iterating
over the executable lines and creating a call for each one, using the same `makeCoverageTrackingCall` method as before.

Running the main method now spits out:

```text The output.
package io.badawi.hello;

public class Hello {

    public static void main(String[] args) {
        io.badawi.coverage.runtime.CoverageTracker.markExecutable("/path/to/Hello.java", 5);
        {
            io.badawi.coverage.runtime.CoverageTracker.markExecuted("/path/to/Hello.java", 5);
            System.out.println("hello, world");
        }
    }
}
```

which is what we wanted.

We're not quite done, though, for a couple of reasons:

* we only handle expression statements. We wouldn't be able to handle our
second example with the if-else statement, for example.
* we are kind of assuming there is only compilation unit, which won't be
true in general.

But before we address these though, let's get to the format of the coverage report,
and what we can do with it.

Generating a coverage report
----------------------------

[javaparser]: https://github.com/matozoid/javaparser
[visitor-wiki]: http://en.wikipedia.org/wiki/Visitor_pattern
