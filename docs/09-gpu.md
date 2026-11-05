[← Overview](../README.md)

# GPU

WSL2 only. On native Linux the GPU isn't supported yet
([Roadmap](16-roadmap.md)).

Programs in the container can optionally use the GPU of the
Windows host. WSL provides it as `/dev/dxg`, and Mesa
translates OpenGL to DirectX 12 with the `d3d12` driver.

Sway itself still renders in software, because WSL doesn't
provide a DRM device. The VNC transfer also runs on the
CPU. The GPU speeds up drawing inside the programs, such as
WebGL in Chromium and the interface of an IDE.

## Turn on and off

The GPU is on as long as the file `~/.config/foxden/gpu`
exists. Its content selects the GPU:

```bash
echo NVIDIA > ~/.config/foxden/gpu   # NVIDIA GPU
: > ~/.config/foxden/gpu             # default GPU (usually the integrated one)
rm ~/.config/foxden/gpu              # off
```

Then restart the container:

```bash
./foxden.sh ~/projects/my-repo --desktop
```

The launcher then shows e.g. `GPU: NVIDIA`. Switching
recreates the container, and running sessions end.
Reconnect the VNC viewer.

The file is outside the projects, so the agent can't
change it. If the host lacks WSL GPU support, the launcher
aborts with an error.

With the GPU on, the container gets:

- the device `/dev/dxg`,
- `/usr/lib/wsl` read-only (WSL's DirectX libraries),
- `GALLIUM_DRIVER=d3d12`, `LD_LIBRARY_PATH=/usr/lib/wsl/lib`
  and, if set, `MESA_D3D12_DEFAULT_ADAPTER_NAME`.

Security note: see
[Security model](02-security-model.md), "GPU (optional)".

## Check

In a terminal on the desktop:

```bash
eglinfo -B -p wayland | grep -i renderer
```

| GPU | Output |
|---|---|
| off | `llvmpipe` (software) |
| on, NVIDIA | `D3D12 (NVIDIA GeForce RTX 4060 Laptop GPU)` |

In Chromium, https://webglreport.com shows the renderer
under "Unmasked Renderer".

## Measurement from 2026-10-29

WebGL demo "Aquarium" (webglsamples.org, 500 fish) in
Chromium, Intel Iris Xe and NVIDIA GeForce RTX 4060 Laptop
GPU, 20 CPU threads:

| | without GPU | with GPU (NVIDIA) |
|---|---|---|
| WebGL in Chromium | refused | WebGL 2 over D3D12 |
| Demo, software renderer forced | 7 fps, about 1300 % CPU | – |
| Demo with GPU | – | 59–60 fps, about 110 % CPU |
| Cursor IDE (Wayland, from a layer) | runs | runs, GPU process uses the NVIDIA driver |

## Limits

- Sway and VNC stay on the CPU.
- Rendered frames go to Sway through system memory.
- Under X11 the Cursor IDE doesn't start with the GPU.
  Wayland is the default and works.
- After driver updates on Windows, Mesa can fall back to
  software rendering. Check with `eglinfo` then.
