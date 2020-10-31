#!/bin/bash -eux
docker build . --tag dwarffortress
docker rm -f dwarffortress || true
docker run \
  --detach \
  --env DISPLAY_SETTINGS="1920x1080x24" \
  --publish 8080:8080 \
  --publish 8081:8081 \
  --rm \
  --name dwarffortress \
  dwarffortress
sleep 3
xdg-open http://localhost:8080
