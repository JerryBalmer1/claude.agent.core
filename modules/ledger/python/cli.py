"""Subprocess entry point for the Ledger snake.

Ledger.psm1 spawns this module. Scalar knobs arrive on argv, free text arrives
as one JSON object on stdin, and everything written back is NDJSON on stdout --
one self-describing event per line, which PowerShell maps onto Write-Verbose /
Write-Debug / Write-Warning / Write-Error. stderr carries only unstructured
crashes. A non-zero exit is the contract for "PowerShell must throw".

Contract version: 1
"""
from __future__ import annotations

import argparse
import json
import logging
import os
import sys
import traceback
from typing import Any, Callable, Dict, List, Optional

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import validators  # noqa: E402
from snake import MaxRetriesExceeded, Snake, SnakeError, TransportError  # noqa: E402

PROTOCOL = 1

EXIT_OK = 0
EXIT_UNEXPECTED = 1
EXIT_VALIDATION = 2
EXIT_USAGE = 3
EXIT_NO_KEY = 4
EXIT_TRANSPORT = 5

_LEVEL_NAME = {
    logging.DEBUG: "debug",
    logging.INFO: "verbose",
    logging.WARNING: "warn",
    logging.ERROR: "error",
}

DEFAULT_MOCK_RESPONSES: List[str] = [
    # Attempt 1: prose. Fails has_function_def, which is the point.
    "Sure! Adding two numbers is straightforward -- you take the first value, "
    "combine it with the second using the plus operator, and that is your "
    "answer. Happy to elaborate if you want more detail.",
    # Attempt 2: what was actually asked for.
    "def add(a, b):\n    return a + b\n",
]


class JsonLineFormatter(logging.Formatter):
    """Render every record as one NDJSON event line."""

    def format(self, record: logging.LogRecord) -> str:
        event: Optional[Dict[str, Any]] = getattr(record, "event", None)
        if event is None:
            event = {
                "type": "log",
                "level": _LEVEL_NAME.get(record.levelno, "verbose"),
                "msg": record.getMessage(),
            }
        return json.dumps({"v": PROTOCOL, **event}, ensure_ascii=False)


def _build_logger() -> logging.Logger:
    log = logging.getLogger("ledger.snake")
    log.setLevel(logging.DEBUG)
    log.propagate = False
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonLineFormatter())
    log.addHandler(handler)
    return log


LOG = _build_logger()

_EVENT_LEVEL = {
    "debug": logging.DEBUG,
    "verbose": logging.INFO,
    "warn": logging.WARNING,
    "error": logging.ERROR,
}


def emit(event: Dict[str, Any]) -> None:
    """Write one NDJSON event. The only output channel this program has."""
    level = _EVENT_LEVEL.get(str(event.get("level", "verbose")), logging.INFO)
    LOG.log(
        level,
        str(event.get("msg", event.get("type", "event"))),
        extra={"event": event},
    )


def log(level: str, msg: str, **data: Any) -> None:
    event: Dict[str, Any] = {"type": "log", "level": level, "msg": msg}
    if data:
        event["data"] = data
    emit(event)


def fail(exit_code: int, code: str, msg: str) -> int:
    emit({"type": "error", "code": code, "msg": msg, "exit": exit_code})
    return exit_code


class ContractParser(argparse.ArgumentParser):
    """argparse that reports usage failures on the NDJSON channel, exit 3."""

    def error(self, message: str) -> Any:  # type: ignore[override]
        sys.exit(fail(EXIT_USAGE, "USAGE", "bad argv: " + message))


def build_parser() -> ContractParser:
    p = ContractParser(prog="ledger-snake", add_help=True)
    p.add_argument("--protocol", type=int, required=True)
    p.add_argument("--mode", choices=("dry-run", "live"), required=True)
    p.add_argument("--model", required=True)
    p.add_argument("--max-retries", type=int, required=True)
    p.add_argument("--validator", required=True, choices=validators.names())
    p.add_argument("--validator-arg", default=None)
    p.add_argument("--max-tokens", type=int, default=4096)
    p.add_argument("--base-delay", type=float, default=1.0)
    return p


def read_payload() -> Dict[str, Any]:
    """One JSON object on stdin, then EOF. Keeps prompt text off the cmdline."""
    raw = sys.stdin.read()
    if not raw.strip():
        raise ValueError("stdin was empty; expected one JSON object with a prompt")
    try:
        payload = json.loads(raw)
    except ValueError as exc:
        raise ValueError("stdin was not valid JSON: " + str(exc)) from None
    if not isinstance(payload, dict):
        raise ValueError("stdin JSON must be an object")
    prompt = payload.get("prompt")
    if not isinstance(prompt, str) or not prompt.strip():
        raise ValueError("stdin JSON needs a non-empty string 'prompt'")
    return payload


def make_mock_transport(responses: List[str]) -> Callable[..., str]:
    """Scripted transport. Repeats the last response once the script runs out."""
    if not responses:
        raise ValueError("dry-run needs at least one mock response")
    calls = {"n": 0}

    def _send(messages, system, model, max_tokens) -> str:
        calls["n"] += 1
        idx = min(calls["n"] - 1, len(responses) - 1)
        if idx != calls["n"] - 1:
            log(
                "debug",
                "mock script exhausted at call {0}; repeating response #{1}".format(
                    calls["n"], idx + 1
                ),
            )
        text = responses[idx]
        log(
            "debug",
            "mock call {0} -> response #{1}".format(calls["n"], idx + 1),
            chars=len(text),
            conversation_turns=len(messages),
        )
        return text

    return _send


def run(args: argparse.Namespace, payload: Dict[str, Any]) -> int:
    validator = validators.get_validator(args.validator, args.validator_arg)
    log(
        "verbose",
        "validator '{0}' resolved".format(args.validator),
        validator_arg=args.validator_arg,
    )

    transport = None
    base_delay = args.base_delay

    if args.mode == "dry-run":
        mock = payload.get("mock") or {}
        responses = mock.get("responses") or DEFAULT_MOCK_RESPONSES
        if not isinstance(responses, list) or not all(
            isinstance(r, str) for r in responses
        ):
            raise ValueError("mock.responses must be a list of strings")
        transport = make_mock_transport(responses)
        base_delay = 0.0
        log(
            "verbose",
            "dry-run: mock transport with {0} scripted response(s), "
            "zero tokens, no network".format(len(responses)),
        )
    else:
        if not os.environ.get("ANTHROPIC_API_KEY"):
            return fail(
                EXIT_NO_KEY,
                "NO_API_KEY",
                "live mode needs ANTHROPIC_API_KEY in the environment",
            )
        log("verbose", "live mode: calling {0} for real".format(args.model))

    snake = Snake(
        model=args.model,
        max_retries=args.max_retries,
        base_delay=base_delay,
        max_tokens=args.max_tokens,
        transport=transport,
        on_event=emit,
    )
    log(
        "debug",
        "snake constructed",
        max_retries=snake.max_retries,
        base_delay=snake.base_delay,
        mode=args.mode,
    )

    result = snake.force(
        prompt=payload["prompt"],
        validator=validator,
        system=payload.get("system"),
    )

    emit(
        {
            "type": "result",
            "ok": True,
            "output": result.output,
            "attempts": result.attempts,
            "sha256": result.sha256,
            "reason": result.reason,
            "validator": args.validator,
            "model": args.model,
            "mode": args.mode,
        }
    )
    return EXIT_OK


def main(argv: Optional[List[str]] = None) -> int:
    for stream in (sys.stdout, sys.stderr, sys.stdin):
        try:
            stream.reconfigure(encoding="utf-8")  # type: ignore[union-attr]
        except (AttributeError, ValueError):
            pass

    args = build_parser().parse_args(argv)
    if args.protocol != PROTOCOL:
        return fail(
            EXIT_USAGE,
            "PROTOCOL",
            "protocol {0} not supported; this snake speaks {1}".format(
                args.protocol, PROTOCOL
            ),
        )

    log(
        "debug",
        "snake cli up",
        python=sys.version.split()[0],
        pid=os.getpid(),
        cwd=os.getcwd(),
    )

    try:
        payload = read_payload()
    except ValueError as exc:
        return fail(EXIT_USAGE, "USAGE", str(exc))

    try:
        return run(args, payload)
    except validators.ValidatorError as exc:
        return fail(EXIT_USAGE, "USAGE", str(exc))
    except MaxRetriesExceeded as exc:
        return fail(EXIT_VALIDATION, exc.code, str(exc))
    except TransportError as exc:
        return fail(EXIT_TRANSPORT, exc.code, str(exc))
    except SnakeError as exc:
        return fail(EXIT_UNEXPECTED, exc.code, str(exc))
    except ValueError as exc:
        return fail(EXIT_USAGE, "USAGE", str(exc))
    except KeyboardInterrupt:
        return fail(EXIT_UNEXPECTED, "INTERRUPT", "interrupted")


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception:  # last resort: never die silently
        traceback.print_exc(file=sys.stderr)
        sys.exit(fail(EXIT_UNEXPECTED, "UNEXPECTED", "unhandled exception; see stderr"))
