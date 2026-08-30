#!/usr/bin/env python3
"""Convert the JSONC subset used by VS Code settings to strict JSON."""

import json
import sys


def strip_comments(source: str) -> str:
    output: list[str] = []
    index = 0
    in_string = False
    escaped = False

    while index < len(source):
        char = source[index]
        following = source[index + 1] if index + 1 < len(source) else ""

        if in_string:
            output.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
            continue

        if char == '"':
            in_string = True
            output.append(char)
            index += 1
        elif char == "/" and following == "/":
            index += 2
            while index < len(source) and source[index] not in "\r\n":
                index += 1
        elif char == "/" and following == "*":
            index += 2
            while index + 1 < len(source) and source[index : index + 2] != "*/":
                output.append("\n" if source[index] == "\n" else " ")
                index += 1
            if index + 1 >= len(source):
                raise ValueError("comentário de bloco JSONC não terminado")
            index += 2
        else:
            output.append(char)
            index += 1

    if in_string:
        raise ValueError("string JSONC não terminada")
    return "".join(output)


def strip_trailing_commas(source: str) -> str:
    output: list[str] = []
    index = 0
    in_string = False
    escaped = False

    while index < len(source):
        char = source[index]
        if in_string:
            output.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
            continue

        if char == '"':
            in_string = True
        elif char == ",":
            lookahead = index + 1
            while lookahead < len(source) and source[lookahead].isspace():
                lookahead += 1
            if lookahead < len(source) and source[lookahead] in "}]":
                index += 1
                continue
        output.append(char)
        index += 1

    return "".join(output)


def main() -> int:
    try:
        source = strip_trailing_commas(strip_comments(sys.stdin.read()))
        value = json.loads(source)
    except (ValueError, json.JSONDecodeError) as error:
        print(f"JSONC inválido: {error}", file=sys.stderr)
        return 1

    json.dump(value, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
