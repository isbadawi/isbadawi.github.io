---
layout: post
title: "Writing a code coverage tool"
date: 2013-04-23 22:11
comments: true
categories: [code, java, coverage]
---
 
*Disclaimer: I'm not quite sure who the audience is for this. I guess it's
describing a little weekend project I put together, but it's also written kind of
like a tutorial, so you can maybe follow along. I don't think it's particularly
beginner-friendly, though. Some knowledge of Java is assumed, but not much.
The code is available [on github](https://github.com/isbadawi/coverage-example).*

                                       
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
executed. The rewritten class might look like this:

```java The same class, primed for code coverage.
package io.badawi.hello;

import io.badawi.coverage.runtime.CoverageTracker;

public class Hello {
  public static void main(String[] args) {
    System.out.println("hello, world");
    CoverageTracker.markExecuted("/path/to/Hello.java", 5);

    CoverageTracker.writeCoverageToFile();
  }
}
```

Straightforward, right?  After a line executes, you mark it as executed.
Then, before the program exits, you write out the coverage information somewhere.
The rewriting process -- generating this code automatically -- might be a
bit involved, but conceptually what we're doing should be easy to understand.

The implementation of `CoverageTracker` could be as simple as this.

```java The coverage tracker.
package io.badawi.coverage.runtime;

import java.util.Map;
import java.util.HashMap;

public class CoverageTracker {
  // Maps filenames and line numbers to true (executed) or false (not executed).
  private static Map<String, Map<Integer, Boolean> coverage =
      new HashMap<String, Map<Integer, Boolean>>();

  // Serializes coverage in some format; we'll revisit this.
  public static void writeCoverageToFile() { }

  public static void markExecuted(String filename, int line) {
    if (!coverage.contains(filename)) {
      coverage.put(filename, new HashMap<Integer, Boolean>());
    }
    coverage.get(filename).put(line, true);  
  }
}
```
 
(Note that although we'll use Guava in other parts of the code,
`CoverageTracker` is used by the instrumented code, and it might be
awkward to add a runtime dependency just to save a few lines of code.
This is why I'm using a `Map<String, Map<Integer, Boolean>>` instead
of a `Table<String, Integer, Boolean>`).

There is just a slight problem. In general, we can't really know ahead of time when or where
a program will terminate, so it won't do to just call `writeCoverageToFile` at the end of
`main`. The easiest way to ensure the coverage report is always generated to put the
call to `writeCoverageToFile` inside a JVM shutdown hook, so we can add this static initializer
block to `CoverageTracker`, and drop the calls in the instrumented code:

```java Write coverage to file on shutdown.
static {
  Runtime.getRuntime().addShutdownHook(new Thread() {
    @Override public void run() {
      writeCoverageToFile();
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

(All the `Visitor` classes have a generic type parameter; each `visit` method
takes an extra argument of that type, and the `accept` method also takes
a value of that type. I guess this can be useful to pass around state that is
built up during the traversal, but for complicated visitors I tend to use
a proper, non-anonymous class, and use member variables to keep state. So
here and in what follows I'll always use `Object` as the type parameter, pass
in `null` to `accept`, and ignore the extra argument.)

Now what we're looking to do is traverse the tree, find all the executable
statements and expressions, and insert our coverage tracking statements
after them.

This isn't as straightforward as it sounds, because if we do this naively
-- given a node in the tree, walk up its parents to find the statement
list containing it, and insert our coverage tracking statement after it
-- we'd be modifying lists of statements as we're iterating over them, which
causes trouble.

Javaparser already contains infrastructure to modify ASTs, in the form of a special
visitor implementation called `ModifierVisitorAdapter`, which has each `visit`
method return a `Node` to serve as the replacement for the current node. So we can replace an
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
    ASTHelper.addStmt(block, n);
    ASTHelper.addStmt(block, makeCoverageTrackingCall(filename, node.getBeginLine()));
    return block;
  }

  private Statement makeCoverageTrackingCall(String filename, int line) {
    NameExpr coverageTracker = ASTHelper.createNameExpr("io.badawi.coverage.runtime.CoverageTracker");
    MethodCallExpr call = new MethodCallExpr(coverageTracker, "markExecutable");
    ASTHelper.addArgument(call, new StringLiteralExpr(filename));
    ASTHelper.addArgument(call, new IntegerLiteralExpr(String.valueOf(line)));
    return new ExpressionStmt(call);
  }
}
```

* The key point here is that parsers retain information about the positions (line and column offsets)
of AST nodes, typically to generate useful error messages. The call to `node.getBeginLine()` returns
the line in the file where the code fragment corresponding to that node begins. 
* The path of the source file can't be known in general (because we could be parsing an arbitrary string, as we did above), so we
pass it in ourselves. 
* `makeCoverageTrackingCall` just creates a call to `markExecuted`, with the filename and line number
as arguments. Note that we insert the fully qualified name of `CoverageTracker` there instead of adding
an import; this wards against the case where the subject code is already using the name `CoverageTracker`.
* The `visit` method runs whenever the traversal encounters an expression statement
(for example, a standalone method call) and returns a block statement containing the original statement,
followed by the call to `markExecuted`.

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
             System.out.println("hello, world");
             io.badawi.coverage.runtime.CoverageTracker.markExecuted("/path/to/Hello.java", 5);
         }
     }
}

```

which is what we wanted.
  
Baseline coverage
-----------------

Let's go back to our hello world example for a bit. Notice that even though there are seven
lines in this file, we really only care about line 5. Line 5 is the only executable line;
the rest are noise.  If line 5 is executed, logically we should say 100% of the class was covered
(as opposed to 14.28%, or 1/7). It's not quite enough, then, to know that line
5 was executed; to produce an accurate coverage report, we have
to know also which lines *could* have been executed (in this case, only line 5).
In doing this, we'll want to ignore things like package declarations, imports,
blank lines, comments and so on. 

Given what we have so far, how do we do this? Which lines are executable?
It should be easy enough to see that the executable lines are precisely those lines for which
we've created a `markExecuted` call. We can reuse our `CoverageTracker` and just mark the line
as executable at that point:

```java Keep track of executable lines.
private Statement makeCoverageTrackingCall(String filename, int line) {
  CoverageTracker.markExecutable(filename, line);
  // same as before
}
```

where `markExecutable` is implemented the same way as `markExecuted`, only with `false`
instead of `true`:

```java Implementation of markExecutable.

public static void markExecutable(String filename, int line) {
  if (!coverage.contains(filename)) {
    coverage.put(filename, new HashMap<Integer, Boolean>());
  }
  coverage.get(filename).put(line, false);
}   
```

Then the coverage report will be generated via the same shutdown hook we added earlier (but
at instrumentation time, not a runtime).
 
Generating a coverage report
----------------------------

We're going to generate our report in lcov format. This format is
understood by tools like `lcov` and `genhtml`, which can use it to
spit out a nice HTML report where the source code is annotated
with colors that show which lines were executed.

The format isn't very complicated. It consists of a series of records,
one for each source file. Within each record, you specify which lines
were executed. You can also specify things like function and branch
coverage, but we won't use those features.

An lcov record for our hello world example might look like

```text An lcov record.
SF:/path/to/Hello.java
DA:3,1
end_of_record
```

The `SF` line signals the start of a new record for the source file
at the given path, and `end_of_record` (obviously) signals the end
of the record. For each executable line, a `DA` line specifies the
line number and the number of times that line was executed. In our case,
since we're only tracking whether a line was executed and not how many
times, we'll only ever put a 1 or 0 there. It wouldn't be difficult to
change the `CoverageTracker` implements to keep a count, though.

With that in mind, generating a coverage report is straightforward
and looks like this.

```java Generating the coverage report.
private static void writeCoverageToFile() {
  String lcovCoverage = generateLcov();
  String coverageReportPath = System.getProperty("coverage.report.path", "coverage_report.lcov");
  FileWriter writer = null;
  try {
    writer = new FileWriter(coverageReportPath);
    writer.write(lcovCoverage);
  } catch (IOException e) {
    throw new RuntimeException(e);
  } finally {
    try {
      writer.close();
    } catch (IOException e) {
      throw new RuntimeException(e);
    }
  }
}

private static String generateLcov() {
  StringBuilder sb = new StringBuilder();
  for (String filename : coverage.keySet()) {
    sb.append("SF:" + filename + "\n");
    for (Map.Entry<Integer, Boolean> line : coverage.get(filename).entrySet()) {
      sb.append(String.format("DA:%d,%d\n", line.getKey(), line.getValue() ? 1 : 0));
    }
    sb.append("end_of_record\n");
  }
  return sb.toString();
}
```

Note how we read the output path from the `coverage.report.path` property; this is
useful since we generate two reports, one during instrumentation and one during
execution.

(`writeCoverageToFile` is a bit awkward, again because I don't want
to use Guava in the runtime code. It could just be a call to
`Files.write`).

We're close to the payoff. We can change the `main` method of
`CoverageVisitor` to take a class as a command line argument
instead of hard coding in our `Hello` class. Since for now we're
assuming a single input class, we'll just print the instrumented
class to standard output and let the caller decide where to put it.

```java A proper main method.
public static void main(String[] args) throws IOException, ParseException {
    File file = new File(args[0]);
    CompilationUnit unit = JavaParser.parse(new FileReader(file));
    unit.accept(new CoverageVisitor(file.getAbsolutePath()), null);
    System.out.println(unit.toString());
}
```

Now we should be able to instrument, compile and execute a class,
and use `genhtml` to visualize the resulting coverage report. The
following assumes `CoverageVisitor` and `CoverageTracker` were compiled
and the class files are in a directory called `bin`:

```bash Putting it all together.
$ pwd
/Users/isbadawi/Documents/workspace/coverage-example
$ cat Hello.java
public class Hello {
  public static void main(String[] args) {
    System.out.println("hello, world");
  }
}
$ mkdir instrumented
$ java -cp bin -Dcoverage.report.path=instrumented/baseline_coverage.lcov \
       io.badawi.coverage.CoverageVisitor Hello.java > instrumented/Hello.java
$ cd instrumented
$ cat baseline_coverage.lcov
SF:/Users/isbadawi/Documents/workspace/coverage-example/Hello.java
DA:3,0
end_of_record      
$ cat Hello.java
public class Hello {

    public static void main(String[] args) {
        {
            System.out.println("hello, world");
            io.badawi.coverage.runtime.CoverageTracker.markExecuted("/Users/isbadawi/Documents/workspace/coverage-example/Hello.java", 3);
        }
    }
}
$ javac -cp .:../bin Hello.java && java -cp .:../bin Hello
hello, world
$ cat coverage_report.lcov
SF:/Users/isbadawi/Documents/workspace/coverage-example/Hello.java
DA:3,1
end_of_record
$ lcov -a baseline_coverage.lcov -a coverage_report.lcov -o combined_coverage.lcov
$ genhtml combined_coverage.lcov -o report
$ cd report && python -m SimpleHTTPServer
Serving HTTP on 0.0.0.0 port 8000 ...
```

We use the `lcov` command to merge together our baseline and runtime coverage
reports. (In this case, the runtime coverage report is enough, but in general
this step is necessary). Then we feed the merged report to `genhtml`, which
generates a little HTML report. `python -m SimpleHTTPServer` just serves up the
contents of the current directory on port 8000. Pointing your browser to
`localhost:8000` should then show a nice coverage report (which you can see
[here](/coverage-report) if you haven't been following along).

Handling everything
-------------------

Now that's we've got this running end-to-end as sort of proof of concept,
we can go back and tie up some loose ends. `CoverageVisitor` only instruments
expression statements, for simplicity and because that's the only kind of
statement the hello world example contained. We'd like to extend our approach
to handle everything.

If we worked at level of statements, we'd need to write code to handle all the different
kinds of statements -- if statements, for loops, while loops, throw statements,
assert statements, and so on. For each of these we'd need to come up with a
transformation that inserted coverage tracking calls in the right place. A simpler
solution would be to work with expressions, and try to come up with a single transformation
that works for all expressions.

One idea would be to take our `markExecuted` method and have it take an expression
as an argument and return its value, like this:

```java markExecuted as an expression
public static <T> T markExecuted(String filename, int line, T expression) {
  markExecuted(filename, line);
  return expression;
}
```

Then you could essentially wrap expressions in a call to `markExecuted`; the
expression would evaluate to the same value, and coverage would be tracked.
For instance, this:

```java An if statement.
if (1 < 2) {
  // ...
}
```

would become this:

```java The same if statement, instrumented.
if (CoverageTracker.markExecuted(/* file */, /* line */, 1 < 2)) {
  // ...
}
```

and the same transformation would apply for loop conditions, assertions,
and so on, without needing to write different cases for them.

There is just a small issue, which is that this won't work if the
expression has type `void`, since you can't pass
something of type `void` to a method. This turns out not to be a huge deal; we don't need
to perform any sort of type inference or anything like that. Expressions of type `void` can only
occur in two places: expression statements (like our call to `System.out.println`),
and for loop headers (in the initialization and increment sections). We can can just
handle those two cases separately, and we'll be fine.

We already took care of expression statements earlier, by inserting the coverage tracking
call afterwards, as a separate statement. We can use the same sort of idea to take care
of for loop headers. The initialization and increment sections include comma-separated
lists of expressions; when considering expressions there, we can insert our coverage
tracking call as the next element in the comma-separated list.

This should be good. Conceptually, it's simpler than handling every statement separately.
Unfortunately, the visitor machinery in javaparser doesn't seem to have a mechanism for
writing a single method that handles all kinds of expressions. The ugly, clumsy way
around this is to write an `visit` method for every different kind of expression, which
looks like this:

```java Instrumenting expressions.
@Override
public Node visit(ArrayAccessExpr n, Object arg) {
  return makeCoverageTrackingCall(n);
}

@Override
public Node visit(ArrayCreationExpr n, Object arg) {
  return makeCoverageTrackingCall(n);
}

// 20-something identical cases
```

I don't really like this, but conceptually it's still simpler than handling statements
separately. Even if we went the other way, we'd need to do this to properly handle assert and throw statements;
we couldn't insert a statement after, since it might not be executed.

[javaparser]: https://github.com/matozoid/javaparser
[visitor-wiki]: http://en.wikipedia.org/wiki/Visitor_pattern
