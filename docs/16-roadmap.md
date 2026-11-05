[← Overview](../README.md)

# Roadmap

## Native Linux

- Image paste on native Linux: let `vnc-paste-proxy.py` read
  the host clipboard with `wl-paste` or `xclip` instead of
  `powershell.exe`. TigerVNC on Linux also only syncs text,
  so the proxy is needed there too.
- GPU on native Linux: pass `/dev/dri` into the container
  (Intel, AMD) or use the NVIDIA Container Toolkit.

## Desktop and tools

- Document Playwright MCP setups for common harnesses.
- Start menu: start Terminal, Chromium and Files through
  `swaymsg exec` so they don't block the bar.
- Don't open links from the container (`xdg-open`) directly
  in the container browser; show them for copying instead.
- Start the Cursor IDE example with `--password-store=basic`
  so the keyring question goes away.
- Use the host's time zone, e.g. with a read-only mount of
  `/etc/localtime`.
- Optionally other compositors: labwc for freely movable
  windows, Weston with RDP instead of VNC.

## Security

- Set up VNC authentication for wider use.
- Mask more secret patterns (e.g. `.npmrc`, `*.pem`,
  `*.key`).
- Add automated security tests.
