#!/usr/bin/env bash
set -euo pipefail

if git grep -nE '(BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|AIza[0-9A-Za-z_-]{30,}|gh[pousr]_[0-9A-Za-z]{30,}|sk-[0-9A-Za-z]{20,})' -- ':!infra/scripts/secret-scan.sh'; then
  echo 'Potential secret detected.' >&2
  exit 1
fi

if git grep -nE '(Password|SigningKey|StationKey)"?[[:space:]]*[:=][[:space:]]*"[^"$<{]*(.{12,})"' -- ':!*.md' ':!.env.example'; then
  echo 'Potential hard-coded credential detected.' >&2
  exit 1
fi

echo 'No known credential pattern detected.'
