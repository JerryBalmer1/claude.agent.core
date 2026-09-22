"""Pluggable validators for the snake.

Every validator is a callable ``(text) -> ValidationResult``. The result is
truthy when the output passed and always carries a human-readable reason, so
the retry loop can feed a *specific* failure back to the model instead of a
shrug. Plain ``bool``-returning callables still work; they just lose the reason.
"""
from __future__ import annotations

import json
import re
from typing import Callable, NamedTuple, Optional, Tuple


class ValidatorError(ValueError):
    """Unknown validator name or bad argument. Surfaces as a usage error."""


class ValidationResult(NamedTuple):
    ok: bool
    reason: str

    def __bool__(self) -> bool:
        return self.ok


Validator = Callable[[str], ValidationResult]


def _ok(reason: str) -> ValidationResult:
    return ValidationResult(True, reason)


def _fail(reason: str) -> ValidationResult:
    return ValidationResult(False, reason)


def non_empty() -> Validator:
    def _check(out: str) -> ValidationResult:
        stripped = (out or "").strip()
        if stripped:
            return _ok(f"{len(stripped)} non-whitespace chars")
        return _fail("output was empty or whitespace only")

    return _check


def contains(substring: str) -> Validator:
    def _check(out: str) -> ValidationResult:
        if substring in out:
            return _ok(f"found required substring {substring!r}")
        return _fail(f"required substring {substring!r} not present in output")

    return _check


def matches(pattern: str) -> Validator:
    rx = re.compile(pattern)

    def _check(out: str) -> ValidationResult:
        hit = rx.search(out)
        if hit:
            return _ok(f"pattern {pattern!r} matched at offset {hit.start()}")
        return _fail(f"pattern {pattern!r} did not match anywhere in output")

    return _check


def is_json() -> Validator:
    def _check(out: str) -> ValidationResult:
        try:
            json.loads(out)
        except ValueError as exc:
            return _fail(f"not valid JSON: {exc}")
        return _ok("output parsed as JSON")

    return _check


def has_function_def() -> Validator:
    required = ("def ", "return")

    def _check(out: str) -> ValidationResult:
        missing = [tok for tok in required if tok not in out]
        if missing:
            listed = " and ".join(repr(tok) for tok in missing)
            return _fail(f"no {listed} token in output; it is prose, not a function")
        return _ok("found 'def ' and 'return'")

    return _check


# name -> (factory, requires an argument)
_REGISTRY: dict = {
    "contains": (contains, True),
    "has_function_def": (has_function_def, False),
    "is_json": (is_json, False),
    "matches": (matches, True),
    "non_empty": (non_empty, False),
}


def names() -> Tuple[str, ...]:
    """Validator names the CLI accepts. Keep --validator's ValidateSet in sync."""
    return tuple(sorted(_REGISTRY))


def get_validator(name: str, arg: Optional[str] = None) -> Validator:
    """Resolve a validator by name. Raises ValidatorError on anything unusable."""
    try:
        factory, needs_arg = _REGISTRY[name]
    except KeyError:
        raise ValidatorError(
            f"unknown validator {name!r}; known validators: {', '.join(names())}"
        ) from None

    if needs_arg and arg is None:
        raise ValidatorError(f"validator {name!r} requires --validator-arg")
    if not needs_arg and arg is not None:
        raise ValidatorError(f"validator {name!r} takes no --validator-arg")

    try:
        return factory(arg) if needs_arg else factory()
    except re.error as exc:
        raise ValidatorError(f"bad --validator-arg for {name!r}: {exc}") from None
