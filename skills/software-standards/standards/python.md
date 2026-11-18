# Python Coding Standards

This document establishes comprehensive Python coding standards, emphasising modern best practices and maintainability.
Some rules can and should be enforced by linters, while others require more discipline.

## PEPs Reference

Essential PEPs to follow:

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
- PEP 723: Inline script metadata for single-file scripts
- PEP 742: Type narrowing with `TypeIs` (Python 3.13+)
- PEP 750: Template Strings (t-strings) (Python 3.14+)

## Naming

- **Functions & variables**: `snake_case`
- **Classes**: `CamelCase`
- **Constants**: `ALL_CAPS` (module-level)
- **Private identifiers**: Leading underscore (`_variable`, `_function()`)
- **Discarded values**: Use `_` to explicitly ignore return values
- **Avoid single-letter variable names** in most contexts except for:
  - **Loop indices**: `for i in range(n):`, `for i, item in enumerate(items):`
  - **Scientific/mathematical code**: `x`, `y`, `z` for coordinates; `t` for time; domain-standard conventions
  - **Discarded values**: `_` for values that are not required (`_ = await call()`)
  - **Type variables**: `T`, `K`, `V` per PEP 484

## Imports

- Absolute imports only, no relative imports
- Google-style import (import packages and modules only), with exceptions for symbols from `typing` and `collections.abc` and for explicit public API re-exports in `__init__.py`.
- Use standard abbreviations (e.g., `import numpy as np`)

## Other General Best Practices

- **Type Annotations**:
  - Use complete type annotations for all function signatures and variable declarations.
  - Include explicit type arguments for generic types.
- **Mutable globals**
  - Avoid mutable globals.
  - If unavoidable, make private with leading `_` and expose only public functions.
- **Context variables**
  - Use `contextvars.ContextVar` only for ambient execution context that cannot reasonably be passed explicitly, such as request metadata, logging fields, tracing correlation, routing keys, or other scoped control signals.
  - Do not use context variables to own mutable business state, request results, or caches.
  - Context variables can be an exception to the mutable global rule, but they must be private, explicitly typed, set and reset through narrow helper functions or context managers, and reset with the returned token in all normal and exceptional control paths.
  - Prefer immutable or simple scalar values.
  - If a structured value is necessary, treat it as an immutable snapshot.
- **Function defaults**
  - Never use mutable objects as default values (lists, dicts).
  - Use `None` and initialise in the function body.
- **Readability**
  - Declare variable types before `if/else` branches.
  - Use context managers for resource management (`with` statements).
  - Use `try` with `except`, `else`, and `finally` as designed and as needed.
  - Use `textwrap.dedent()` for long multi-line strings (or prefer external text files).

## Build and Package Management

- **`pyproject.toml`**: Use `pyproject.toml` as the single source of truth for the build system and dependencies.
- **Package manager**: Use `uv` for fast, modern package management.
- **Lock files**
  - Pin versions with lock files.
  - Use `>=` in `pyproject.toml` for actual requirements.
- **Dependencies**: Separate dev, build, and prod dependencies into groups.
- **Package layout**
  - Prefer implicit namespace packages (PEP 420) for simple hierarchies and no `__init__.py` files.
  - Use `__init__.py` only if the package should expose a unified public API across its submodules.
  - Re-export the public symbols in `__init__.py` and list them explicitly in `__all__`.

## Linting and Static Analysis

- **Formatting**: `ruff format` for consistent style
- **Linting**: `ruff check` for code quality
- **Static analysis**: `pyright` for type checking and safety
- **Modern features**: Use language features fully (such as `Self`, `Final`, `@final`, `@override`, `match`/`case`, `type` statements and inline type parameters, `TypeIs`, `assert_never`, etc.)
- **Type narrowing**: Use `cast` only when necessary and it produces correct behaviour safely

## Enums

- Singleton comparison (`None`, `True`, `False`, enums) uses identity (`is`), not equality (`==`)
- Prefer plain `enum.Enum` for strongest typing and clear name/value differentiation
- Prefer integer-valued enums for database storage (optimal performance, interoperability); assign explicit values if values are persisted or exposed in an API
- Use `enum.auto()` with `_generate_next_value_` to generate stable values for string-valued enums; avoid rename if values are persisted or exposed in an API
- Use `IntEnum` and `StrEnum` sparingly; beware of unintended comparisons and type issues

## File Paths

- **Local filesystems**: Use `pathlib.Path` for all operations
- **Cloud storage**: Use `cloudpathlib` for cloud path operations

## Function Signatures

- Use `/` and `*` to enforce positional/keyword-only arguments for clarity and safety
- Use `@property` and `@functools.cached_property` appropriately
- Choose appropriate container types for parameters (e.g., `Sequence` vs `list` for inputs)

## Data Models

In order of preference:

1. **Pydantic**: Prefer strict models with field and model validators and model config settings such as `extra="forbid"`, `validate_default=True`, and `strict=True`.
   Use `frozen=True` for read-only models or `validate_assignment=True` for mutable models.
2. **Dataclasses**: For performance-sensitive code without validation (`frozen=True`, `kw_only=True`, `slots=True`)
3. **NamedTuple**: For immutable named tuples (efficient for vectorized computation)

### UUID Generation

- Use `uuid.uuid7()` by default for new applications targeting Python 3.14 or later, as it supports chronological sorting and can improve database index locality.
- Use `uuid.uuid5()` with a stable namespace and name when the same inputs must produce the same identifier.
- Use `uuid.uuid4()` if a contract requires version 4, the identifier must omit its generation timestamp, or the project supports Python versions without `uuid.uuid7()`.

## Command-Line Interfaces

- Prefer **`cyclopts`** over `argparse` or `click` for type-safe CLI (generates automatically from type hints)
- For executable scripts managed by `uv`, use `#!/usr/bin/env -S uv run --script` in the shebang.
- Use PEP 723 inline metadata (`# /// script` block) for portable standalone scripts with no workspace dependencies.
- Use proper exit codes (0 for success, non-zero for errors)

## Database

- Use **SQLAlchemy 2.0 API** (ORM or Core) exclusively
- Use **Alembic** for migrations; avoid hand-written SQL
- Never use raw SQL queries for safety and maintainability
- Define statement generation as class methods on the table class when mapped classes own their queries.
- When a project has several database modules, group them in a dedicated package, with one table per file where practical.

## HTTP and OpenAPI

- Generate a statically typed client from an OpenAPI spec if spec is available
- Prefer `httpx2.AsyncClient` over `httpx` or `requests`
- All request/response types must be strongly typed and validated data models

## Testing (Pytest)

- **Layout**: Prefer one unit test file per source module, for example `tests/test_foo.py` for `src/foo.py`.
- **Isolation**: Never mutate shared libraries or modules that could contaminate other tests.
- **Conftest**: Use `conftest.py` at each directory level for scoped fixtures.
- **Sandboxing**: Define fixtures to block network access for unit tests.
- **Markers**
  - Define a fixed set of custom markers, similar to Bazel tags.
  - Register them in the project-level pytest configuration and use them consistently for categories such as `unit`, `integration`, `manual`, and `network`.
- **Grouping**
  - Use test classes to organise related tests.
  - Use `@staticmethod` when appropriate.
- **Parametrisation**: Use `@pytest.mark.parametrize` with `ids` for multiple input/output cases.
- **Patching**
  - Use `mock.patch.object()` for mock-based dependency replacement.
  - Patch the name in the namespace where the code under test looks it up.
  - Use a context manager when the patch is localised to a specific arrange/act/assert block.
  - Use a decorator when the patch is a whole-function precondition.
  - Avoid string-based `mock.patch()` because string targets are brittle and cannot be checked statically.
  - Use `monkeypatch` for environment variables and pytest process-state changes.
- **Asyncio**: Set `asyncio_mode = "auto"` in the project-level pytest configuration when `pytest-asyncio` handles all asynchronous tests; omit `@pytest.mark.asyncio` unless the test needs marker options such as `loop_scope`.
- **Naming**: Keep test names descriptive and concise.
- **Concurrent state**: Exercise different completion orders and assert observable success or failure.
- **Scoped states and tracing**: Verify propagation into child tasks and restoration of parent state after nested scopes and exceptions.
