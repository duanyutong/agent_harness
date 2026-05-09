# Code Review Guidelines

This document provides guidance for conducting effective code reviews.

For general coding principles and best practices, see [principles.md](../standards/principles.md).

## What to Look For

- **Intent** — Understand the motivation for the change and justification for the chosen approach. Ask: What problem does it solve? What are the options? Why is this the right way?
- **Scope** — Is the change appropriately scoped for a single PR? Does the stated scope in the PR title and description match the diff?
- **Correctness** — Does the code do what it claims? Are edge cases handled?
- **Design** — Is it well-structured? (modular, layered, separation of concerns)
- **Readability** — Is it easy to understand, with adequate documentation?
- **Maintainability** — Can future developers modify this safely and extend it?
- **Standards** — Does it follow best practices and conventions?
- **Testing** — Are tests comprehensive and cover important cases?

## Providing Feedback

- Be clear, grounded, and constructive
- Include disposition for each comment to distinguish blocking issues from nonblocking ones
- Ask questions when intent is unclear rather than assuming

### Disposition Indicators

Disposition indicators improve code review effectiveness by:

- **Reducing ambiguity**: Authors know exactly what's blocking vs. optional, avoiding wasted effort on misinterpretation
- **Enabling async workflows**: Clear signals allow distributed resolution without synchronous clarification
- **Maintaining positive tone**: Marking nitpicks as "nit" or "minor" signals they're about making small improvements, not severe criticisms
- **Speeding up resolution**: Reviewers and authors quickly align on what must be addressed before merge

Use the following table of standard disposition indicators in the beginning of each comment to indicate the severity and nature of the issue.
This convention is based on [Reviewable's disposition system](https://docs.reviewable.io/discussions#dispositions-and-resolution).

| Indicator        | Disposition | Blocking? |
| ---------------- | ----------- | --------- |
| FYI              | Informing   | No        |
| Typo, Minor, Nit | Discussing  | No        |
| LGTM             | Satisfied   | No        |
| Major, Bug       | Blocking    | Yes       |
| ???              | Pondering   | No        |

## Review Structure

A code review consists of:

1. **Decision**: Approve, Request Changes, or Comment
2. **Review Body**: High-level summary or architectural feedback
3. **Inline Comments**: Line-by-line feedback on specific code

### Review Body

If there are high-level issues regarding the architecture, design, or code organization, not tied to specific files or lines, describe them here in a concise manner and provide constructive suggestions for improvement.

If no high-level issues exist, include a **one-sentence** summary.
Do not elaborate, add multiple points, or repeat the inline comments. Examples:

- "Clean implementation with clear separation of concerns; a few minor comments below."
- "LGTM; just a couple of nits."
- "Thanks for putting this together."

### Inline Comments

Each inline comment should:

- Begin with one of the standard disposition indicators plus the issue type, e.g. "FYI (perf): ...", "Minor (readability): ..." without emphasis in bold
- Describe the issue clearly and concisely, no more than one or two sentences
  - If clearly a bug, state it directly
  - If it is uncertain (could be intentional), ask clarifying questions instead of assuming
- Include a well-written code example when suggesting improvements, if possible
- Consider the scope and size of the PR—if addressing the issue can be deferred to a follow-up, mention that (only if the change would be large or significantly out of scope)

Only use "LGTM" when replying to an existing, open thread that has been fully addressed.
Do not add new inline comments that are simply LGTM.

## Code Review Checklist

When reviewing or writing code, verify:

- [ ] Code follows all principles in [principles.md](../standards/principles.md) and applicable adjacent language-specific guidelines
- [ ] Design is sound; responsibilities are clearly separated
- [ ] Code is readable and understandable (e.g. good naming, clear logic, comments where needed)
- [ ] Comments explain why, not what
- [ ] No unnecessary complexity or over-engineering
- [ ] Functions/methods are focused and reasonably sized
- [ ] Error handling is explicit and appropriate
- [ ] Security practices are followed (input validation, no secrets, sanitization)
- [ ] Performance is adequate for the use case (profiling if needed)
- [ ] No obvious bugs or edge cases are missed
