#!/bin/sh
# Initialize defaults
JAIL_IP=""
DEFAULT_GW_IP=""
INTERFACE="vnet0"
VNET="on"
POOL_PATH=""
JAIL_NAME="nextcloud"
TIME_ZONE=""
HOST_NAME=""
DATABASE="mariadb"
DB_PATH=""
FILES_PATH=""
PORTS_PATH=""
CONFIG_PATH=""
STANDALONE_CERT=0
SELFSIGNED_CERT=0
DNS_CERT=0
NO_CERT=0
DL_FLAGS="tls.dns.azure"
DNS_SETTING="dns azure"
RELEASE="11.3-RELEASE"
JAILS_MOUNT=$(zfs get -H -o value mountpo

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

mkdir -p /mnt/includes

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
