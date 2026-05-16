# General Coding Principles & Best Practices

This document outlines language-agnostic software engineering principles and best practices.

## Core Principles

- SOLID: The five principles of OOP (Robert C. Martin, 2000)
- DRY: Do Not Repeat Yourself (Hunt & Thomas, _The Pragmatic Programmer_, 1999)
- KISS: Keep It Simple (Kelly Johnson, Lockheed Skunk Works, 1960s)
- YAGNI: You Are Not Going To Need It (Kent Beck, _Extreme Programming Explained_, 1999)
- Separation of Concerns (Dijkstra, "On the role of scientific thought", 1974)
- Unix Philosophy (Doug McIlroy, _Bell System Technical Journal_, 1978)

## Safety

The Power of 10: Rules for Developing Safety-Critical Code (NASA/JPL)

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

Secure code protects data and systems from unauthorised access, misuse, and exploitation.

- **Validation**: Define explicit trust boundaries and validate all input at these boundaries
- **Sanitisation**: Sanitise raw input data before use in SQL, HTML, and similar contexts
- **Secrets Management**: Never commit secrets to version control; use environment variables or vaults instead

## Design Patterns

Design patterns are proven solutions to recurring problems.
They improve code readability, maintainability, and scalability.

- Patterns are solutions to recurring problems; do not force them into unsuitable contexts
- Prefer the simplest solution; introduce patterns when complexity demands
- Name patterns in code (e.g., `UserFactory`, `PaymentStrategy`) for clarity

Standard design patterns:

- **Creational**: factory, abstract factory, builder, prototype, singleton
- **Structural**: adapter, bridge, composite, decorator, facade, flyweight, proxy
- **Behavioural**: chain of responsibility, command, iterator, mediator, memento, observer, state, strategy, template method, visitor

Reference: Gamma, Helm, Johnson, Vlissides, _Design Patterns: Elements of Reusable Object-Oriented Software_ (1994)

## Testing

Tests verify correctness, document behaviour, and enable safe refactoring.

- Tests should be fast, isolated, repeatable, self-validating, and timely (F.I.R.S.T.)
- Test behaviour, not implementation
- Tests are documentation—make them readable
- The Arrange-Act-Assert structure is recommended for clarity

## Additional Guidelines

- Composition over Inheritance
  - Inheritance creates tight coupling; composition allows flexibility
  - "Has-a" relationships are often more appropriate than "is-a"
  - Use interfaces/protocols for polymorphism without inheritance hierarchies
  - Prefer dependency injection to hard-coded dependencies for better testability and modularity
- Principle of Least Astonishment
  - Code should behave as users and developers expect
  - Function names should accurately describe what they do
  - Side effects should be obvious or eliminated
  - Follow established conventions of the language and framework
- Defensive Programming
  - Validate all inputs at system boundaries
  - Check preconditions at function entry
  - Assert invariants that should always hold
  - Fail promptly and explicitly rather than silently corrupting state
  - Never trust external data (user input, files, network, environment variables)
- Idempotency
  - Operations that can be safely retried should produce the same result
  - Critical for distributed systems, network requests, and database operations
  - Design APIs and functions to be idempotent where possible
  - Use unique identifiers to detect and prevent duplicates
- Naming
  - Names should be descriptive and reveal intent
  - Use consistent naming conventions within a codebase
  - Boolean variables and functions should read as yes/no questions (e.g., `is_valid`, `has_permission`)
  - Function names should be verb phrases (e.g., `calculate_total`, `send_email`)
  - Class names should be noun phrases (e.g., `User`, `PaymentProcessor`)
- Comments
  - Code should be self-documenting; comments explain _why_, not _what_
  - Keep comments accurate—wrong comments are worse than none

**Reference**: Robert C. Martin, _Clean Code: A Handbook of Agile Software Craftsmanship_ (2008)
