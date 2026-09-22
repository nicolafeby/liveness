#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

container_name=research-liveness-backend
image_name=research-liveness-backend
host_port=18080
previous_name="${container_name}-previous"
image_tag="${image_name}:${GITHUB_SHA:-local}"

command -v docker >/dev/null || { echo 'Docker tidak tersedia pada runner.' >&2; exit 1; }
if docker container inspect "$previous_name" >/dev/null 2>&1; then
  echo "Container cadangan $previous_name sudah ada; periksa sebelum deploy ulang." >&2
  exit 1
fi

docker build --tag "$image_tag" .

had_previous=false
rollback() {
  echo 'Deploy gagal; mengembalikan container sebelumnya.' >&2
  docker rm -f "$container_name" >/dev/null 2>&1 || true
  if [ "$had_previous" = true ]; then
    docker rename "$previous_name" "$container_name"
    docker start "$container_name"
  fi
}
trap rollback ERR

if docker container inspect "$container_name" >/dev/null 2>&1; then
  docker rename "$container_name" "$previous_name"
  had_previous=true
  docker stop "$previous_name"
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
