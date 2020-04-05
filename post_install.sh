#!/bin/sh
# Initialize defaults
HOST_NAME="nextcloud.domain.tld"
DL_FLAGS="tls.dns.azure"
DNS_SETTING="dns azure"
TIME_ZONE="Europe/Vienna"
JAIL_IP=$(ifconfig epair0b | grep inet | cut -w -f3)
CERT_EMAIL="email@domain.tld"
DNS_ENV="AZURE_CLIENT_ID=xxx AZURE_CLIENT_SECRET=xxx AZURE_SUBSCRIPTION_ID=xxx AZURE_TENANT_ID=xxx AZURE_RESOURCE_GROUP=xxx AZURE_METADATA_ENDPOINT=https://login.microsoftonline.com/"
DB_ROOT_PASSWORD=$(openssl rand -base64 16)
DB_PASSWORD=$(openssl rand -base64 16)
ADMIN_PASSWORD=$(openssl rand -base64 12)
TMP_FOLDER="/tmp/U0XfaFP10hh2lTMH"

#####
# Folder Creation and Permissions
#####
#DB
mkdir -p /var/db/mysql
chown -R 88:88 /var/db/mysql
#config
mkdir -p /usr/local/www/nextcloud/config
#files
mkdir -p /mnt/files
chown -R www:www /mnt/files
chmod -R 770 /mnt/files
#####
# Additional Dependency installation
#####
portsnap fetch extract
sh -c "make -C /usr/ports/www/php73-opcache clean install BATCH=yes"
sh -c "make -C /usr/ports/devel/php73-pcntl clean install BATCH=yes"
fetch -o /tmp https://getcaddy.com
if ! bash -s personal "${DL_FLAGS}" < /tmp/getcaddy.com
then
	echo "Failed to download/install Caddy"
	exit 1
fi

#####
# Configuration and Nextcloud installation  
#####
FILE="latest-18.tar.bz2"
if ! fetch -o /tmp https://download.nextcloud.com/server/releases/"${FILE}" https://download.nextcloud.com/server/releases/"${FILE}".asc https://nextcloud.com/nextcloud.asc
then
	echo "Failed to download Nextcloud"
	exit 1
fi
gpg --import /tmp/nextcloud.asc
if ! gpg --verify /tmp/"${FILE}".asc
then
	echo "GPG Signature Verification Failed!"
	echo "The Nextcloud download is corrupt."
	exit 1
fi
tar xjf /tmp/"${FILE}" -C /usr/local/www/
chown -R www:www /usr/local/www/nextcloud/
sysrc mysql_enable="YES"
sysrc redis_enable="YES"
sysrc php_fpm_enable="YES"

# Copy and edit pre-written config files
cp -f ${TMP_FOLDER}/php.ini /usr/local/etc/php.ini
cp -f ${TMP_FOLDER}/redis.conf /usr/local/etc/redis.conf
cp -f ${TMP_FOLDER}/www.conf /usr/local/etc/php-fpm.d/
cp -f ${TMP_FOLDER}/Caddyfile /usr/local/www/
cp -f ${TMP_FOLDER}/caddy /usr/local/etc/rc.d/
chmod 555 /usr/local/etc/rc.d/caddy
cp -f ${TMP_FOLDER}/my-system.cnf /var/db/mysql/my.cnf

sed -i '' "s/yourhostnamehere/${HOST_NAME}/" /usr/local/www/Caddyfile
sed -i '' "s/DNS-PLACEHOLDER/${DNS_SETTING}/" /usr/local/www/Caddyfile
sed -i '' "s/JAIL-IP/${JAIL_IP}/" /usr/local/www/Caddyfile
sed -i '' "s|mytimezone|${TIME_ZONE}|" /usr/local/etc/php.ini

sysrc caddy_enable="YES"
sysrc caddy_cert_email="${CERT_EMAIL}"
sysrc caddy_env="${DNS_ENV}"

#start services
service mysql-server start
service redis start
service php-fpm start
service caddy start

# Secure database, set root password, create Nextcloud DB, user, and password
mysql -u root -e "CREATE DATABASE nextcloud;"
mysql -u root -e "GRANT ALL ON nextcloud.* TO nextcloud@localhost IDENTIFIED BY '${DB_PASSWORD}';"
mysql -u root -e "DELETE FROM mysql.user WHERE User='';"
mysql -u root -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
mysql -u root -e "DROP DATABASE IF EXISTS test;"
mysql -u root -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
mysql -u root -e "UPDATE mysql.user SET Password=PASSWORD('${DB_ROOT_PASSWORD}') WHERE User='root';"
mysqladmin reload
cp -f ${TMP_FOLDER}/my.cnf /root/.my.cnf
sed -i '' "s|mypassword|${DB_ROOT_PASSWORD}|" /root/.my.cnf

# CLI installation and configuration of Nextcloud
touch /var/log/nextcloud.log
chown www /var/log/nextcloud.log
su -m www -c "php /usr/local/www/nextcloud/occ maintenance:install --database=\"mysql\" --database-name=\"nextcloud\" --database-user=\"nextcloud\" --database-pass=\"${DB_PASSWORD}\" --database-host=\"localhost:/tmp/mysql.sock\" --admin-user=\"admin\" --admin-pass=\"${ADMIN_PASSWORD}\" --data-dir=\"/mnt/files\""
su -m www -c "php /usr/local/www/nextcloud/occ config:system:set mysql.utf8mb4 --type boolean --value=\"true\""
su -m www -c "php /usr/local/www/nextcloud/occ db:add-missing-indices"
su -m www -c "php /usr/local/www/nextcloud/occ db:convert-filecache-bigint --no-interaction"
su -m www -c "php /usr/local/www/nextcloud/occ config:system:set logtimezone --value=\"${TIME_ZONE}\""
su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set log_type --value="file"'
su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set logfile --value="/var/log/nextcloud.log"'
su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set loglevel --value="2"'
su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set logrotate_size --value="104847600"'
su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set memcache.local --value="\OC\Memcache\APCu"'
su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set redis host --value="/tmp/redis.sock"'
su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set redis port --value=0 --type=integer'
su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set memcache.locking --value="\OC\Memcache\Redis"'
su -m www -c "php /usr/local/www/nextcloud/occ config:system:set overwrite.cli.url --value=\"https://${HOST_NAME}/\""
su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set htaccess.RewriteBase --value="/"'
su -m www -c 'php /usr/local/www/nextcloud/occ maintenance:update:htaccess'
su -m www -c "php /usr/local/www/nextcloud/occ config:system:set trusted_domains 1 --value=\"${HOST_NAME}\""
su -m www -c "php /usr/local/www/nextcloud/occ config:system:set trusted_domains 2 --value=\"${JAIL_IP}\""
su -m www -c 'php /usr/local/www/nextcloud/occ app:enable encryption'
su -m www -c 'php /usr/local/www/nextcloud/occ encryption:enable'
su -m www -c 'php /usr/local/www/nextcloud/occ encryption:disable'
su -m www -c 'php /usr/local/www/nextcloud/occ background:cron'
su -m www -c 'php -f /usr/local/www/nextcloud/cron.php'
crontab -u www ${TMP_FOLDER}/www-crontab
echo "Nextcloud Configuration:" > /root/PLUGIN_INFO
echo "• Database: ${DB_NAME}/${DB_ROOT_PASSWORD}" >> /root/PLUGIN_INFO
echo "• Nextcloud database password: ${DB_PASSWORD}" >> /root/PLUGIN_INFO
echo "• Nextcloud administrator password: ${ADMIN_PASSWORD}" >> /root/PLUGIN_INFO
