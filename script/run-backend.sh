#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../backend"

if ! command -v adb >/dev/null 2>&1; then
  echo "adb tidak ditemukan. Pasang Android platform-tools terlebih dahulu." >&2
  exit 1
fi

if [[ ! -x .venv/bin/uvicorn ]]; then
  echo "Virtualenv backend belum siap. Jalankan pip install -r backend/requirements.txt." >&2
  exit 1
fi

adb reverse tcp:8000 tcp:8000
echo "ADB reverse aktif: Android 127.0.0.1:8000 -> backend 127.0.0.1:8000"
exec .venv/bin/uvicorn main:app --host 127.0.0.1 --port 8000 --reload
