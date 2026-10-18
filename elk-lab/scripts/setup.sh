#!/usr/bin/env bash
set -euo pipefail
cd /usr/share/elasticsearch
if [ ! -f config/certs/ca/ca.crt ]; then
  mkdir -p config/certs
  bin/elasticsearch-certutil ca --silent --pem -out config/certs/ca.zip
  unzip -q config/certs/ca.zip -d config/certs
fi
if [ ! -f config/certs/es01/es01.crt ]; then
  cat > config/certs/instances.yml <<'YAML'
instances:
  - name: es01
    dns: [es01, localhost]
    ip: [127.0.0.1]
YAML
  bin/elasticsearch-certutil cert --silent --pem -out config/certs/certs.zip --in config/certs/instances.yml --ca-cert config/certs/ca/ca.crt --ca-key config/certs/ca/ca.key
  unzip -q config/certs/certs.zip -d config/certs
fi
# Keep signing keys only in the setup volume. Reuse existing CA/node identity.
mkdir -p config/certs/live
if [ ! -f config/certs/live/beats-ca.crt ]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 365 -subj /CN=elk-lab-beats-clients \
    -addext 'basicConstraints=critical,CA:TRUE' -addext 'keyUsage=critical,keyCertSign,cRLSign' \
    -keyout config/certs/live/beats-ca.key -out config/certs/live/beats-ca.crt
fi
issue() {
  local name=$1 usage=$2 san=$3 ca=$4 key=$5
  local dest=config/certs/live/$name
  if [ ! -f "$dest.crt" ]; then
    openssl req -new -newkey rsa:2048 -nodes -subj "/CN=$name" -keyout "$dest.key" -out "$dest.csr"
    printf 'basicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=%s\nsubjectAltName=%s\n' "$usage" "$san" > "$dest.ext"
    openssl x509 -req -in "$dest.csr" -CA "$ca" -CAkey "$key" -CAcreateserial -days 365 -sha256 -extfile "$dest.ext" -out "$dest.crt"
  fi
}
for name in logstash kibana nginx; do
  issue "$name" serverAuth "DNS:$name,DNS:localhost,IP:127.0.0.1" config/certs/ca/ca.crt config/certs/ca/ca.key
done
issue filebeat clientAuth DNS:filebeat config/certs/live/beats-ca.crt config/certs/live/beats-ca.key
# Monitoring API keystore: no plaintext management endpoint.
if [ ! -f config/certs/live/logstash-api.p12 ]; then
  openssl pkcs12 -export -name logstash -in config/certs/live/logstash.crt -inkey config/certs/live/logstash.key \
    -out config/certs/live/logstash-api.p12 -passout env:LOGSTASH_KEYSTORE_PASSWORD
fi
# Java Beats input requires an unencrypted PKCS#8 key.
if [ ! -f config/certs/live/logstash.pkcs8.key ]; then
  openssl pkcs8 -topk8 -nocrypt -in config/certs/live/logstash.key -out config/certs/live/logstash.pkcs8.key
fi
mkdir -p public-certs/ca service-certs/es01/es01 service-certs/es01/ca
publish() { if [ ! -f "$2" ]; then cp "$1" "$2"; fi; }
publish config/certs/ca/ca.crt public-certs/ca/ca.crt
publish config/certs/ca/ca.crt service-certs/es01/ca/ca.crt
publish config/certs/es01/es01.crt service-certs/es01/es01/es01.crt
publish config/certs/es01/es01.key service-certs/es01/es01/es01.key
for name in logstash kibana nginx filebeat; do
  mkdir -p "service-certs/$name"
  publish "config/certs/live/$name.crt" "service-certs/$name/$name.crt"
  publish "config/certs/live/$name.key" "service-certs/$name/$name.key"
done
publish config/certs/live/logstash.pkcs8.key service-certs/logstash/logstash.pkcs8.key
publish config/certs/live/logstash-api.p12 service-certs/logstash/logstash-api.p12
publish config/certs/live/beats-ca.crt service-certs/logstash/beats-ca.crt
# Nginx Basic authentication, separate from Elastic accounts.
if [ ! -f web-auth/htpasswd ]; then
  [[ "$WEB_PASSWORD" =~ ^[A-Za-z0-9]{20,}$ ]] || { echo 'WEB_PASSWORD requires 20+ alphanumeric characters' >&2; exit 1; }
  mkdir -p web-auth
  printf 'demo:%s\n' "$(printf '%s' "$WEB_PASSWORD" | openssl passwd -apr1 -stdin)" > web-auth/htpasswd
fi
chown -R root:root config/certs public-certs service-certs/nginx service-certs/filebeat
find config/certs service-certs web-auth -type d -exec chmod 750 {} \;
find config/certs service-certs web-auth -type f -exec chmod 640 {} \;
# Only public certificates are world-readable; no private keys in this volume.
find public-certs -type d -exec chmod 755 {} \;
find public-certs -type f -exec chmod 644 {} \;
# Elastic service images use UID 1000, but Logstash does not share root's group.
for name in es01 logstash kibana; do chown -R 1000:0 "service-certs/$name"; done
chown root:101 web-auth web-auth/htpasswd
echo 'TLS identities and web authentication ready; existing keys preserved.'
