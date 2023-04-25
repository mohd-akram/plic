dnl usage: m4 -DSITE=<SITE> -DPORT=<PORT> -DACMEDIR=<DIR>
define(`NOLOG', `access_log off;
  error_log /dev/null;')dnl
define(`REDIRECT', `location / {
    return 301 https://SITE$request_uri;
  }')dnl
server {
  listen [::]:80;
  server_name SITE www.SITE;

  NOLOG

  location /.well-known/acme-challenge/ {
    alias ACMEDIR/;
  }

  REDIRECT
}

server {
  listen [::]:443 ssl http2;
  server_name www.SITE;

  NOLOG

  REDIRECT
}

server {
  listen [::]:443 ssl http2;
  server_name SITE;

  NOLOG

  add_header
    Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    always;

  location / {
    proxy_pass http://localhost:PORT;
  }
}
