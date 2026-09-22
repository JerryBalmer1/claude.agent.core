"""Core snake: wraps Claude and forces compliance via a validate-retry loop.

The transport is injectable, so the retry machinery can be exercised with no
API key, no network, and no ``anthropic`` package on the path. The SDK import
is lazy and happens only when a live transport is actually built.
"""
from __future__ import annotations

import hashlib
import os
import time
from typing import Any, Callable, Dict, List, NamedTuple, Optional

# transport(messages, system, model, max_tokens) -> assistant text
Transport = Callable[[List[Dict[str, str]], Optional[str], str, int], str]
EventSink = Callable[[Dict[str, Any]], None]


class SnakeError(RuntimeError):
    """Base class for snake failures. Never swallowed, always surfaced."""

    code = "SNAKE"


class TransportError(SnakeError):
    """The model call itself failed (network, auth, SDK missing)."""

    code = "TRANSPORT"


class MaxRetriesExceeded(SnakeError):
    """Validator never satisfied inside the retry cap. Halt and report."""

    code = "MAX_RETRIES"


class ForceResult(NamedTuple):
    """An accepted output plus its ledger metadata."""

    output: str
    attempts: int
    sha256: str
    reason: str

    def __str__(self) -> str:  # so print(result) still prints the payload
        return self.output


class Snake:
    """The wrapper that doesn't ask Claude nicely."""

    def __init__(
        self,
        api_key: Optional[str] = None,
        model: str = "claude-sonnet-4-5",
        max_retries: int = 5,
        base_delay: float = 1.0,
        max_tokens: int = 4096,
        transport: Optional[Transport] = None,
        on_event: Optional[EventSink] = None,
    ):
        self.model = model
        self.max_retries = int(max_retries)
        if self.max_retries < 1:
            raise ValueError("max_retries must be >= 1")
        self.base_delay = float(base_delay)
        self.max_tokens = int(max_tokens)
        self._on_event: EventSink = on_event or (lambda event: None)

        if transport is not None:
            # Injected transport: no key, no SDK, no network required.
            self.api_key = api_key
            self._transport = transport
        else:
            self.api_key = api_key or os.environ.get("ANTHROPIC_API_KEY")
            if not self.api_key:
                raise ValueError("No API key. Set ANTHROPIC_API_KEY or pass it in.")
            self._transport = self._live_transport()

    # ---------------------------------------------------------------- transport

    def _live_transport(self) -> Transport:
        try:
            from anthropic import Anthropic  # imported only on the live path
        except ImportError as exc:
            raise TransportError(
                "anthropic SDK not installed. pip install -r requirements.txt"
            ) from exc

        client = Anthropic(api_key=self.api_key)

        def _send(messages, system, model, max_tokens):
            kwargs: Dict[str, Any] = {
                "model": model,
                "max_tokens": max_tokens,
                "messages": messages,
            }
            if system:
                kwargs["system"] = system
            resp = client.messages.create(**kwargs)
            return "".join(
                block.text
                for block in resp.content
                if getattr(block, "type", None) == "text"
            )

        return _send

    # -------------------------------------------------------------------- guts

    def _emit(self, **event: Any) -> None:
        self._on_event(event)

    def _sleep(self, attempt: int) -> None:
        if self.base_delay <= 0:
            return
        delay = self.base_delay * (2 ** (attempt - 1))
        self._emit(type="log", level="debug", msg=f"backoff {delay:.2f}s")
        time.sleep(delay)

    @staticmethod
    def _feedback(attempt: int, reason: str, text: str) -> str:
        return (
            f"Your output failed validation on attempt {attempt}. "
            f"Reason: {reason}. "
            f"Fix it. Output only what was asked, no commentary, no markdown fences. "
            f"Your rejected attempt began: {text[:500]}"
        )

    # -------------------------------------------------------------------- force

    def force(
        self,
        prompt: str,
        validator: Callable[[str], Any],
        system: Optional[str] = None,
        max_tokens: Optional[int] = None,
    ) -> ForceResult:
        """Send prompt, validate, feed failures back, retry until the cap."""
        tokens = self.max_tokens if max_tokens is None else int(max_tokens)
        messages: List[Dict[str, str]] = [{"role": "user", "content": prompt}]
        last_reason = "no attempt completed"

        for attempt in range(1, self.max_retries + 1):
            self._emit(type="attempt", n=attempt, of=self.max_retries)
            self._emit(
                type="log",
                level="debug",
                msg="request",
                data={
                    "model": self.model,
                    "max_tokens": tokens,
                    "messages": len(messages),
                    "system": bool(system),
                },
            )

            try:
                text = self._transport(messages, system, self.model, tokens)
            except Exception as exc:
                last_reason = f"transport failed: {exc}"
                self._emit(
                    type="log", level="warn", msg=f"attempt {attempt}: {last_reason}"
                )
                if attempt == self.max_retries:
                    raise TransportError(last_reason) from exc
                self._sleep(attempt)
                continue

            self._emit(
                type="log",
                level="debug",
                msg="response",
                data={"chars": len(text), "head": text[:120]},
            )

            result = validator(text)
            ok = bool(result)
            reason = getattr(result, "reason", "") or ("passed" if ok else "rejected")
            self._emit(type="validation", ok=ok, attempt=attempt, reason=reason)

            if ok:
                digest = hashlib.sha256(text.encode("utf-8")).hexdigest()
                self._emit(
                    type="log",
                    level="verbose",
                    msg=(
                        f"accepted on attempt {attempt}/{self.max_retries} "
                        f"(sha256 {digest[:12]}...)"
                    ),
                )
                return ForceResult(text, attempt, digest, reason)

            last_reason = reason
            self._emit(
                type="log",
                level="verbose",
                msg=f"attempt {attempt}/{self.max_retries} rejected: {reason}",
            )

            # Claude failed. Feed it the corpse of its own failure.
            messages.append({"role": "assistant", "content": text})
            messages.append(
                {"role": "user", "content": self._feedback(attempt, reason, text)}
            )
            if attempt < self.max_retries:
                self._sleep(attempt)

        raise MaxRetriesExceeded(
            f"validator never satisfied after {self.max_retries} attempts. "
            f"Last failure: {last_reason}"
        )
