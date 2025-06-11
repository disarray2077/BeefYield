# BeefYield

BeefYield is a proof-of-concept Beef library designed to transform a method's code into a yield state machine enumerator at compile-time. This allows you to write iterator-like methods using `YieldReturn!` and `YieldBreak!` mixins, similar to C#'s `yield return` and `yield break` statements. The library rewrites the annotated method into a state machine that can be iterated over, producing values one at a time.

## ⚠️ Disclaimer & Current Status ⚠️

BeefYield is currently **not under active development** and should be considered **experimental**.

*   **Incomplete Feature Coverage:** It may not support all Beef language features or complex control flow structures within yieldable methods.
*   **Limited Testing:** While basic tests exist (see `BeefYield.Tests`), the library has **not been thoroughly tested** against a wide range of complex scenarios.
*   **Known and Unknown Bugs:** You may run into object life-time issues, incorrect transformations, or other bugs.

You're welcome to try it out, just keep its current limitations in mind.

## Usage

### Making a Method Yieldable

To make a method behave like an iterator, you need to:
1.  Decorate it with the `[MakeYieldable(FilePath)]` attribute.
    *   `FilePath`: Currently, you must provide the absolute path to the source file containing the method. This is a temporary workaround. Ideally, this would use a compiler intrinsic like `Compiler.CalledFilePath`.
2.  Change the method's return type to `YieldEnumerator<T>`, where `T` is the type of items being yielded.
3.  Use the `YieldReturn!(value);` mixin to yield a value.
4.  Optionally, use the `YieldBreak!();` mixin to explicitly stop iteration.

Here's an example demonstrating how to create and use yieldable methods:

```bf
using System;
using BeefYield;
using System.Diagnostics;
using System.Collections;

namespace MyProject
{
    class MyIterators
    {
        // Replace with the actual path to this file in your project.
        const String FilePath = @"FULL_PATH_TO_THIS_SOURCE_FILE.bf";

        [MakeYieldable(FilePath)]
        public static YieldEnumerator<char8> GetCharacters(String str)
        {
#unwarn // This is necessary because the original code will no longer be reachable after the transformation
            Debug.WriteLine("GetCharacters: Start");

            // You can call other yieldable methods
            for (char8 res in FilterCharacters(str.RawChars, (c) => c != '.'))
            {
                Debug.WriteLine($"GetCharacters: Yielding '{res}'");
                YieldReturn!(res); // Yield the character
            }

            Debug.WriteLine("GetCharacters: End");
        }

        [MakeYieldable(FilePath)]
        public static YieldEnumerator<T> FilterCharacters<T, TEnum, TPred>(TEnum enumerator, TPred predicate)
            where TEnum : IEnumerator<T>
            where TPred : delegate bool(T a)
        {
#unwarn
            Debug.WriteLine("FilterCharacters: Start");
            for (T item in enumerator)
            {
                if (predicate(item))
                {
                    Debug.WriteLine($"FilterCharacters: Yielding item");
                    YieldReturn!(item);
                }
            }
            Debug.WriteLine("FilterCharacters: End");

            YieldBreak!(); // Explicitly stop iteration
            // Any code after YieldBreak!() will be unreachable
            Debug.WriteLine("This won't be reached");
        }

        public static void Main()
        {
            Console.WriteLine("Iterating through GetCharacters(\"B.e.e.f\"):");
            int count = 0;
            for (let charValue in GetCharacters("B.e.e.f"))
            {
                Console.WriteLine($"Main: Received '{charValue}'");
                count++;
            }
            Console.WriteLine($"Main: Total characters received: {count}"); // Expected: 4 (Beef)
        }
    }
}
```

## How It Works (High-Level)

The `[MakeYieldable]` attribute, combined with the `YieldReturn!` and `YieldBreak!` mixins, triggers a compile-time code transformation that converts sequential code into a state machine:

1. **Parsing:** The source code of the attributed method is parsed using the [`BeefParser`](https://github.com/disarray2077/BeefParser) library to build an Abstract Syntax Tree (AST).

2. **State Machine Generation:** The AST is analyzed and transformed into a state machine where:
   - `YieldReturn!(value);` statements become yield points that pause execution and return values
   - `YieldBreak!();` statements become iteration termination points
   - Control flow structures (loops, conditionals) are divided into separate states at each yield point
   - Local variables are moved to a context object that persists across state transitions

3. **Code Generation:** The transformed state machine replaces the original method, creating an enumerator that can pause and resume execution at any yield point while maintaining all local variable state.