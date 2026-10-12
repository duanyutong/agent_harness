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
- PEP 723: Inline script metadata for single-file scripts (Python 3.11+)
- PEP 727: Documentation in Annotated metadata (Python 3.14+)
- PEP 742: TypeIs for type narrowing (replaces TypeGuard) (Python 3.13+)
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
- Import packages and modules only, not individual classes or functions (except from `typing` and `collections.abc`)
- Use standard abbreviations (e.g., `import numpy as np`)

## Other General Best Practices

- **Type Annotations**:
  - Always use type hints for function arguments and return types.
  - For variables that are not immediately obvious, add type annotations for clarity.
- **Mutable globals**: Avoid. If unavoidable, make private with leading `_` and expose only public functions
- **Function defaults**: Never use mutable objects as default values (lists, dicts); use `None` and initialise in the function body
- **Readability**:
  - Declare variable types before `if/else` branches
  - Use context managers for resource management (`with` statements)
  - Use `try-except-else-finally` for error handling
  - Use `textwrap.dedent()` for long multi-line strings (or prefer external text files)

## Build and Package Management

- **`pyproject.toml`**: Single source of truth for build system and dependencies
- **Package manager**: Use `uv` for fast, modern package management
- **Lock files**: Pin versions with lock files; use `>=` in `pyproject.toml` for actual requirements
- **Dependencies**: Separate dev, build, and prod dependencies into groups
- **`__init__.py`**: Discard unless needed for combined modules or controlling exports

## Linting and Static Analysis

- **Formatting**: `ruff format` for consistent style
- **Linting**: `ruff check` for code quality
- **Static analysis**: `pyright` for type checking and safety
- **Modern features**: Use language features fully (`Self`, `Final`, `@final`, `@override`, `match`/`case`)
- **Type narrowing**: Use `cast` only when necessary and it produces correct behaviour

## Enums

- Singleton comparison (`None`, `True`, `False`, enums) uses identity (`is`), not equality (`==`)
- Prefer plain `Enum` for strongest typing and clear name/value differentiation
- Use `IntEnum` and `StrEnum` sparingly; beware of unintended comparisons and type issues
- Prefer integer-valued enums for database storage (optimal performance, interoperability)
- Use `auto()` for automatic value generation (with `_generate_next_value_` override if needed)

## File Paths

- **Local filesystems**: Use `pathlib.Path` for all operations
- **Cloud storage**: Use `cloudpathlib` for cloud path operations

## Function Signatures

- Use `/` and `*` to enforce positional/keyword-only arguments for clarity and safety
- Use `@property` and `@functools.cached_property` appropriately
- Choose appropriate container types for parameters (e.g., `Sequence` vs `list` for inputs)

## Data Models

In order of preference:

1. **Pydantic**: For data models with validation; leverage field/model validators; use strictest config (`frozen=True`, `extra='forbid'`, `validate_default=True`, `validate_assignment=True`)
2. **Dataclasses**: For performance-sensitive code without validation (`frozen=True`, `kw_only=True`, `slots=True`)
3. **NamedTuple**: For immutable named tuples (efficient for vectorized computation)

## Command-Line Interfaces

- Prefer **`cyclopts`** over `argparse` or `click` for type-safe CLI (generates automatically from type hints)
- Use `#!/usr/bin/env -S uv run --script` in shebang
- Use proper exit codes (0 for success, non-zero for errors)

## Database

- Use **SQLAlchemy 2.0 API** (ORM or Core) exclusively
- Use **Alembic** for migrations; avoid hand-written SQL
- Never use raw SQL queries for safety and maintainability

## HTTP and OpenAPI

- **Always generate statically typed clients from OpenAPI specs** for HTTP calls
- Use async **`httpx`** rather than `requests` for hand-written clients
- All request/response types must be Pydantic models

## Testing (Pytest)

- **Isolation**: Never mutate shared libraries or modules that could contaminate other tests
- **Conftest**: Use `conftest.py` at each directory level for scoped fixtures
- **Sandboxing**: Define fixtures to block network access for unit tests
- **Markers**: Define a fixed set of custom markers (unit, integration, manual, network) similar to Bazel tags
- **Grouping**: Use test classes to organise related tests; use `@staticmethod` when appropriate
- **Parametrisation**: Use `@pytest.mark.parametrize` with `ids` for multiple input/output cases
- **Patching**: Prefer `mock.patch.object()` over `mock.patch()` for better type checking and maintainability
- **Asyncio**: Configure `asyncio_mode = "auto"` project-wide; skip `@pytest.mark.asyncio` on functions
- **Naming**: Keep test names descriptive and concise
