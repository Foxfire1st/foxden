[← Overview](../README.md)

# Internet access

The container uses the normal Docker bridge network.

There is:

- No extra web proxy.
- No domain allowlist.
- No artificial restriction to the endpoints of a harness.
- No second gateway container.

Normal internet connections work.

Examples:

```bash
curl -I https://example.com
npm view typescript version
python -m pip index versions requests
```

With this configuration, the container can also reach any
reachable services on the local network or the Docker
host, including ports of other containers published on
`0.0.0.0`.

This is explicitly not a network-isolated sandbox.
