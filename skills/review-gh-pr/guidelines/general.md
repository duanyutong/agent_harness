# General Guidelines

This document covers language-agnostic software engineering principles and best practices.

Code review should cover correctness, readability, maintainability, and more—from high-level design to low-level implementation details:

- Is it well-designed and well-structured? (e.g., modular, layered)
- Is it well-written and easy to read, with adequate documentation?
- Is it maintainable and extensible?
- Does it behave correctly?
- Does it follow standards and best practices?
- Does it have sufficient test coverage?

## Core Principles

- SOLID: The five principles of OOP (Robert C. Martin, 2000)
- DRY: Don't Repeat Yourself (Hunt & Thomas, _The Pragmatic Programmer_, 1999)
- KISS: Keep It Simple, Stupid (Kelly Johnson, Lockheed Skunk Works, 1960s)
- YAGNI: You Aren't Gonna Need It (Kent Beck, _Extreme Programming Explained_, 1999)
- Separation of Concerns (Dijkstra, "On the role of scientific thought", 1974)
- Unix Philosophy (Doug McIlroy, _Bell System Technical Journal_, 1978)

## Safety

### The Power of 10: Rules for Developing Safety-Critical Code (NASA/JPL)

1. Restrict to simple control flow—avoid `goto`, `setjmp`, or recursion
2. All loops should have a fixed upper bound
3. Do not use dynamic memory allocation after initialisation
4. Prefer focused functions (less than ~60 lines; fits on one screen)
5. Assertion density should average two per function
6. Declare data at the smallest possible scope
7. Check return values of all non-void functions; validate all parameters
8. Limit preprocessor use to file inclusion and simple macros
9. Limit pointer use; no more than one level of dereferencing
10. Compile with all warnings enabled; use static analysers; adopt a zero-warnings policy

Reference: Gerard J. Holzmann, _IEEE Computer_ (2006)

## Security

- Validate all input at trust boundaries
- Sanitise raw input data before use in SQL, HTML, etc.
- Never commit secrets to version control

## Design Patterns

- Use standard design patterns for maintainability, scalability, and readability
- Patterns are solutions to recurring problems—don't force-fit them
- Prefer the simplest solution; introduce patterns when complexity demands
- Name patterns in code (e.g., `UserFactory`, `PaymentStrategy`) for clarity

Standard design patterns:

- Creational: factory, abstract factory, builder, prototype, singleton
- Structural: adapter, bridge, composite, decorator, facade, flyweight, proxy
- Behavioural: chain of responsibility, command, iterator, mediator, memento, observer, state, strategy, template method, visitor

Reference: Gamma, Helm, Johnson, Vlissides, _Design Patterns: Elements of Reusable Object-Oriented Software_ (1994)

## Test Principles

- Tests should be fast, isolated, repeatable, self-validating, and timely (F.I.R.S.T.)
- Test behaviour, not implementation
- Tests are documentation—make them readable
- The Arrange-Act-Assert structure is recommended for clarity

## Additional Principles

- Composition over Inheritance
  - Inheritance creates tight coupling; composition allows flexibility
  - "Has-a" relationships are often more appropriate than "is-a"
  - Use interfaces/protocols for polymorphism without inheritance hierarchies
- Principle of Least Astonishment
  - Code should behave as users and developers expect
  - Function names should accurately describe what they do
  - Side effects should be obvious or eliminated
  - Follow established conventions of the language and framework
- Defensive Programming
  - Validate all inputs at system boundaries
  - Check preconditions at function entry
  - Assert invariants that should always hold
  - Fail fast and loud rather than silently corrupting state
  - Never trust external data (user input, files, network, environment variables)
- Idempotency
  - Operations that can be safely retried should produce the same result
  - Critical for distributed systems, network requests, and database operations
  - Design APIs and functions to be idempotent where possible
- Naming
  - Names should be descriptive and reveal intent
  - Use consistent naming conventions within a codebase
  - Boolean variables and functions should read as yes/no questions (e.g., `is_valid`, `has_permission`)
  - Function names should be verb phrases (e.g., `calculate_total`, `send_email`)
- Comments
  - Code should be self-documenting; comments explain _why_, not _what_
  - Keep comments accurate—wrong comments are worse than none
