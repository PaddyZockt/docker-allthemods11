# syntax=docker/dockerfile:1

FROM eclipse-temurin:25-jdk

LABEL version="0.14.0-beta"
LABEL org.opencontainers.image.source="https://github.com/PaddyZockt/docker-allthemods11"
LABEL org.opencontainers.image.description="All the Mods 11 Minecraft server that installs the newest server pack from CurseForge at start-up"

# uid 99 / gid 100 are the Unraid defaults (nobody:users), so /data is writable there without extra steps.
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl unzip jq ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && adduser --uid 99 --gid 100 --home /data --disabled-password --gecos "" minecraft

COPY launch.sh /launch.sh
RUN chmod 755 /launch.sh

USER minecraft
WORKDIR /data
VOLUME /data
EXPOSE 25565/tcp

CMD ["/launch.sh"]