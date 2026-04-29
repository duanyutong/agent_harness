# Code Review Guidelines

This document provides guidance for conducting effective code reviews.

For principles and best practices, see [general.md](./general.md).

## What to Look For

1. **Correctness** — Does the code do what it claims? Are edge cases handled?
2. **Design** — Is it well-structured? (modular, layered, separation of concerns)
3. **Readability** — Is it easy to understand, with adequate documentation?
4. **Maintainability** — Can future developers modify this safely and extend it?
5. **Standards** — Does it follow best practices and conventions?
6. **Testing** — Are tests comprehensive and cover important cases?

## Providing Feedback

- Be clear, grounded, and constructive
- Include disposition for each comment to distinguish blocking issues from nonblocking ones
- Ask questions when intent is unclear rather than assuming

## Code Review Checklist

When reviewing or writing code, verify:

- [ ] Code follows all principles in [general.md](./general.md) and applicable adjacent language-specific guidelines
- [ ] Design is sound; responsibilities are clearly separated
- [ ] Code is readable and understandable (e.g. good naming, clear logic, comments where needed)
- [ ] Comments explain why, not what
- [ ] No unnecessary complexity or over-engineering
- [ ] Functions/methods are focused and reasonably sized
- [ ] Error handling is explicit and appropriate
- [ ] Security practices are followed (input validation, no secrets, sanitization)
- [ ] Performance is adequate for the use case (profiling if needed)
- [ ] No obvious bugs or edge cases are missed
