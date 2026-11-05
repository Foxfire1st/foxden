#!/usr/bin/env python3
"""VNC proxy that pastes Windows clipboard images into the sandbox.

    VNC viewer -> 127.0.0.1:VNC_PORT (this proxy, WSL) -> wayvnc (container)

Started by foxden.sh. VNC only carries text in its clipboard, so
images take this path instead.

The proxy reads the client -> server half of the RFB stream. When it sees a
Ctrl+V key press from the viewer, it holds that key event back, asks a
persistent powershell.exe for the Windows clipboard image, pushes it into the
container with `wl-copy --type image/png`, then forwards the key press.

Only key events that arrive from the viewer pass through here. Keys the agent
injects inside the container (wlrctl, wtype) never do, so the agent cannot
trigger a clipboard read.

The server -> client half is copied unchanged.
"""

import argparse
import asyncio
import base64
import logging
import struct
import subprocess
import sys
import time

log = logging.getLogger("vnc-paste-proxy")

TIMEOUT = 3.0  # seconds for the clipboard read and for the push
SETTLE = 0.05  # seconds between push and forwarding Ctrl+V

# ------------------------------------------------------------
# Windows clipboard helper (persistent powershell.exe)
# ------------------------------------------------------------
# Protocol on stdin/stdout: one command line in, one frame out.
# Frame: 4-byte big-endian length, then PNG bytes (length 0 = nothing).
#   ping -> empty frame (warm-up, does not touch the clipboard)
#   get  -> PNG if the clipboard holds an image and no text
# Clipboards with text (e.g. Excel cells, which also carry a bitmap) are
# left to TigerVNC's own text sync.
PS_SCRIPT = r"""
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$out = [Console]::OpenStandardOutput()

function Send-Frame([byte[]]$b) {
  $hdr = [BitConverter]::GetBytes([int32]$b.Length)
  [Array]::Reverse($hdr)
  $out.Write($hdr, 0, 4)
  if ($b.Length) { $out.Write($b, 0, $b.Length) }
  $out.Flush()
}

function Get-ClipboardPng {
  $d = [Windows.Forms.Clipboard]::GetDataObject()
  if (-not $d) { return ,[byte[]]@() }
  if ($d.GetDataPresent([Windows.Forms.DataFormats]::UnicodeText)) { return ,[byte[]]@() }

  $ms = New-Object IO.MemoryStream
  if ($d.GetDataPresent('PNG')) {
    $s = $d.GetData('PNG')
    $s.CopyTo($ms)
  } elseif ($d.GetDataPresent([Windows.Forms.DataFormats]::Bitmap)) {
    $img = [Windows.Forms.Clipboard]::GetImage()
    $img.Save($ms, [Drawing.Imaging.ImageFormat]::Png)
    $img.Dispose()
  }
  return ,$ms.ToArray()
}

while (($line = [Console]::In.ReadLine()) -ne $null) {
  $png = [byte[]]@()
  if ($line -eq 'get') {
    for ($try = 0; $try -lt 3; $try++) {
      try { $png = Get-ClipboardPng; break }
      catch {
        [Console]::Error.WriteLine("clipboard: " + $_.Exception.Message)
        Start-Sleep -Milliseconds 50
      }
    }
  }
  Send-Frame $png
}
"""


class ClipboardHelper:
    def __init__(self):
        self.proc = None
        self.lock = asyncio.Lock()

    async def _ensure(self):
        if self.proc is not None and self.proc.returncode is None:
            return
        enc = base64.b64encode(PS_SCRIPT.encode("utf-16-le")).decode()
        self.proc = await asyncio.create_subprocess_exec(
            "powershell.exe", "-NoLogo", "-NoProfile", "-NonInteractive",
            "-STA", "-EncodedCommand", enc,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE)

    async def _request(self, cmd):
        async with self.lock:
            await self._ensure()
            self.proc.stdin.write(cmd + b"\n")
            await self.proc.stdin.drain()
            (n,) = struct.unpack(">I", await self.proc.stdout.readexactly(4))
            return await self.proc.stdout.readexactly(n) if n else b""

    async def request(self, cmd, timeout):
        try:
            return await asyncio.wait_for(self._request(cmd), timeout)
        except BaseException:
            # A half-read frame would desync the protocol: start over.
            self.kill()
            raise

    def kill(self):
        if self.proc is not None and self.proc.returncode is None:
            self.proc.kill()
        self.proc = None


# ------------------------------------------------------------
# Push into the container
# ------------------------------------------------------------
async def push_png(container, png, timeout):
    # wl-copy forks and keeps serving the selection after docker exec ends.
    # Its child must not hold docker's stdout/stderr open, or docker exec
    # waits ~2 s for the streams before returning.
    script = ('set -a; . /tmp/agent-runtime/desktop.env; set +a; '
              'exec "$@" >/dev/null 2>&1')
    proc = await asyncio.create_subprocess_exec(
        "docker", "exec", "-i", container, "sh", "-c", script, "sh",
        "wl-copy", "--type", "image/png",
        stdin=subprocess.PIPE, stdout=subprocess.DEVNULL)
    try:
        await asyncio.wait_for(proc.communicate(png), timeout)
    except BaseException:
        proc.kill()
        raise
    if proc.returncode != 0:
        raise RuntimeError(f"docker exec wl-copy exited with {proc.returncode}")


# ------------------------------------------------------------
# RFB client -> server parsing
# ------------------------------------------------------------
KEYSYM_CTRL = {0xFFE3, 0xFFE4}  # Control_L, Control_R
KEYSYM_V = {0x76, 0x56}         # v, V

# Message types with a fixed total length (type byte included).
FIXED_LEN = {
    0: 20,    # SetPixelFormat
    3: 10,    # FramebufferUpdateRequest
    5: 6,     # PointerEvent
    150: 10,  # EnableContinuousUpdates
    250: 4,   # xvp
}


class KeyState:
    def __init__(self):
        self.ctrl = set()
        self.v_down = False

    def is_ctrl_v_press(self, down, keysym):
        """True only on the first press of V while Ctrl is held."""
        if keysym in KEYSYM_CTRL:
            if down:
                self.ctrl.add(keysym)
            else:
                self.ctrl.discard(keysym)
            return False
        if keysym in KEYSYM_V:
            trigger = bool(down) and not self.v_down and bool(self.ctrl)
            self.v_down = bool(down)  # auto-repeat sends more downs
            return trigger
        return False


async def copy_raw(reader, writer):
    while data := await reader.read(65536):
        writer.write(data)
        await writer.drain()


async def pump_client(reader, writer, on_ctrl_v, tag):
    """Forward viewer -> server, calling on_ctrl_v before a Ctrl+V press."""
    read = reader.readexactly

    async def fwd(*parts):
        writer.write(b"".join(parts))
        await writer.drain()

    async def give_up(reason):
        log.warning("%s: %s; Ctrl+V detection off for this connection",
                    tag, reason)
        await copy_raw(reader, writer)

    version = await read(12)
    await fwd(version)
    if version not in (b"RFB 003.008\n", b"RFB 003.007\n"):
        return await give_up(f"protocol version {version!r}")

    sec = await read(1)
    await fwd(sec)
    if sec[0] == 2:          # VNC auth: 16-byte challenge response
        await fwd(await read(16))
    elif sec[0] != 1:        # anything else (TLS, VeNCrypt) is opaque
        return await give_up(f"security type {sec[0]}")

    await fwd(await read(1))  # ClientInit
    log.info("%s: session up (security type %d)", tag, sec[0])

    keys = KeyState()
    while True:
        head = await read(1)
        mtype = head[0]

        if mtype in FIXED_LEN:
            await fwd(head, await read(FIXED_LEN[mtype] - 1))

        elif mtype == 2:  # SetEncodings
            hdr = await read(3)
            (count,) = struct.unpack(">H", hdr[1:3])
            await fwd(head, hdr, await read(4 * count))

        elif mtype == 4:  # KeyEvent
            body = await read(7)
            (keysym,) = struct.unpack(">I", body[3:7])
            if keys.is_ctrl_v_press(body[0], keysym):
                await on_ctrl_v()
            await fwd(head, body)

        elif mtype == 6:  # ClientCutText (negative length = extended)
            hdr = await read(7)
            (length,) = struct.unpack(">i", hdr[3:7])
            await fwd(head, hdr, await read(abs(length)))

        elif mtype == 248:  # ClientFence
            hdr = await read(8)
            await fwd(head, hdr, await read(hdr[7]))

        elif mtype == 251:  # SetDesktopSize
            hdr = await read(7)
            await fwd(head, hdr, await read(16 * hdr[5]))

        elif mtype == 255:  # QEMU client message
            sub = await read(1)
            if sub[0] != 0:
                await fwd(head, sub)
                return await give_up(f"QEMU subtype {sub[0]}")
            body = await read(10)  # down(2) keysym(4) keycode(4)
            (down, keysym) = struct.unpack(">HI", body[0:6])
            if keys.is_ctrl_v_press(down, keysym):
                await on_ctrl_v()
            await fwd(head, sub, body)

        else:
            await fwd(head)
            return await give_up(f"unknown message type {mtype}")


# ------------------------------------------------------------
# Proxy
# ------------------------------------------------------------
class Proxy:
    def __init__(self, opts):
        self.opts = opts
        self.clip = ClipboardHelper()
        self.conn_id = 0

    async def on_ctrl_v(self):
        t0 = time.monotonic()
        try:
            png = await self.clip.request(b"get", TIMEOUT)
        except Exception as e:
            log.warning("Ctrl+V: clipboard read failed: %r", e)
            return
        if not png:
            log.info("Ctrl+V: no image-only clipboard, passing through")
            return
        try:
            await push_png(self.opts.container, png, TIMEOUT)
        except Exception as e:
            log.warning("Ctrl+V: push failed: %r", e)
            return
        await asyncio.sleep(SETTLE)
        log.info("Ctrl+V: pushed %d KB PNG in %d ms", len(png) // 1024,
                 (time.monotonic() - t0) * 1000)

    async def handle(self, c_reader, c_writer):
        self.conn_id += 1
        tag = f"conn {self.conn_id}"
        log.info("%s: viewer connected from %s", tag,
                 c_writer.get_extra_info("peername"))
        try:
            s_reader, s_writer = await asyncio.open_connection(
                "127.0.0.1", self.opts.upstream_port)
        except OSError as e:
            log.error("%s: upstream unavailable: %s", tag, e)
            c_writer.close()
            return

        tasks = [
            asyncio.create_task(copy_raw(s_reader, c_writer)),
            asyncio.create_task(
                pump_client(c_reader, s_writer, self.on_ctrl_v, tag)),
        ]
        done, pending = await asyncio.wait(
            tasks, return_when=asyncio.FIRST_COMPLETED)
        for t in pending:
            t.cancel()
        for t in done:
            exc = t.exception()
            if exc and not isinstance(exc, (asyncio.IncompleteReadError,
                                            ConnectionError)):
                log.warning("%s: %r", tag, exc)
        for w in (c_writer, s_writer):
            w.close()
        log.info("%s: closed", tag)

    async def warm_up(self):
        try:
            await self.clip.request(b"ping", 15)
        except Exception as e:
            log.warning("powershell.exe unavailable, image paste off "
                        "until it works: %r", e)

    async def run(self):
        try:
            server = await asyncio.start_server(
                self.handle, "127.0.0.1", self.opts.listen_port)
        except OSError as e:
            log.error("cannot listen on 127.0.0.1:%d: %s",
                      self.opts.listen_port, e.strerror)
            sys.exit(1)
        log.info("listening on 127.0.0.1:%d -> 127.0.0.1:%d, container %.12s",
                 self.opts.listen_port, self.opts.upstream_port,
                 self.opts.container)
        self.warm_task = asyncio.create_task(self.warm_up())
        async with server:
            await server.serve_forever()


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--listen-port", type=int, required=True,
                   help="port for VNC viewers (VNC_PORT)")
    p.add_argument("--upstream-port", type=int, required=True,
                   help="loopback port published for wayvnc")
    p.add_argument("--container", required=True,
                   help="container to paste into")
    opts = p.parse_args()

    logging.basicConfig(level=logging.INFO, stream=sys.stderr,
                        format="%(asctime)s %(message)s",
                        datefmt="%Y-%m-%d %H:%M:%S")
    try:
        asyncio.run(Proxy(opts).run())
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
