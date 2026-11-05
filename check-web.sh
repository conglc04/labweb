
#!/usr/bin/env bash

for ip in 10.4.10.94 10.4.10.91 10.4.10.99; do
  echo "=== Web VM: $ip ==="
  curl --noproxy '*' -sS \
    --connect-timeout 2 --max-time 6 \
    -o /dev/null \
    -w 'HTTP=%{http_code} TIME=%{time_total}s\n' \
    "http://$ip/index.php"
done
