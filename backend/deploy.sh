#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

container_name=liveness-backend
legacy_container_name=research-liveness-backend
image_name=liveness-backend
host_port=18080
previous_name="${container_name}-previous"
image_tag="${image_name}:${GITHUB_SHA:-local}"

command -v docker >/dev/null || { echo 'Docker tidak tersedia pada runner.' >&2; exit 1; }

port_owners() {
  docker ps \
    --filter "publish=${host_port}" \
    --format '{{.Names}}'
}

foreign_port_owners="$(port_owners | grep -Ev "^(${container_name}|${legacy_container_name})$" || true)"
if [ -n "$foreign_port_owners" ]; then
  echo "Port ${host_port} sedang dipakai container lain:" >&2
  printf '  %s\n' "$foreign_port_owners" >&2
  echo 'Hentikan container tersebut atau ubah host_port sebelum deploy.' >&2
  exit 1
fi

if docker container inspect "$previous_name" >/dev/null 2>&1; then
  echo "Container cadangan $previous_name sudah ada; periksa sebelum deploy ulang." >&2
  exit 1
fi

docker build --tag "$image_tag" .

had_previous=false
previous_original_name="$container_name"
rollback() {
  echo 'Deploy gagal; mengembalikan container sebelumnya.' >&2
  docker rm -f "$container_name" >/dev/null 2>&1 || true
  if [ "$had_previous" = true ]; then
    docker rename "$previous_name" "$previous_original_name"
    docker start "$previous_original_name"
  fi
}
trap rollback ERR

active_container_name=
if docker container inspect "$container_name" >/dev/null 2>&1; then
  active_container_name="$container_name"
fi
if docker container inspect "$legacy_container_name" >/dev/null 2>&1; then
  if [ -n "$active_container_name" ]; then
    echo "Container ${container_name} dan ${legacy_container_name} sama-sama ada; periksa runner sebelum deploy." >&2
    exit 1
  fi
  active_container_name="$legacy_container_name"
fi

if [ -n "$active_container_name" ]; then
  previous_original_name="$active_container_name"
  docker rename "$active_container_name" "$previous_name"
  had_previous=true
  docker stop "$previous_name"

  # Docker biasanya melepas published port segera setelah stop, tetapi pada
  # runner yang sibuk pelepasannya dapat tertunda sesaat.
  for attempt in {1..10}; do
    if [ -z "$(port_owners)" ]; then
      break
    fi
    if [ "$attempt" -eq 10 ]; then
      echo "Port ${host_port} belum dilepas setelah container lama dihentikan." >&2
      false
    fi
    sleep 1
  done
fi

docker run -d \
  --name "$container_name" \
  --restart unless-stopped \
  --publish "${host_port}:8000" \
  "$image_tag"

for attempt in {1..30}; do
  health="$(docker inspect --format '{{.State.Health.Status}}' "$container_name")"
  if [ "$health" = healthy ]; then
    break
  fi
  if [ "$health" = unhealthy ] || [ "$attempt" -eq 30 ]; then
    docker logs --tail 100 "$container_name" >&2
    false
  fi
  sleep 2
done

if [ "$had_previous" = true ]; then
  docker rm "$previous_name"
fi
trap - ERR
echo "Backend aktif pada port ${host_port}."
