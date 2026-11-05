[← Overview](../README.md)

# Managing containers

## Start the desktop

```bash
./foxden.sh ~/projects/my-repo --desktop
```

## Show desktop logs

Logs of Sway, wayvnc, the start hooks of your layers and
the VNC proxy:

```bash
./foxden.sh ~/projects/my-repo --desktop-logs
```

## Stop the container

```bash
./foxden.sh ~/projects/my-repo --stop
```

After stopping, the launcher reports uncommitted changes in
the project. That doesn't prevent the stop. The same
applies to `--down`.

## Remove the container

```bash
./foxden.sh ~/projects/my-repo --down
```

A normal `--down` keeps the persistent agent home.

Only delete Docker volumes deliberately, since they can
hold harness sign-ins and other settings. To list
existing volumes:

```bash
docker volume ls | grep foxden
```

## Update the image

After changes to the `Dockerfile`, `agent-rules.md`,
`desktop/` or your layers, starting again through the
launch script is enough.

The script builds the base image and your layers on every
start; Docker's cache skips unchanged steps. If an image
changed, the container is recreated, and sessions running
in it end. The same happens when turning the GPU on or off.

To update downloaded tools, such as harnesses installed by
your layers, build without cache:

```bash
FOXDEN_REBUILD=1 ./foxden.sh ~/projects/my-repo --desktop
```

The base image is about 1.7 GB.
