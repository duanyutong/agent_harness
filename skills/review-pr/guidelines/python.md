# Python Guideline

This document lists Python standards and best practices that in general should be followed wherever possible.

Some rules can and should be enforced by linters, while others require more discipline.

## PEPs

Here is a select list of important PEPs that should be followed.

- PEP 8: Style Guide for Python Code
- PEP 20: The Zen of Python
- PEP 257: Docstring Conventions
- PEP 484: Type Hints (Python 3.5+)
- PEP 518: `pyproject.toml` for build requirements
- PEP 526: Variable Annotations (Python 3.6+)
- PEP 544: Protocols – Structural Subtyping (Python 3.8+)
- PEP 585: Type Hinting Generics in Standard Collections (Python 3.9+)
- PEP 604: Union Types with `|` operator (Python 3.10+)
- PEP 612: ParamSpec for Callable type hints (Python 3.10+)
- PEP 621: Project metadata in `pyproject.toml`
- PEP 634: Structural Pattern Matching `match`/`case` (Python 3.10+)
- PEP 654: Exception Groups and `except*` (Python 3.11+)
- PEP 673: Self type for methods returning instance type (Python 3.11+)
- PEP 675: LiteralString for SQL injection prevention (Python 3.11+)
- PEP 678: Exception notes via `add_note()` (Python 3.11+)
- PEP 692: Unpack[TypedDict] for `**kwargs` typing (Python 3.12+)
- PEP 695: Type Parameter Syntax (Python 3.12+)
- PEP 696: Type Defaults for Type Parameters (Python 3.13+)
- PEP 702: `@deprecated` decorator for deprecation warnings (Python 3.13+)
- PEP 723: Inline script metadata for single-file scripts (Python 3.11+)
- PEP 727: Documentation in Annotated metadata (Python 3.14+)
- PEP 742: TypeIs for type narrowing (replaces TypeGuard) (Python 3.13+)
- PEP 750: Template Strings (t-strings) (Python 3.14+)

## Style

Google style is a set of basic conventions that are widely used and accepted, covering naming, imports, etc.
It is a solid foundation that serves as a good default, unless more modern practices are available.
All guidelines in this document are more modern and stricter than Google style and preferred.

- Naming: snake_case for functions/variables, CamelCase for classes, ALL_CAPS for constants, leading underscore for private variables/functions
- Imports
  - Absolute imports only, no relative imports
  - Import packages and modules only, not individual classes or functions (except from `typing` and `collections.abc`)
  - Use standard abbreviations (e.g., `import numpy as np`)
- Assertions: Do not use `assert` for runtime validation—assertions may be optimised out in production build
- Mutable globals
  - Avoid as much as possible
  - If unavoidable, make variable private with leading `_` and only expose public functions
- Function arguments
  - Never use mutable objects as default values (lists, dicts, etc.)

## Best Practices

### Build and Package Management

- Use `pyproject.toml` as the single source of truth for build system and dependencies
- Use `uv` for fast, modern package management and development workflow
- Use lock file for version pinning, and `>=` in `pyproject.toml` for specifying the actual requirement
- Separate dev, build, and prod dependencies into different groups
- Discard empty `__init__.py`, unless it is needed to make a combined module or to control exports

### Linting & Static Analysis

- Use `ruff-format` for formatting, `ruff-check` for linting, `pyright` for static analysis
- For maximum static analysis coverage, fully utilise modern language features such as
  - `Self`, `Final`, `@final`, `@override`, etc.
  - `match`/`case` for complex conditionals
- Use `cast` if it produces the correct behaviour and is the only way to avoid suppressions

### Readability

- Prefer declaring variable types before `if/else` branches similar to ternary
- Use context managers for resource management (files, connections, locks)
- Use `try-except-else(-finally)` for error handling
- Use `textwrap.dedent()` for long multi-line strings, but consider external text files.

### Enums

- Singleton comparison (`None`, `True`, `False`, enums) should use identity (`is`) rather than equality (`==`)
- Prefer plain `enum.Enum` for strongest typing and differentiation between name and value types; use `IntEnum` and `StrEnum` sparingly and beware of unintended comparisons and type issues
- Prefer integer-valued enums when used in database storage for optimal performance, interoperability, and predictable cardinality
- Use `auto()` for automatic value generation (with `_generate_next_value_` override if needed)

### File Paths

- Use `pathlib` for all local filesystem operations
- Use `cloudpathlib` for cloud path operations

### Signature

- Use `/`, `*` features to improve readability and safety of function calls
- Use `@property`, `@functools.cached_property`, `@pydantic.computed_field` appropriately
- Choose the most appropriate type for any variable and parameter (e.g. `list` vs `frozenset`)
  - Input data containers should generally be covariant (e.g. `Sequence` vs `list`)

### Data Models

In order of preference:

- Pydantic: For data models with validation (`frozen=True`, `extra='forbid'`, `validate_assignment=True`, `strict=True`); make full use of supported types and field/model validators
- Dataclasses: For performance without validation (`frozen=True`, `kw_only=True`, `slots=True`)
- NamedTuple: For immutable tuples with named fields (efficient for vectorised computation)

### CLI Scripts

- Prefer `cyclopts` over `argparse` or `click` for modern type-safe CLI
  - Leverage type hints to generate argument parsers automatically
- Use `#!/usr/bin/env -S uv run --script` in shebang as documented in `uv`
- Use proper exit codes (0 success, non-zero error)

### Database

- Use `SQLAlchemy` 2.0 API (either ORM or Core)
- Use `Alembic` for automatic migrations
- Avoid raw SQL queries for safety and maintainability

### OpenAPI and HTTP Clients

- Always generate statically typed clients from OpenAPI specs for making HTTP calls
- Use async `httpx` rather than `requests` if hand-writing clients
- All request/response types should be pydantic models

### Pytest

- Never mutate shared libraries or modules in a way that can contaminate other tests
- Conftest: Use `conftest.py` for clearly scoped fixtures at each directory level
- Sandboxing: Define a fixture to completely block network access for unit tests
- Custom markers: Use a fixed set of markers to manage different types of tests (unit, integration, manual, network, etc.), similar to Bazel tags.
- Grouping: Use classes to group related test functions for readability; use `@staticmethod` when appropriate
- Parametrisation: Use `@pytest.mark.parametrize` with `ids` for testing multiple input/output cases
- Patching: prefer `mock.path.object` over `mock.patch` for already-imported modules to avoid hardcoded string paths that are brittle and not type-checked.

Other tips:

- Asyncio: `asyncio_mode = "auto"` once in project config and skip the `@pytest.mark.asyncio` decorator in functions
- Keep class and function names descriptive and yet concise; use `pytest_collection_modifyitems` to limit node display length in test reports if needed
