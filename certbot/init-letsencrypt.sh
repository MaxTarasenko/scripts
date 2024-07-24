#!/bin/bash

# Check if the script is running with sudo
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run with sudo."
    exit 1
fi

# Check dc bin
if [ -x "$(command -v docker-compose)" ]; then
    DC_CMD="docker-compose"
elif [ -x "$(command -v docker compose)" ]; then
    DC_CMD="docker compose"
else
    echo 'Error: (docker-compose or docker compose) is not installed.' >&2
    exit 1
fi

# Function to validate domain
validate_domain() {
  local domain=$1
  if [[ $domain =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    return 0
  else
    return 1
  fi
}

# Set domains
while true; do
  read -p "Enter the domain(s) to create the certificate (comma-separated for multiple domains): " domains
  if [ -z "$domains" ]; then
    echo "Error: you need to enter at least one domain." >&2
    continue
  fi

  # Split domains into an array
  IFS=',' read -r -a domain_array <<< "$domains"

  # Validate each domain
  valid=true
  for domain in "${domain_array[@]}"; do
    domain=$(echo "$domain" | xargs)  # trim whitespace
    if ! validate_domain "$domain"; then
      echo "Invalid domain format: $domain" >&2
      valid=false
      break
    fi
  done

  if $valid; then
    break
  fi
done

main_domain=$(echo "${domain_array[0]}" | xargs)  # Первый домен будет основным

read -p "Enter the path to the folder to create the certificate (default=$HOME/docker_data/certbot): " data_path
: "${data_path:="$HOME/docker_data/certbot"}"

read -p "Enter a valid address is strongly recommended (default=register-unsafely-without-email): " email
: "${email:=""}"

read -p "Set to 1 if you're testing your setup to avoid hitting request limits (default=0): " staging
: "${staging:="0"}"

web_service="webserver"

rsa_key_size=4096

# Function to check if a certificate is valid
is_cert_valid() {
  local cert_path="$data_path/conf/live/$main_domain/fullchain.pem"
  if [ -f "$cert_path" ]; then
    local expiry_date
    expiry_date=$(openssl x509 -enddate -noout -in "$cert_path" | cut -d= -f2)
    local expiry_timestamp
    expiry_timestamp=$(date -d "$expiry_date" +%s)
    local current_timestamp
    current_timestamp=$(date +%s)
    if [ "$expiry_timestamp" -gt "$current_timestamp" ]; then
      return 0
    else
      return 1
    fi
  else
    return 1
  fi
}

# Check if certificate directory exists and ask for replacement if necessary
if [ -d "$data_path/conf/live/$main_domain" ]; then
  read -p "Existing data found for $main_domain. Continue and replace existing certificate? (y/N) " decision
  if [ "$decision" != "Y" ] && [ "$decision" != "y" ]; then
    exit 1
  fi
fi

if [ ! -e "$data_path/conf/options-ssl-nginx.conf" ] || [ ! -e "$data_path/conf/ssl-dhparams.pem" ]; then
  echo "### Downloading recommended TLS parameters ..."
  mkdir -p "$data_path/conf"
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf > "$data_path/conf/options-ssl-nginx.conf"
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem > "$data_path/conf/ssl-dhparams.pem"
  echo
fi

echo "### Creating dummy certificate for $main_domain ..."
path="/etc/letsencrypt/live/$main_domain"
mkdir -p "$data_path/conf/live/$main_domain"
$DC_CMD run --rm --entrypoint "\
  openssl req -x509 -nodes -newkey rsa:$rsa_key_size -days 1\
    -keyout '$path/privkey.pem' \
    -out '$path/fullchain.pem' \
    -subj '/CN=localhost'" certbot
echo

echo "### Starting nginx ..."
$DC_CMD up --force-recreate -d $web_service
echo

echo "### Deleting dummy certificate for $main_domain ..."
$DC_CMD run --rm --entrypoint "\
  rm -Rf /etc/letsencrypt/live/$main_domain && \
  rm -Rf /etc/letsencrypt/archive/$main_domain && \
  rm -Rf /etc/letsencrypt/renewal/$main_domain.conf" certbot
echo

echo "### Requesting Let's Encrypt certificate for domains: $domains ..."
# Select appropriate email arg
case "$email" in
  "") email_arg="--register-unsafely-without-email" ;;
  *) email_arg="--email $email" ;;
esac

# Enable staging mode if needed
if [ $staging != "0" ]; then staging_arg="--staging"; fi

# Join domains with -d flag
domain_args=""
for domain in "${domain_array[@]}"; do
  domain=$(echo "$domain" | xargs)  # trim whitespace
  domain_args="$domain_args -d $domain"
done

$DC_CMD run --rm --entrypoint "\
  certbot certonly --webroot -w /var/www/certbot \
    $staging_arg \
    $email_arg \
    $domain_args \
    --rsa-key-size $rsa_key_size \
    --agree-tos \
    --force-renewal" certbot
echo

echo "### Reloading nginx ..."
$DC_CMD exec $web_service nginx -s reload
