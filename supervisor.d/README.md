# supervisor.d — Custom supervisord services

Every `*.conf` file in this directory is mounted into the container at
`/etc/supervisor/conf.d/` and included by supervisord (see the `[include]`
section at the bottom of `supervisord.conf`). One `[program:x]` block per
file, e.g. `supervisor.d/panwatch.conf`:

```ini
[program:panwatch]
command=/opt/data/apps/panwatch/run.sh
directory=/opt/data/apps/panwatch
user=hermes
autostart=true
autorestart=true
priority=40
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
```

Notes:

- Files live on the **host**, so custom services survive container
  recreation and image updates. This is the supported way to add services —
  never edit `/etc/supervisor/supervisord.conf` inside the container.
- Install service **code** under a mounted volume (`/opt/data/...` or
  `/workspace/...`), not inside the container filesystem, or it will be
  lost on recreation too.
- This `README.md` is not loaded by supervisord (only `*.conf` matches the
  include pattern). Keep private service configs in files ending in `.conf`;
  they stay on your server and are never baked into the image.

Apply changes without restarting the container:

```bash
docker exec hermes-suite supervisorctl reread
docker exec hermes-suite supervisorctl update
```
