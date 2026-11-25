set -eu
APP=/opt/ayugram-relay
DATA=/var/lib/ayugram-relay
id ayurelay >/dev/null 2>&1 || useradd --system --home "$DATA" --shell /usr/sbin/nologin ayurelay
install -d -o ayurelay -g ayurelay -m 700 "$DATA" "$DATA/do"
command -v nginx >/dev/null 2>&1 && command -v curl >/dev/null 2>&1 || { apt-get update -q; DEBIAN_FRONTEND=noninteractive apt-get install -y -q nginx curl openssl; }
if [ ! -x /usr/local/bin/workerd ]; then
  URL="$(curl -fsS https://registry.npmjs.org/@cloudflare/workerd-linux-64/latest | python3 -c 'import json,sys; print(json.load(sys.stdin)["dist"]["tarball"])')"
  TMP="$(mktemp -d)"
  curl -fsSL "$URL" | tar xz -C "$TMP"
  install -m 755 "$TMP/package/bin/workerd" /usr/local/bin/workerd
  rm -rf "$TMP"
fi
{
  echo 'using Workerd = import "/workerd/workerd.capnp";'
  echo 'const config :Workerd.Config = ('
  echo '  services = ['
  echo '    (name = "relay", worker = .relay),'
  echo '    (name = "internet", network = (allow = ["public"], tlsOptions = (trustBrowserCas = true))),'
  echo "    (name = \"storage\", disk = (path = \"$DATA/do\", writable = true)),"
  echo '  ],'
  echo '  sockets = [(name = "http", address = "127.0.0.1:8787", http = (), service = "relay")],'
  echo ');'
  echo 'const relay :Workerd.Worker = ('
  echo '  modules = ['
  echo '    (name = "worker.js", esModule = embed "worker.js"),'
  for f in "$APP"/*.js; do
    n="$(basename "$f")"
    [ "$n" = worker.js ] && continue
    echo "    (name = \"$n\", esModule = embed \"$n\"),"
  done
  echo '  ],'
  echo '  compatibilityDate = "2025-06-01",'
  echo '  bindings = ['
  for n in STATS_TOKEN REPORT_CHAT_ID REPORT_BOT_TOKEN REPORT_WEBHOOK_SECRET GROQ_API_KEY PRO_API_KEY GEMINI_API_KEY MODERATION_KEY CRYPTOPAY_TOKEN TONCENTER_KEY XROCKET_TOKEN XROCKET_WEBHOOK_TOKEN; do
    echo "    (name = \"$n\", fromEnvironment = \"$n\"),"
  done
  echo '    (name = "PRESENCE", durableObjectNamespace = "Presence"),'
  echo '    (name = "STATS", durableObjectNamespace = "Stats"),'
  echo '    (name = "PROFILES", durableObjectNamespace = "Profiles"),'
  echo '  ],'
  echo '  durableObjectNamespaces = ['
  echo '    (className = "Presence", uniqueKey = "ayugram-presence", enableSql = true),'
  echo '    (className = "Stats", uniqueKey = "ayugram-stats", enableSql = true),'
  echo '    (className = "Profiles", uniqueKey = "ayugram-profiles", enableSql = true),'
  echo '  ],'
  echo '  durableObjectStorage = (localDisk = "storage"),'
  echo '  globalOutbound = "internet",'
  echo ');'
} > "$APP/config.capnp"
cat > /etc/systemd/system/ayugram-relay.service <<EOF
[Unit]
Description=AyuGram relay
After=network-online.target
[Service]
User=ayurelay
EnvironmentFile=/etc/ayugram-relay.env
WorkingDirectory=$APP
ExecStart=/usr/local/bin/workerd serve $APP/config.capnp
Restart=always
RestartSec=2
MemoryMax=700M
[Install]
WantedBy=multi-user.target
EOF
cat > /etc/systemd/system/ayugram-relay-cron.service <<EOF
[Unit]
Description=AyuGram relay cron
[Service]
Type=oneshot
EnvironmentFile=/etc/ayugram-relay.env
ExecStart=/bin/sh -c 'curl -fsS -m 60 -X POST -H "x-cron: \$STATS_TOKEN" http://127.0.0.1:8787/__cron'
EOF
cat > /etc/systemd/system/ayugram-relay-cron.timer <<EOF
[Unit]
Description=AyuGram relay cron every 2 minutes
[Timer]
OnBootSec=2min
OnUnitActiveSec=2min
[Install]
WantedBy=timers.target
EOF
CERT=/etc/ssl/ayugram-relay
if [ ! -f "$CERT/cert.pem" ]; then
  install -d -m 700 "$CERT"
  openssl req -x509 -nodes -newkey rsa:2048 -days 3650 -subj "/CN=relay.mapixdev.com" -keyout "$CERT/key.pem" -out "$CERT/cert.pem" 2>/dev/null
fi
{
  echo 'real_ip_header CF-Connecting-IP;'
  for r in $(curl -fsS https://www.cloudflare.com/ips-v4) $(curl -fsS https://www.cloudflare.com/ips-v6); do echo "set_real_ip_from $r;"; done
  echo 'server {'
  echo '  listen 443 ssl default_server;'
  echo '  listen [::]:443 ssl default_server;'
  echo "  ssl_certificate $CERT/cert.pem;"
  echo "  ssl_certificate_key $CERT/key.pem;"
  echo '  client_max_body_size 12m;'
  echo '  location = /__cron { return 404; }'
  echo '  location / {'
  echo '    proxy_pass http://127.0.0.1:8787;'
  echo '    proxy_http_version 1.1;'
  echo '    proxy_set_header Host $host;'
  echo '    proxy_read_timeout 120s;'
  echo '    proxy_request_buffering off;'
  echo '  }'
  echo '}'
} > /etc/nginx/sites-available/ayugram-relay
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/ayugram-relay /etc/nginx/sites-enabled/ayugram-relay
iptables -C INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || { iptables -I INPUT 1 -p tcp --dport 443 -j ACCEPT; command -v netfilter-persistent >/dev/null 2>&1 && netfilter-persistent save >/dev/null 2>&1 || true; }
nginx -t
systemctl daemon-reload
systemctl enable --now ayugram-relay.service ayugram-relay-cron.timer
systemctl restart ayugram-relay.service
systemctl reload nginx || systemctl restart nginx
sleep 3
systemctl is-active ayugram-relay.service
curl -fsS -m 20 -o /dev/null -w "local %{http_code}\n" http://127.0.0.1:8787/ai/guide || journalctl -u ayugram-relay -n 40 --no-pager
