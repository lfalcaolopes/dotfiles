#!/usr/bin/env python3
"""Monta o settings.json do VS Code a partir do bloco gerenciado e do bloco local.

O bloco gerenciado é copiado literalmente do repositório, preservando
comentários e ordem. Abaixo de uma sentinela em comentário ficam as chaves
locais da máquina, que sobrevivem entre execuções. Chaves que o repositório
passa a gerenciar são removidas do bloco local, de modo que o repositório
vence sempre e nenhuma chave aparece duplicada.
"""

import argparse
import json
import re
from pathlib import Path

from jsonc_to_json import strip_comments, strip_trailing_commas

SENTINEL = "dotfiles:local"
SENTINEL_PATTERN = re.compile(rf"^[ \t]*//[ \t]*{re.escape(SENTINEL)}[ \t]*$")
BANNER = f"""\
  // ==========================================================================
  // {SENTINEL}
  // --------------------------------------------------------------------------
  // Acima: gerenciado por ~/dev/dotfiles/config/vscode/settings.json.
  //        Reescrito por inteiro a cada bootstrap.sh. Editar acima nao persiste.
  // Abaixo: preferencias locais desta maquina, preservadas entre execucoes.
  //         Para valer nas duas maquinas, mova a chave para o repo.
  //         Se o repo passar a gerenciar a chave, ela e removida daqui.
  // =========================================================================="""


def parse_jsonc(source: str, origin: str) -> dict:
    try:
        value = json.loads(strip_trailing_commas(strip_comments(source)))
    except (ValueError, json.JSONDecodeError) as error:
        raise SystemExit(f"JSONC inválido em {origin}: {error}")
    if not isinstance(value, dict):
        raise SystemExit(f"esperado objeto JSON em {origin}")
    return value


def split_at_sentinel(text: str) -> str | None:
    """Devolve o texto abaixo da sentinela, ou None se ela não existir."""
    lines = text.splitlines()
    for index, line in enumerate(lines):
        if SENTINEL_PATTERN.match(line):
            return "\n".join(lines[index + 1 :])
    return None


def strip_closing_brace(text: str, origin: str) -> str:
    body = text.rstrip()
    if not body.endswith("}"):
        raise SystemExit(f"{origin} não termina com '}}'")
    body = body[:-1].rstrip()
    if body.endswith(","):
        body = body[:-1]
    return body


def render_entry(key: str, value: object) -> str:
    rendered = json.dumps(value, ensure_ascii=False, indent=2)
    rendered = rendered.replace("\n", "\n  ")
    return f"  {json.dumps(key, ensure_ascii=False)}: {rendered}"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--managed", required=True, type=Path)
    parser.add_argument("--destination", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    arguments = parser.parse_args()

    managed_text = arguments.managed.read_text()
    if split_at_sentinel(managed_text) is not None:
        raise SystemExit(
            f"fonte gerenciada não pode conter a sentinela '{SENTINEL}': {arguments.managed}"
        )
    managed = parse_jsonc(managed_text, str(arguments.managed))

    local: dict[str, object] = {}
    divergent: list[str] = []

    if arguments.destination.exists():
        destination_text = arguments.destination.read_text()
        destination = parse_jsonc(destination_text, str(arguments.destination))

        below_text = split_at_sentinel(destination_text)
        if below_text is None:
            candidates = list(destination)
        else:
            candidates = list(parse_jsonc("{\n" + below_text, str(arguments.destination)))

        for key in candidates:
            if key not in managed and key in destination:
                local[key] = destination[key]

        for key, value in managed.items():
            if key in destination and destination[key] != value:
                divergent.append(
                    f"chave gerenciada divergente, repositório prevalece: {key} "
                    f"(local {json.dumps(destination[key], ensure_ascii=False)}, "
                    f"repo {json.dumps(value, ensure_ascii=False)})"
                )

    body = strip_closing_brace(managed_text, str(arguments.managed))
    parts = [body + ("," if local else ""), "", BANNER, ""]
    if local:
        parts.append(",\n".join(render_entry(key, value) for key, value in local.items()))
    parts.append("}")
    arguments.output.write_text("\n".join(parts) + "\n")

    for message in divergent:
        print(message)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
