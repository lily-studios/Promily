from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence

#——————————————————————————————————————————————————————————————————————

PACKAGE_NAME = "Promily"
DEFAULT_VERSION = "1.0.0"
OUTPUT_NAME = "init.luau"
SEPARATOR = "--————————————————————————————————————————————————————————————————————--"
DEFAULT_WATCH_INTERVAL = 0.35
WATCH_DEBOUNCE_SECONDS = 0.12

FUNCTION_ANNOTATION = re.compile(
    r"^\s*---\s*@promilyExport(?:\s+([A-Za-z_][A-Za-z0-9_]*))?\s*$"
)
TYPE_ANNOTATION = re.compile(
    r"^\s*---\s*@promilyType(?:\s+([A-Za-z_][A-Za-z0-9_]*))?\s*$"
)
FUNCTION_PATTERN = re.compile(
    r"^\s*function\s+module\.([A-Za-z_][A-Za-z0-9_]*)\b"
)
ASSIGNED_FUNCTION_PATTERN = re.compile(
    r"^\s*module\.([A-Za-z_][A-Za-z0-9_]*)\s*=\s*function\b"
)
TYPE_START_PATTERN = re.compile(
    r"^\s*export\s+type\s+([A-Za-z_][A-Za-z0-9_]*)\b"
)
VERSION_PATTERN = re.compile(
    r'^\s*local\s+version\s*=\s*"([^"]+)"\s*$',
    re.MULTILINE,
)

#——————————————————————————————————————————————————————————————————————
# Existing Promily public value API.
#
# New public functions should use:
#
# --- @promilyExport
# function module.someFunction(...)
#
# Or rename the root export:
#
# --- @promilyExport createThing
# function module.new(...)
#
# Unannotated new functions remain private.
#——————————————————————————————————————————————————————————————————————

BASE_FUNCTION_EXPORTS: dict[str, dict[str, tuple[str, ...]]] = {
    "adapters/roblox": {
        "fromAttribute": ("fromAttribute",),
        "fromChild": ("fromChild",),
        "fromEvent": ("fromEvent",),
        "fromProperty": ("fromProperty",),
    },
    "combinators/collection": {
        "all": ("all",),
        "allSettled": ("allSettled",),
        "any": ("any",),
        "each": ("each",),
        "filter": ("filter",),
        "find": ("find",),
        "firstResolved": ("firstResolved",),
        "map": ("map",),
        "mapSettled": ("mapSettled",),
        "partition": ("partition",),
        "props": ("props",),
        "propsSettled": ("propsSettled",),
        "race": ("race",),
        "reduce": ("reduce",),
        "sequence": ("sequence",),
        "some": ("some",),
    },
    "combinators/control": {
        "delay": ("delay",),
        "rejectAfter": ("rejectAfter",),
        "retry": ("retry",),
        "sleep": ("sleep",),
        "timeout": ("timeout",),
        "timeoutOr": ("timeoutOr",),
    },
    "concurrency/queue": {
        "new": ("createQueue",),
    },
    "concurrency/semaphore": {
        "new": ("createSemaphore",),
    },
    "concurrency/singleFlight": {
        "new": ("createSingleFlight",),
    },
    "core/cancellation": {
        "new": ("createCancellationSource",),
    },
    "core/promise": {
        "cancelled": ("cancelled",),
        "defer": ("defer",),
        "is": ("is",),
        "new": ("new",),
        "reject": ("reject",),
        "resolve": ("resolve",),
        "setUnhandledRejectionHandler": ("setUnhandledRejectionHandler",),
        "try": ("try",),
        "wrap": ("wrap",),
    },
    "core/scope": {
        "new": ("createScope",),
    },
}

#——————————————————————————————————————————————————————————————————————
# Existing Promily public type API.
#
# New public types should use:
#
# --- @promilyType
# export type someType = ...
#
# Or rename the root export:
#
# --- @promilyType publicName
# export type internalName = ...
#
# Unannotated new types remain private.
#——————————————————————————————————————————————————————————————————————

BASE_TYPE_EXPORTS: dict[str, dict[str, tuple[str, ...]]] = {
    "adapters/roblox": {
        "childOptions": ("childOptions",),
        "eventOptions": ("eventOptions",),
        "valueOptions": ("valueOptions",),
    },
    "combinators/collection": {
        "mapOptions": ("mapOptions",),
        "partitionResult": ("partitionResult",),
        "settledResult": ("settledResult",),
    },
    "combinators/control": {
        "retryOptions": ("retryOptions",),
    },
    "concurrency/queue": {
        "queue": ("queue",),
        "queueOptions": ("queueOptions",),
    },
    "concurrency/semaphore": {
        "permit": ("permit",),
        "semaphore": ("semaphore",),
    },
    "concurrency/singleFlight": {
        "singleFlight": ("singleFlight",),
        "singleFlightKey": ("singleFlightKey",),
    },
    "core/cancellation": {
        "source": ("cancellationSource",),
    },
    "core/errors": {
        "aggregateError": ("aggregateError",),
        "cancelledAttemptError": ("cancelledAttemptError",),
        "cancelledInputError": ("cancelledInputError",),
        "cancelledMapperError": ("cancelledMapperError",),
        "insufficientInputsError": ("insufficientInputsError",),
        "queueClosedError": ("queueClosedError",),
        "queueDeletedError": ("queueDeletedError",),
        "queueFullError": ("queueFullError",),
        "semaphoreDeletedError": ("semaphoreDeletedError",),
        "singleFlightDeletedError": ("singleFlightDeletedError",),
    },
    "core/promise": {
        "cancellationToken": ("cancellationToken",),
        "connection": ("connection",),
        "deferred": ("deferred",),
        "diagnosticsSnapshot": ("diagnosticsSnapshot",),
        "diagnosticsStats": ("diagnosticsStats",),
        "observer": ("observer",),
        "promise": ("promise",),
        "promiseBase": ("promiseBase",),
        "promiseStatus": ("promiseStatus",),
        "result": ("promiseResult",),
        "timeoutOptions": ("timeoutOptions",),
    },
    "core/scope": {
        "scope": ("scope",),
    },
}

CUSTOM_PUBLIC_NAMES = {
    "after",
    "deadline",
    "fork",
    "getVersion",
    "never",
    "withCancellation",
}

CUSTOM_FIELD_NAMES = {
    "diagnostics",
    "status",
}

CUSTOM_MODULE_KEYS = {
    "combinators/control",
    "core/promise",
}

#——————————————————————————————————————————————————————————————————————


@dataclass(frozen=True)
class ParsedDocumentation:
    lines: tuple[str, ...]
    function_public_names: tuple[str, ...]
    type_public_names: tuple[str, ...]


@dataclass(frozen=True)
class SourceFunction:
    name: str
    documentation: tuple[str, ...]
    annotation_public_names: tuple[str, ...]


@dataclass(frozen=True)
class SourceType:
    name: str
    generic_declaration: str
    annotation_public_names: tuple[str, ...]


@dataclass(frozen=True)
class SourceModule:
    key: str
    path: Path
    variable_name: str
    require_expression: str
    functions: dict[str, SourceFunction]
    types: dict[str, SourceType]


@dataclass(frozen=True)
class FunctionExport:
    public_name: str
    module: SourceModule
    source: SourceFunction


@dataclass(frozen=True)
class TypeExport:
    public_name: str
    module: SourceModule
    source: SourceType


@dataclass(frozen=True)
class GenerationResult:
    source: str
    module_count: int
    public_function_count: int
    public_type_count: int
    warnings: tuple[str, ...]
    version: str


#——————————————————————————————————————————————————————————————————————


def find_project_root(start: Path) -> Path:
    current = start.resolve()

    for candidate in (current, *current.parents):
        source_directory = candidate / "src"

        if source_directory.is_dir():
            return candidate

    raise RuntimeError(
        f'Unable to locate {PACKAGE_NAME} root from "{start}". '
        'Expected a parent directory containing "src".'
    )


#——————————————————————————————————————————————————————————————————————


def read_json_version(path: Path) -> str | None:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise RuntimeError(f'Unable to read "{path}": {error}') from error

    value = data.get("version")

    if not isinstance(value, str):
        return None

    value = value.strip()
    return value or None


#——————————————————————————————————————————————————————————————————————


def read_wally_version(path: Path) -> str | None:
    try:
        source = path.read_text(encoding="utf-8")
    except OSError as error:
        raise RuntimeError(f'Unable to read "{path}": {error}') from error

    package_match = re.search(
        r"(?ms)^\s*\[package\]\s*$"
        r"(.*?)(?=^\s*\[[^\]]+\]\s*$|\Z)",
        source,
    )

    if package_match is None:
        return None

    version_match = re.search(
        r'^\s*version\s*=\s*"([^"]+)"\s*(?:#.*)?$',
        package_match.group(1),
        re.MULTILINE,
    )

    if version_match is None:
        return None

    version = version_match.group(1).strip()
    return version or None


#——————————————————————————————————————————————————————————————————————


def read_existing_init_version(path: Path) -> str | None:
    if not path.is_file():
        return None

    try:
        source = path.read_text(encoding="utf-8")
    except OSError as error:
        raise RuntimeError(f'Unable to read "{path}": {error}') from error

    match = VERSION_PATTERN.search(source)

    if match is None:
        return None

    version = match.group(1).strip()
    return version or None


#——————————————————————————————————————————————————————————————————————


def read_version(project_root: Path, output_path: Path, override: str | None) -> str:
    if override is not None:
        value = override.strip()

        if not value:
            raise RuntimeError("--version must not be empty.")

        return value

    json_candidates = (
        project_root / "package.json",
        project_root / "manifest.json",
    )

    for path in json_candidates:
        if not path.is_file():
            continue

        version = read_json_version(path)

        if version:
            return version

    wally_path = project_root / "wally.toml"

    if wally_path.is_file():
        version = read_wally_version(wally_path)

        if version:
            return version

    current_version = read_existing_init_version(output_path)

    if current_version:
        return current_version

    return DEFAULT_VERSION


#——————————————————————————————————————————————————————————————————————


def escape_luau_string(value: str) -> str:
    return (
        value.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\r", "\\r")
        .replace("\n", "\\n")
    )


#——————————————————————————————————————————————————————————————————————


def is_luau_identifier(value: str) -> bool:
    return re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", value) is not None


#——————————————————————————————————————————————————————————————————————


def upper_first(value: str) -> str:
    if not value:
        return value

    return value[0].upper() + value[1:]


#——————————————————————————————————————————————————————————————————————


def lower_first(value: str) -> str:
    if not value:
        return value

    return value[0].lower() + value[1:]


#——————————————————————————————————————————————————————————————————————


def sanitize_identifier(value: str) -> str:
    parts = re.findall(r"[A-Za-z0-9_]+", value)

    if not parts:
        raise RuntimeError(f'Cannot convert "{value}" into a Luau identifier.')

    identifier = "".join(upper_first(part) for part in parts)
    identifier = lower_first(identifier)

    if identifier[0].isdigit():
        identifier = f"module{identifier}"

    return identifier


#——————————————————————————————————————————————————————————————————————


def create_require_expression(relative_path: Path) -> str:
    expression = "script"

    for part in relative_path.parts:
        if is_luau_identifier(part):
            expression += f".{part}"
            continue

        expression += f'["{escape_luau_string(part)}"]'

    return expression


#——————————————————————————————————————————————————————————————————————


def create_variable_names(module_keys: Sequence[str]) -> dict[str, str]:
    stem_counts: dict[str, int] = {}

    for module_key in module_keys:
        stem = Path(module_key).name
        stem_counts[stem] = stem_counts.get(stem, 0) + 1

    output: dict[str, str] = {}
    used_names: set[str] = set()

    for module_key in sorted(module_keys):
        module_path = Path(module_key)
        stem = module_path.name

        if stem_counts[stem] == 1:
            base = sanitize_identifier(stem)
        else:
            base = sanitize_identifier("_".join(module_path.parts))

        variable_name = f"{base}Module"

        if variable_name in used_names:
            raise RuntimeError(
                f'Duplicate generated module variable "{variable_name}" '
                f'for "{module_key}".'
            )

        used_names.add(variable_name)
        output[module_key] = variable_name

    return output


#——————————————————————————————————————————————————————————————————————


def read_documentation(lines: list[str], declaration_index: int) -> ParsedDocumentation:
    collected: list[str] = []
    index = declaration_index - 1

    while index >= 0:
        stripped = lines[index].strip()

        if stripped.startswith("---"):
            collected.append(stripped)
            index -= 1
            continue

        if stripped == "":
            index -= 1
            continue

        break

    collected.reverse()

    documentation: list[str] = []
    function_public_names: list[str] = []
    type_public_names: list[str] = []

    for line in collected:
        function_match = FUNCTION_ANNOTATION.match(line)

        if function_match:
            function_public_names.append(function_match.group(1) or "")
            continue

        type_match = TYPE_ANNOTATION.match(line)

        if type_match:
            type_public_names.append(type_match.group(1) or "")
            continue

        documentation.append(line)

    return ParsedDocumentation(
        lines=tuple(documentation),
        function_public_names=tuple(function_public_names),
        type_public_names=tuple(type_public_names),
    )


#——————————————————————————————————————————————————————————————————————


def extract_generic_declaration(line: str, type_name: str) -> str:
    match = TYPE_START_PATTERN.match(line)

    if not match:
        return ""

    remainder = line[match.end():].lstrip()

    if not remainder.startswith("<"):
        return ""

    depth = 0
    end_index: int | None = None

    for index, character in enumerate(remainder):
        if character == "<":
            depth += 1
            continue

        if character != ">":
            continue

        depth -= 1

        if depth != 0:
            continue

        end_index = index
        break

    if end_index is None:
        raise RuntimeError(
            f'Unable to parse generic declaration for type "{type_name}". '
            "Keep the generic declaration on one line."
        )

    return remainder[: end_index + 1].strip()


#——————————————————————————————————————————————————————————————————————


def parse_module(source_directory: Path, path: Path, variable_name: str) -> SourceModule:
    relative = path.relative_to(source_directory)
    module_key = relative.with_suffix("").as_posix()

    try:
        source = path.read_text(encoding="utf-8")
    except OSError as error:
        raise RuntimeError(f'Unable to read "{path}": {error}') from error

    lines = source.splitlines()
    functions: dict[str, SourceFunction] = {}
    types: dict[str, SourceType] = {}

    for index, line in enumerate(lines):
        function_match = FUNCTION_PATTERN.match(line)

        if function_match is None:
            function_match = ASSIGNED_FUNCTION_PATTERN.match(line)

        if function_match is not None:
            function_name = function_match.group(1)

            if function_name in functions:
                raise RuntimeError(
                    f'Duplicate module function "{module_key}.{function_name}".'
                )

            documentation = read_documentation(lines, index)
            annotation_names = tuple(
                function_name if name == "" else name
                for name in documentation.function_public_names
            )

            functions[function_name] = SourceFunction(
                name=function_name,
                documentation=documentation.lines,
                annotation_public_names=annotation_names,
            )

        type_match = TYPE_START_PATTERN.match(line)

        if type_match is None:
            continue

        type_name = type_match.group(1)

        if type_name in types:
            raise RuntimeError(
                f'Duplicate exported type "{module_key}.{type_name}".'
            )

        documentation = read_documentation(lines, index)
        annotation_names = tuple(
            type_name if name == "" else name
            for name in documentation.type_public_names
        )

        types[type_name] = SourceType(
            name=type_name,
            generic_declaration=extract_generic_declaration(line, type_name),
            annotation_public_names=annotation_names,
        )

    return SourceModule(
        key=module_key,
        path=path,
        variable_name=variable_name,
        require_expression=create_require_expression(relative.with_suffix("")),
        functions=functions,
        types=types,
    )


#——————————————————————————————————————————————————————————————————————


def discover_module_keys(source_directory: Path) -> tuple[str, ...]:
    output: list[str] = []
    output_path = (source_directory / OUTPUT_NAME).resolve()

    for path in source_directory.rglob("*.luau"):
        if path.resolve() == output_path:
            continue

        relative = path.relative_to(source_directory).with_suffix("")
        output.append(relative.as_posix())

    output.sort()
    return tuple(output)


#——————————————————————————————————————————————————————————————————————


def split_top_level(value: str) -> list[str]:
    output: list[str] = []
    stack: list[str] = []
    pairs = {"<": ">", "(": ")", "[": "]", "{": "}"}
    closing = set(pairs.values())
    start = 0

    for index, character in enumerate(value):
        expected = pairs.get(character)

        if expected is not None:
            stack.append(expected)
            continue

        if character in closing:
            if stack and stack[-1] == character:
                stack.pop()

            continue

        if character != "," or stack:
            continue

        output.append(value[start:index].strip())
        start = index + 1

    tail = value[start:].strip()

    if tail:
        output.append(tail)

    return output


#——————————————————————————————————————————————————————————————————————


def strip_generic_modifier(value: str) -> str:
    stack: list[str] = []
    pairs = {"<": ">", "(": ")", "[": "]", "{": "}"}
    closing = set(pairs.values())

    for index, character in enumerate(value):
        expected = pairs.get(character)

        if expected is not None:
            stack.append(expected)
            continue

        if character in closing:
            if stack and stack[-1] == character:
                stack.pop()

            continue

        if stack:
            continue

        if character in (":", "="):
            return value[:index].strip()

    return value.strip()


#——————————————————————————————————————————————————————————————————————


def get_generic_arguments(declaration: str) -> str:
    if not declaration:
        return ""

    if not declaration.startswith("<") or not declaration.endswith(">"):
        raise RuntimeError(f'Invalid generic declaration "{declaration}".')

    inner = declaration[1:-1].strip()

    if not inner:
        return ""

    arguments: list[str] = []

    for entry in split_top_level(inner):
        candidate = strip_generic_modifier(entry)
        match = re.fullmatch(r"([A-Za-z_][A-Za-z0-9_]*)(\.\.\.)?", candidate)

        if not match:
            raise RuntimeError(
                f'Unsupported generic parameter "{entry}" in "{declaration}".'
            )

        arguments.append(f"{match.group(1)}{match.group(2) or ''}")

    return "<" + ", ".join(arguments) + ">"


#——————————————————————————————————————————————————————————————————————


def merge_public_names(
    base_names: Iterable[str],
    annotation_names: Iterable[str],
) -> tuple[str, ...]:
    output: list[str] = []
    seen: set[str] = set()

    for name in (*base_names, *annotation_names):
        if name in seen:
            continue

        seen.add(name)
        output.append(name)

    return tuple(output)


#——————————————————————————————————————————————————————————————————————


def validate_public_name(name: str, category: str) -> None:
    if is_luau_identifier(name):
        return

    raise RuntimeError(
        f'Invalid public {category} name "{name}". '
        "Public API names must be valid Luau identifiers."
    )


#——————————————————————————————————————————————————————————————————————


def build_function_exports(
    modules: dict[str, SourceModule],
) -> tuple[FunctionExport, ...]:
    exports: list[FunctionExport] = []
    used_names: dict[str, tuple[str, str]] = {}
    module_keys = set(BASE_FUNCTION_EXPORTS)

    module_keys.update(
        module.key
        for module in modules.values()
        if any(
            function.annotation_public_names
            for function in module.functions.values()
        )
    )

    for module_key in sorted(module_keys):
        module = modules.get(module_key)

        if module is None:
            raise RuntimeError(
                f'Public API references missing module "{module_key}".'
            )

        base_exports = BASE_FUNCTION_EXPORTS.get(module_key, {})
        source_names = set(base_exports)
        source_names.update(
            function.name
            for function in module.functions.values()
            if function.annotation_public_names
        )

        for source_name in sorted(source_names):
            source = module.functions.get(source_name)

            if source is None:
                raise RuntimeError(
                    f'Public API references missing function '
                    f'"{module_key}.{source_name}".'
                )

            public_names = merge_public_names(
                base_exports.get(source_name, ()),
                source.annotation_public_names,
            )

            for public_name in public_names:
                validate_public_name(public_name, "function")

                if public_name in CUSTOM_PUBLIC_NAMES or public_name in CUSTOM_FIELD_NAMES:
                    raise RuntimeError(
                        f'Function "{module_key}.{source_name}" attempts to '
                        f'export reserved Promily API "{public_name}".'
                    )

                previous = used_names.get(public_name)
                current = (module_key, source_name)

                if previous is not None:
                    if previous == current:
                        continue

                    raise RuntimeError(
                        f'Duplicate public function "{public_name}" from '
                        f'"{previous[0]}.{previous[1]}" and '
                        f'"{module_key}.{source_name}". '
                        "Rename one export with @promilyExport <name>."
                    )

                used_names[public_name] = current
                exports.append(
                    FunctionExport(
                        public_name=public_name,
                        module=module,
                        source=source,
                    )
                )

    exports.sort(key=lambda export: (export.public_name.lower(), export.public_name))
    return tuple(exports)


#——————————————————————————————————————————————————————————————————————


def build_type_exports(
    modules: dict[str, SourceModule],
) -> tuple[TypeExport, ...]:
    exports: list[TypeExport] = []
    used_names: dict[str, tuple[str, str]] = {}
    module_keys = set(BASE_TYPE_EXPORTS)

    module_keys.update(
        module.key
        for module in modules.values()
        if any(
            source_type.annotation_public_names
            for source_type in module.types.values()
        )
    )

    for module_key in sorted(module_keys):
        module = modules.get(module_key)

        if module is None:
            raise RuntimeError(
                f'Public API references missing module "{module_key}".'
            )

        base_exports = BASE_TYPE_EXPORTS.get(module_key, {})
        source_names = set(base_exports)
        source_names.update(
            source_type.name
            for source_type in module.types.values()
            if source_type.annotation_public_names
        )

        for source_name in sorted(source_names):
            source = module.types.get(source_name)

            if source is None:
                raise RuntimeError(
                    f'Public API references missing type '
                    f'"{module_key}.{source_name}".'
                )

            public_names = merge_public_names(
                base_exports.get(source_name, ()),
                source.annotation_public_names,
            )

            for public_name in public_names:
                validate_public_name(public_name, "type")
                previous = used_names.get(public_name)
                current = (module_key, source_name)

                if previous is not None:
                    if previous == current:
                        continue

                    raise RuntimeError(
                        f'Duplicate public type "{public_name}" from '
                        f'"{previous[0]}.{previous[1]}" and '
                        f'"{module_key}.{source_name}". '
                        "Rename one export with @promilyType <name>."
                    )

                used_names[public_name] = current
                exports.append(
                    TypeExport(
                        public_name=public_name,
                        module=module,
                        source=source,
                    )
                )

    exports.sort(key=lambda export: (export.public_name.lower(), export.public_name))
    return tuple(exports)


#——————————————————————————————————————————————————————————————————————


def create_type_replacements(module_key: str) -> dict[str, str]:
    output: dict[str, str] = {}
    source_types = BASE_TYPE_EXPORTS.get(module_key, {})

    for source_name, public_names in source_types.items():
        if not public_names:
            continue

        public_name = public_names[0]

        if public_name == source_name:
            continue

        output[source_name] = public_name

    return output


#——————————————————————————————————————————————————————————————————————


def rewrite_documentation(
    module_key: str,
    documentation: Sequence[str],
) -> tuple[str, ...]:
    replacements = create_type_replacements(module_key)
    output: list[str] = []

    for line in documentation:
        rewritten = line

        for source_name, public_name in replacements.items():
            rewritten = re.sub(
                rf"\b{re.escape(source_name)}\b",
                public_name,
                rewritten,
            )

        rewritten = rewritten.replace("promiseModule.promise", "promise")
        output.append(rewritten)

    return tuple(output)


#——————————————————————————————————————————————————————————————————————


def get_function_documentation(export: FunctionExport) -> tuple[str, ...]:
    if export.source.documentation:
        return rewrite_documentation(
            export.module.key,
            export.source.documentation,
        )

    return (
        f"--- Re-exports {export.module.key}.{export.source.name}.",
    )


#——————————————————————————————————————————————————————————————————————


def validate_public_documentation(
    exports: Sequence[FunctionExport],
    strict: bool,
) -> tuple[str, ...]:
    warnings: list[str] = []

    for export in exports:
        if export.source.documentation:
            continue

        message = (
            f'Public function "{export.public_name}" from '
            f'"{export.module.key}.{export.source.name}" has no LDoc block.'
        )

        if strict:
            raise RuntimeError(message)

        warnings.append(message)

    return tuple(warnings)


#——————————————————————————————————————————————————————————————————————


def get_required_module_keys(
    function_exports: Sequence[FunctionExport],
    type_exports: Sequence[TypeExport],
) -> tuple[str, ...]:
    output = set(CUSTOM_MODULE_KEYS)
    output.update(export.module.key for export in function_exports)
    output.update(export.module.key for export in type_exports)
    return tuple(sorted(output))


#——————————————————————————————————————————————————————————————————————


def render_header(version: str) -> str:
    escaped_version = escape_luau_string(version)

    return f'''--!strict

-- exposes the public Promily Promise API
-- automatically generated by .vscode/scripts/generateInit.py
-- do not edit this file directly

local module = {{}}

{SEPARATOR}

local version = "{escaped_version}"'''


#——————————————————————————————————————————————————————————————————————


def render_imports(
    modules: dict[str, SourceModule],
    required_module_keys: Sequence[str],
) -> str:
    required_modules = [modules[module_key] for module_key in required_module_keys]
    required_modules.sort(
        key=lambda module: (module.variable_name.lower(), module.variable_name)
    )

    lines = [SEPARATOR, ""]

    for source_module in required_modules:
        lines.append(
            f"local {source_module.variable_name} = "
            f"require({source_module.require_expression})"
        )

    return "\n".join(lines)


#——————————————————————————————————————————————————————————————————————


def render_types(exports: Sequence[TypeExport]) -> str:
    lines = [SEPARATOR, ""]

    for export in exports:
        declaration = export.source.generic_declaration
        arguments = get_generic_arguments(declaration)
        lines.append(
            f"export type {export.public_name}{declaration} = "
            f"{export.module.variable_name}.{export.source.name}{arguments}"
        )

    return "\n".join(lines)


#——————————————————————————————————————————————————————————————————————


def render_function(export: FunctionExport) -> str:
    lines = list(get_function_documentation(export))
    lines.append(
        f"module.{export.public_name} = "
        f"{export.module.variable_name}.{export.source.name}"
    )
    return "\n".join(lines)


#——————————————————————————————————————————————————————————————————————


def render_functions(exports: Sequence[FunctionExport]) -> str:
    lines = [SEPARATOR]

    for export in exports:
        lines.append("")
        lines.append(render_function(export))
        lines.append("")
        lines.append(SEPARATOR)

    return "\n".join(lines)


#——————————————————————————————————————————————————————————————————————


def render_custom_api(modules: dict[str, SourceModule]) -> str:
    control_module = modules["combinators/control"].variable_name
    promise_module = modules["core/promise"].variable_name

    return f'''--- Returns the Promily package version.
---@return string version Semantic package version.
function module.getVersion(): string
\treturn version
end

{SEPARATOR}

--- Creates a Promise that stays pending until it is cancelled.
---@generic T
---@param token cancellationToken? Optional cancellation token.
---@return promise<T> promiseValue Pending Promise.
function module.never<T>(token: cancellationToken?): promise<T>
\treturn {promise_module}.new(function() end, token) :: any
end

{SEPARATOR}

--- Creates an independently cancellable consumer branch of a source Promise.
--- Cancelling the branch disconnects it without cancelling the source.
---@generic T
---@param source T | promise<T> Source value or Promise.
---@return promise<T> branch Independent consumer Promise.
function module.fork<T>(source: T | promise<T>): promise<T>
\treturn {promise_module}.resolve(source).fork() :: any
end

{SEPARATOR}

--- Mirrors a source Promise while also cancelling the consumer when the token is cancelled.
--- Token cancellation does not cancel the source Promise.
---@generic T
---@param source T | promise<T> Source value or Promise.
---@param token cancellationToken Cancellation token for the consumer branch.
---@return promise<T> branch Token-bound consumer Promise.
function module.withCancellation<T>(
\tsource: T | promise<T>,
\ttoken: cancellationToken
): promise<T>
\treturn {promise_module}.resolve(source).withCancellation(token) :: any
end

{SEPARATOR}

--- Applies an absolute os.clock() deadline to a source Promise.
---@generic T
---@param source T | promise<T> Source value or Promise.
---@param deadlineTime number Absolute os.clock() deadline.
---@param reason any? Optional rejection reason when the deadline is exceeded.
---@return promise<T> promiseValue Deadline-bound Promise.
function module.deadline<T>(
\tsource: T | promise<T>,
\tdeadlineTime: number,
\treason: any?
): promise<T>
\treturn {promise_module}.resolve(source).deadline(deadlineTime, reason) :: any
end

{SEPARATOR}

--- Runs a lazy callback after a delay and adopts its result.
---@generic T
---@param seconds number Non-negative delay in seconds.
---@param callback fun(): T | promise<T> Callback to run after the delay.
---@return promise<T> promiseValue Delayed callback result.
function module.after<T>(
\tseconds: number,
\tcallback: () -> T | promise<T>
): promise<T>
\treturn {control_module}.sleep(seconds).andThen(function()
\t\treturn callback()
\tend) :: any
end

{SEPARATOR}

module.diagnostics = table.freeze({{
\t--- Returns pending Promises sorted longest-pending first.
\t---@param limit number? Optional maximum result count.
\t---@return {{diagnosticsSnapshot}} snapshots Pending Promise snapshots.
\tgetLongestPending = function(limit: number?): {{diagnosticsSnapshot}}
\t\treturn {promise_module}.getPendingSnapshots(limit)
\tend,

\t--- Returns pending Promises sorted longest-pending first.
\t---@param limit number? Optional maximum result count.
\t---@return {{diagnosticsSnapshot}} snapshots Pending Promise snapshots.
\tgetPending = function(limit: number?): {{diagnosticsSnapshot}}
\t\treturn {promise_module}.getPendingSnapshots(limit)
\tend,

\t--- Returns lifetime and currently-live Promise counts.
\t---@return diagnosticsStats stats Promise diagnostic counters.
\tgetStats = function(): diagnosticsStats
\t\treturn {promise_module}.getDiagnosticsStats()
\tend,
}})

module.status = {promise_module}.getStatusTable()

{SEPARATOR}'''


#——————————————————————————————————————————————————————————————————————


def generate_source(
    version: str,
    modules: dict[str, SourceModule],
    function_exports: Sequence[FunctionExport],
    type_exports: Sequence[TypeExport],
) -> str:
    required_module_keys = get_required_module_keys(function_exports, type_exports)

    sections = (
        render_header(version),
        render_imports(modules, required_module_keys),
        render_types(type_exports),
        render_functions(function_exports),
        render_custom_api(modules),
        "return module",
    )

    return "\n\n".join(section.rstrip() for section in sections) + "\n"


#——————————————————————————————————————————————————————————————————————


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)

    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.",
        suffix=".tmp",
        dir=path.parent,
        text=True,
    )
    temporary_path = Path(temporary_name)

    try:
        with os.fdopen(
            descriptor,
            "w",
            encoding="utf-8",
            newline="\n",
        ) as file:
            file.write(content)
            file.flush()
            os.fsync(file.fileno())

        os.replace(temporary_path, path)
    except BaseException:
        temporary_path.unlink(missing_ok=True)
        raise


#——————————————————————————————————————————————————————————————————————


def validate_custom_dependencies(modules: dict[str, SourceModule]) -> None:
    required_functions = {
        "combinators/control": {"sleep"},
        "core/promise": {
            "getDiagnosticsStats",
            "getPendingSnapshots",
            "getStatusTable",
            "new",
            "resolve",
        },
    }

    required_types = {
        "core/promise": {
            "cancellationToken",
            "diagnosticsSnapshot",
            "diagnosticsStats",
            "promise",
        },
    }

    for module_key, function_names in required_functions.items():
        source_module = modules.get(module_key)

        if source_module is None:
            raise RuntimeError(
                f'Custom API requires missing module "{module_key}".'
            )

        for function_name in sorted(function_names):
            if function_name in source_module.functions:
                continue

            raise RuntimeError(
                f'Custom API requires missing function '
                f'"{module_key}.{function_name}".'
            )

    for module_key, type_names in required_types.items():
        source_module = modules.get(module_key)

        if source_module is None:
            raise RuntimeError(
                f'Custom API requires missing module "{module_key}".'
            )

        for type_name in sorted(type_names):
            if type_name in source_module.types:
                continue

            raise RuntimeError(
                f'Custom API requires missing type "{module_key}.{type_name}".'
            )


#——————————————————————————————————————————————————————————————————————


def resolve_project_root(arguments: argparse.Namespace) -> Path:
    if arguments.root is not None:
        root = Path(arguments.root).expanduser().resolve()

        if not (root / "src").is_dir():
            raise RuntimeError(
                f'Invalid --root "{root}". Expected "{root / "src"}" to exist.'
            )

        return root

    script_directory = Path(__file__).resolve().parent
    return find_project_root(script_directory)


#——————————————————————————————————————————————————————————————————————


def build_generation(arguments: argparse.Namespace) -> tuple[Path, GenerationResult]:
    project_root = resolve_project_root(arguments)
    source_directory = project_root / "src"
    output_path = source_directory / OUTPUT_NAME

    module_keys = discover_module_keys(source_directory)
    variable_names = create_variable_names(module_keys)
    modules: dict[str, SourceModule] = {}

    for module_key in module_keys:
        path = source_directory / f"{module_key}.luau"
        source_module = parse_module(
            source_directory,
            path,
            variable_names[module_key],
        )
        modules[module_key] = source_module

    validate_custom_dependencies(modules)

    function_exports = build_function_exports(modules)
    type_exports = build_type_exports(modules)
    warnings = validate_public_documentation(
        function_exports,
        arguments.strict_docs,
    )
    version = read_version(project_root, output_path, arguments.version)
    generated = generate_source(
        version,
        modules,
        function_exports,
        type_exports,
    )

    return output_path, GenerationResult(
        source=generated,
        module_count=len(modules),
        public_function_count=len(function_exports) + len(CUSTOM_PUBLIC_NAMES),
        public_type_count=len(type_exports),
        warnings=warnings,
        version=version,
    )


#——————————————————————————————————————————————————————————————————————


def print_generation_details(
    arguments: argparse.Namespace,
    output_path: Path,
    result: GenerationResult,
) -> None:
    if arguments.verbose:
        print(f"Project: {output_path.parent.parent}", file=sys.stderr)
        print(f"Version: {result.version}", file=sys.stderr)
        print(f"Discovered modules: {result.module_count}", file=sys.stderr)
        print(
            f"Public functions: {result.public_function_count}",
            file=sys.stderr,
        )
        print(f"Public types: {result.public_type_count}", file=sys.stderr)

    for warning in result.warnings:
        print(f"generateInit.py warning: {warning}", file=sys.stderr)


#——————————————————————————————————————————————————————————————————————


def generate(arguments: argparse.Namespace, *, quiet_unchanged: bool = False) -> int:
    output_path, result = build_generation(arguments)
    print_generation_details(arguments, output_path, result)

    if arguments.dry_run:
        sys.stdout.write(result.source)
        return 0

    current = ""

    if output_path.is_file():
        try:
            current = output_path.read_text(encoding="utf-8")
        except OSError as error:
            raise RuntimeError(f'Unable to read "{output_path}": {error}') from error

    if arguments.check:
        if current == result.source:
            print(f"{PACKAGE_NAME} init.luau is up to date.")
            return 0

        print(f"{PACKAGE_NAME} init.luau is out of date.", file=sys.stderr)
        print("Run:", file=sys.stderr)
        print("  python3 .vscode/scripts/generateInit.py", file=sys.stderr)
        return 1

    if current == result.source:
        if not quiet_unchanged:
            print(f"No changes: {output_path}")

        return 0

    atomic_write(output_path, result.source)
    print(f"Generated: {output_path}")
    return 0


#——————————————————————————————————————————————————————————————————————


def get_watch_signature(project_root: Path) -> str:
    digest = hashlib.sha256()
    source_directory = project_root / "src"
    output_path = (source_directory / OUTPUT_NAME).resolve()

    paths = sorted(source_directory.rglob("*.luau"))

    version_paths = (
        project_root / "package.json",
        project_root / "manifest.json",
        project_root / "wally.toml",
    )

    paths.extend(path for path in version_paths if path.is_file())

    for path in sorted(paths, key=lambda value: value.as_posix()):
        if path.resolve() == output_path:
            continue

        try:
            stat = path.stat()
        except FileNotFoundError:
            continue

        relative = path.relative_to(project_root).as_posix()
        digest.update(relative.encode("utf-8"))
        digest.update(b"\0")
        digest.update(str(stat.st_mtime_ns).encode("utf-8"))
        digest.update(b"\0")
        digest.update(str(stat.st_size).encode("utf-8"))
        digest.update(b"\0")

    return digest.hexdigest()


#——————————————————————————————————————————————————————————————————————


def watch(arguments: argparse.Namespace) -> int:
    project_root = resolve_project_root(arguments)
    source_directory = project_root / "src"

    print(f"Watching {PACKAGE_NAME} source: {source_directory}")
    print("Press Ctrl+C to stop.")

    initial_result = generate(arguments, quiet_unchanged=True)

    if initial_result != 0:
        return initial_result

    previous_signature = get_watch_signature(project_root)

    try:
        while True:
            time.sleep(arguments.interval)
            current_signature = get_watch_signature(project_root)

            if current_signature == previous_signature:
                continue

            time.sleep(WATCH_DEBOUNCE_SECONDS)
            current_signature = get_watch_signature(project_root)

            try:
                result = generate(arguments, quiet_unchanged=True)
            except RuntimeError as error:
                print(f"generateInit.py: {error}", file=sys.stderr)
                continue

            if result != 0:
                continue

            previous_signature = current_signature

    except KeyboardInterrupt:
        print(f"\nStopped {PACKAGE_NAME} init generator.")
        return 0


#——————————————————————————————————————————————————————————————————————


def create_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Generate Promily src/init.luau from the production public API."
        )
    )

    mode = parser.add_mutually_exclusive_group()

    mode.add_argument(
        "--check",
        action="store_true",
        help="Exit with status 1 when src/init.luau is not current.",
    )
    mode.add_argument(
        "--dry-run",
        action="store_true",
        help="Print generated source without writing it.",
    )
    mode.add_argument(
        "--watch",
        action="store_true",
        help="Watch src for module changes and regenerate automatically.",
    )

    parser.add_argument(
        "--strict-docs",
        action="store_true",
        help="Fail generation if a public function has no LDoc block.",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print discovered modules and public API counts.",
    )
    parser.add_argument(
        "--version",
        help=(
            "Override the generated Promily version. Without this option, the "
            "generator reads package metadata or preserves the current init.luau version."
        ),
    )
    parser.add_argument(
        "--root",
        help=(
            "Promily repository root. Normally unnecessary when the script lives "
            "under .vscode/scripts."
        ),
    )
    parser.add_argument(
        "--interval",
        type=float,
        default=DEFAULT_WATCH_INTERVAL,
        help=(
            "Watch polling interval in seconds. "
            f"Default: {DEFAULT_WATCH_INTERVAL}."
        ),
    )

    return parser


#——————————————————————————————————————————————————————————————————————


def validate_arguments(arguments: argparse.Namespace) -> None:
    if arguments.interval <= 0 or arguments.interval != arguments.interval:
        raise RuntimeError("--interval must be a positive finite number.")

    if arguments.interval == float("inf"):
        raise RuntimeError("--interval must be a positive finite number.")


#——————————————————————————————————————————————————————————————————————


def main() -> int:
    arguments = create_parser().parse_args()
    validate_arguments(arguments)

    if arguments.watch:
        return watch(arguments)

    return generate(arguments)


#——————————————————————————————————————————————————————————————————————


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as error:
        print(f"generateInit.py: {error}", file=sys.stderr)
        raise SystemExit(1)
