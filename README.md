# [All the Mods 11-0.14.0-beta](https://www.curseforge.com/minecraft/modpacks/all-the-mods-11) server for Docker and Unraid

A Docker image that runs an **All the Mods 11** Minecraft server. At start-up it asks CurseForge for the newest server pack, installs it together with the NeoForge version the pack needs, and starts the server. When a new pack version appears, the image is rebuilt automatically, and a restarted container updates itself.

Unraid users: install it from the Apps tab (Community Applications) once it is listed there, or use the template at https://github.com/PaddyZockt/unraid-templates (`templates/allthemods11.xml`).

This repository is not affiliated with the All the Mods team or CurseForge. No mod files are inside the image; the pack is downloaded when the container starts.

## Quick start

```
docker run -d --name atm11 \
  -p 25565:25565 \
  -v /path/to/atm11-data:/data \
  -e EULA=true \
  -e CURSEFORGE_API_KEY=your-key \
  paddygametv/docker-allthemods11:latest
```

The first start downloads and installs the pack, which takes a few minutes. Follow it with `docker logs -f atm11`. Later starts only start the server, or update it when CurseForge offers a newer pack.

## Requirements

* `/data` on persistent storage. The container runs as uid 99 / gid 100 (the Unraid defaults); on other systems make `/data` writable for that user.
* Port 25565/tcp.
* `EULA=true`. By setting it you accept the [Minecraft EULA](https://aka.ms/MinecraftEULA).
* `CURSEFORGE_API_KEY`: your own free key from https://console.curseforge.com. CurseForge only serves server packs to requests with a key.
* About 8 GB of RAM for the server (see `JVM_OPTS`).

## Settings

All optional. Set them as environment variables.

| Variable | Meaning | Default |
|---|---|---|
| `JVM_OPTS` | Java options. Replaces the memory lines of `user_jvm_args.txt` | pack default |
| `MOTD` | Server list message | `A Minecraft Server` |
| `MAX_PLAYERS` | Player limit | `5` |
| `ONLINE_MODE` | `true` or `false`: check accounts with Mojang | `true` |
| `ALLOW_FLIGHT` | `true` or `false` | `true` |
| `ENABLE_WHITELIST` | `true` or `false` | `false` |
| `WHITELIST_USERS` | Comma separated names added to the whitelist, e.g. `Steve, Alex` | none |
| `OP_USERS` | Comma separated names that become operators (level 4) | none |
| `NEOFORGE_VERSION` | Only needed if the pack does not name its NeoForge version | detected |

Names are looked up through playerdb.co. Entries that are already listed are left alone.

## Troubleshooting

* **Container stops right away:** read the first log lines. They say what is missing (EULA, API key, download problem).
* **Permission errors on `/data`:** give uid 99 / gid 100 write access to the folder.
* **Install is incomplete or broken:** stop the container and delete `/data/.installed_server_version`. The next start installs the pack again; your world and `server.properties` stay.
* **CurseForge refuses the download:** check that the key is valid and that you copied all of it.