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

# Set domain
read -p "Enter the domain to create the certificate: " domain
if [ -z $domain ]; then
    echo "Error: you need to enter a domain." >&2
    exit 1
fi

read -p "Enter the path to the folder to create the certificate (default=$HOME/docker_data/certbot): " data_path
: "${data_path:="$HOME/docker_data/certbot"}"

read -p "Enter a valid address is strongly recommended (default=register-unsafely-without-email): " email
: "${email:=""}"

read -p "Set to 1 if you're testing your setup to avoid hitting request limits (default=0): " staging
: "${staging:="0"}"

web_service="webserver"

rsa_key_size=4096

if [ -d "$data_path" ]; then
  read -p "Existing data found for $domain. Continue and replace existing certificate? (y/N) " decision
  if [ "$decision" != "Y" ] && [ "$decision" != "y" ]; then
    exit
  fi
fi

if [ ! -e "$data_path/conf/options-ssl-nginx.conf" ] || [ ! -e "$data_path/conf/ssl-dhparams.pem" ]; then
  echo "### Downloading recommended TLS parameters ..."
  mkdir -p "$data_path/conf"
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf > "$data_path/conf/options-ssl-nginx.conf"
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem > "$data_path/conf/ssl-dhparams.pem"
  echo
fi

echo "### Creating dummy certificate for $domain ..."
path="/etc/letsencrypt/live/$domain"
mkdir -p "$data_path/conf/live/$domain"
$DC_CMD run --rm --entrypoint "\
  openssl req -x509 -nodes -newkey rsa:$rsa_key_size -days 1\
    -keyout '$path/privkey.pem' \
    -out '$path/fullchain.pem' \
    -subj '/CN=localhost'" certbot
echo

echo "### Starting nginx ..."
$DC_CMD up --force-recreate -d $web_service
echo

echo "### Deleting dummy certificate for $domain ..."
$DC_CMD run --rm --entrypoint "\
  rm -Rf /etc/letsencrypt/live/$domain && \
  rm -Rf /etc/letsencrypt/archive/$domain && \
  rm -Rf /etc/letsencrypt/renewal/$domain.conf" certbot
echo


echo "### Requesting Let's Encrypt certificate for $domain ..."
# Select appropriate email arg
case "$email" in
  "") email_arg="--register-unsafely-without-email" ;;
  *) email_arg="--email $email" ;;
esac

# Enable staging mode if needed
if [ $staging != "0" ]; then staging_arg="--staging"; fi

$DC_CMD run --rm --entrypoint "\
  certbot certonly --webroot -w /var/www/certbot \
    $staging_arg \
    $email_arg \
    -d $domain \
    --rsa-key-size $rsa_key_size \
    --agree-tos \
    --force-renewal" certbot
echo

echo "### Reloading nginx ..."
$DC_CMD exec $web_service nginx -s reload
