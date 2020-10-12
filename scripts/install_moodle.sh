#!/bin/bash
# This script must be run as root (ex.: sudo sh [script_name])

# exit when any command fails
set -e
# keep track of the last executed command
trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
# echo an error message before exiting
trap 'echo "\"${last_command}\" command failed with exit code $?."' EXIT

# Helper functions
function echo_title {
    echo ""
    echo "###############################################################################"
    echo "$1"
    echo "###############################################################################"
}

function installMoodlePlugin {
    local pluginTitle=$1
    local pluginZipFileUrl=$2
    local pluginDirPath=$3

    echo "Installation of Moodle \"${pluginTitle}\" plugin."
    echo "Downloading \"${pluginTitle}\" plugin zip file..."
    wget $pluginZipFileUrl
    echo "Extracting \"${pluginTitle}\" plugin files..."
    unzip $(basename $pluginZipFileUrl) -d $pluginDirPath
    echo "Done with \"${pluginTitle}\" plugin installation."
}

###############################################################################
echo_title "Starting $0 on $(date)."
###############################################################################

###############################################################################
echo_title 'Read input parameters.'
###############################################################################
echo 'Initializing expected parameters array...'
declare -A parameters=( [dbServerAdminPassword]= \
                        [dbServerAdminUsername]= \
                        [dbServerFqdn]= \
                        [dbServerName]= \
                        [fileShareName]= \
                        [moodleAdminEmail]= \
                        [moodleAdminPassword]= \
                        [moodleAdminUsername]= \
                        [moodleDbName]= \
                        [moodleDbPassword]= \
                        [moodleDbUsername]= \
                        [moodleFqdn]= \
                        [moodleUpgradeKey]= \
                        [redisHostName]= \
                        [redisName]= \
                        [redisPrimaryKey]= \
                        [smtpRelayFqdn]= \
                        [smtpRelayPrivateIp]= \
                        [storageAccountEndPoint]= \
                        [storageAccountKey]= \
                        [storageAccountName]= )

sortedParameterList=$(echo ${!parameters[@]} | tr " " "\n" | sort | tr "\n" " ");

echo "Mapping input parameter values and checking for extra parameters..."
while [[ ${#@} -gt 0 ]];
do
    key=$1
    value=$2

    ## Test if the parameter key start with "-" and if the parameter key (without the first dash) is in the expected parameter list.
    if [[ ${key} =~ ^-.*$ && ${parameters[${key:1}]+_} ]]; then
        parameters[${key:1}]="$value"
    else
        echo "ERROR: Unexpected parameter: $key"
        extraParameterFlag=true;
    fi

    # Move to the next key/value pair or up to the end of the parameter list.
    shift $(( 2 < ${#@} ? 2 : ${#@} ))
done

echo "Checking for missing parameters..."
for p in $sortedParameterList; do
    if [[ -z ${parameters[$p]} ]]; then
        echo "ERROR: Missing parameter: $p."
        missingParameterFlag=true;
    fi
done

# Abort if missing or extra parameters.
if [[ -z $extraParameterFlag && -z $missingParameterFlag ]]; then
    echo "INFO: No missing or extra parameters."
else
    echo "ERROR: Execution aborted due to missing or extra parameters."
    usage="USAGE: $(basename $0)"
    for p in $sortedParameterList; do
        usage="${usage} -${p} \$${p}"
    done
    echo "${usage}";
    exit 1;
fi

echo 'Echo parameter values for debug purposes...'
for p in $sortedParameterList; do
    echo "DEBUG: $p = \"${parameters[$p]}\""
done
echo "Done."

###############################################################################
echo_title "Set useful variables."
###############################################################################
apache2DefaultDocumentRootDirPath="/var/www/html"
apache2ConfEnabledSecurityFilePath="/etc/apache2/conf-enabled/security.conf"
apache2SitesEnabledDefaultFilePath="/etc/apache2/sites-enabled/000-default.conf"
apache2User="www-data"
hostsFilePath="/etc/hosts"
installDirPath="$(pwd)"
moodleDocumentRootDirPath="${apache2DefaultDocumentRootDirPath}/moodle"
moodleLocalCacheRootDirPath="${apache2DefaultDocumentRootDirPath}/moodlelocalcache"
phpIniFilePath="/etc/php/7.2/apache2/php.ini"
echo "Done."

###############################################################################
echo_title "Update and upgrade the server."
###############################################################################
apt-get update
apt-get upgrade -y
echo "Done."

###############################################################################
echo_title "Install tools."
###############################################################################
apt-get install postgresql-client-10 php-cli unzip -y
echo "Done."

###############################################################################
echo_title "Install Moodle dependencies."
###############################################################################
apt-get install apache2 libapache2-mod-php -y
apt-get install graphviz aspell ghostscript clamav php7.2-pspell php7.2-curl php7.2-gd php7.2-intl php7.2-pgsql php7.2-xml php7.2-xmlrpc php7.2-ldap php7.2-zip php7.2-soap php7.2-mbstring php7.2-redis -y
echo "Done."

###############################################################################
echo_title "Remove server packages that are no longer needed."
###############################################################################
apt-get autoremove -y
echo "Done."


###############################################################################
echo_title "Setup SMTP Relay."
###############################################################################
echo "Adding SMTP Relay Private IP address in ${hostsFilePath}..."
echo -e "\n# Redirect SMTP Relay FQDN to Private IP Address.\n${parameters[smtpRelayPrivateIp]}\t${parameters[smtpRelayFqdn]}" >> $hostsFilePath
echo "Done."

###############################################################################
echo_title "Update PHP config."
###############################################################################
echo "Updating upload_max_filesize and post_max_size settings in ${phpIniFilePath}..."
sed -i "s/upload_max_filesize.*/upload_max_filesize = 2048M/" $phpIniFilePath
sed -i "s/post_max_size.*/post_max_size = 2048M/" $phpIniFilePath
echo "Done."

###############################################################################
echo_title "Update Apache config."
###############################################################################
if ! grep -q "${moodleDocumentRootDirPath}" $apache2SitesEnabledDefaultFilePath; then
    echo "Updating Apache default site DocumentRoot property in ${apache2SitesEnabledDefaultFilePath}..."
    escapedApache2DefaultDocumentRootDirPath=$(sed -E 's/(\/)/\\\1/g' <<< ${apache2DefaultDocumentRootDirPath})
    escapedMoodleDocumentRootDirPath=$(sed -E 's/(\/)/\\\1/g' <<< ${moodleDocumentRootDirPath})
    sed -i -E "s/DocumentRoot[[:space:]]*${escapedApache2DefaultDocumentRootDirPath}/DocumentRoot ${escapedMoodleDocumentRootDirPath}/g" $apache2SitesEnabledDefaultFilePath
else
    echo "Skipping $apache2SitesEnabledDefaultFilePath file update: DocumentRoot already properly set."
fi

echo "Updating Apache ServerSignature and ServerToken directives in ${apache2ConfEnabledSecurityFilePath}..."
sed -i "s/^ServerTokens[[:space:]]*\(Full\|OS\|Minimal\|Minor\|Major\|Prod\)$/ServerTokens Prod/" $apache2ConfEnabledSecurityFilePath
sed -i "s/^ServerSignature[[:space:]]*\(On\|Off\|EMail\)$/ServerSignature Off/" $apache2ConfEnabledSecurityFilePath

echo "Restarting Apache2..."
service apache2 restart

echo "Done."

###############################################################################
echo_title "Create Moodle database user if not existing."
###############################################################################
echo "Creating and granting privileges to database user ${parameters[moodleDbUsername]}..."
export PGPASSWORD="${parameters[dbServerAdminPassword]}"
psql "host=${parameters[dbServerFqdn]} port=5432 dbname=postgres user=${parameters[dbServerAdminUsername]}@${parameters[dbServerName]} sslmode=require" << EOF
DO \$\$
BEGIN
    IF EXISTS ( SELECT FROM pg_catalog.pg_roles WHERE rolname='${parameters[moodleDbUsername]}' ) THEN
        RAISE WARNING 'user ${parameters[moodleDbUsername]} already existing. Skipping task.';
    ELSE
        CREATE USER ${parameters[moodleDbUsername]} WITH ENCRYPTED PASSWORD '${parameters[moodleDbPassword]}';
        GRANT ALL PRIVILEGES ON DATABASE ${parameters[moodleDbName]} TO ${parameters[moodleDbUsername]};
        RAISE INFO 'User ${parameters[moodleDbUsername]} created.';
    END IF;
END
\$\$;
EOF
echo "Done."

###############################################################################
echo_title "Mount Moodle data fileshare."
###############################################################################
if [ ! -d "/mnt/${parameters[fileShareName]}" ]; then
    echo "Creating /mnt/${parameters[fileShareName]} folder..."
    mkdir /mnt/${parameters[fileShareName]}
else
    echo "Skipping /mnt/${parameters[fileShareName]} creation."
fi
if [ ! -d "/etc/smbcredentials" ]; then
    echo "Creating /etc/smbcredentials folder..."
    mkdir /etc/smbcredentials
else
    echo "Skipping /etc/smbcredentials file creation."
fi
if [ ! -f "/etc/smbcredentials/openlearningmoodlesa.cred" ]; then
    echo "Creating /etc/smbcredentials/openlearningmoodlesa.cred file..."
    echo "username=${parameters[storageAccountName]}" >> /etc/smbcredentials/${parameters[storageAccountName]}.cred
    echo "password=${parameters[storageAccountKey]}" >> /etc/smbcredentials/${parameters[storageAccountName]}.cred
else
    echo "Skipping /etc/smbcredentials/openlearningmoodlesa.cred file creation."
fi
echo "Updating permission on /etc/smbcredentials/${parameters[storageAccountName]}.cred..."
chmod 600 /etc/smbcredentials/${parameters[storageAccountName]}.cred
if ! grep -q ${parameters[storageAccountName]} /etc/fstab; then
    echo "Updating /etc/fstab file..."
    echo "//$(echo ${parameters[storageAccountEndPoint]} | awk -F/ '{print $3}')/${parameters[fileShareName]} /mnt/${parameters[fileShareName]} cifs nofail,vers=3.0,credentials=/etc/smbcredentials/${parameters[storageAccountName]}.cred,dir_mode=0777,file_mode=0777,serverino" >> /etc/fstab
else
    echo "Skipping /etc/fstab file update."
fi
echo "Mounting all defined mount points..."
mount -a
echo "Done."

###############################################################################
echo_title "Create Moodle Local Cache directory."
###############################################################################
if [ -d ${moodleLocalCacheRootDirPath} ]; then
    echo "Deleting old ${moodleLocalCacheRootDirPath} folder..."
    rm -rf ${moodleLocalCacheRootDirPath}
fi
echo "Creating new ${moodleLocalCacheRootDirPath} folder..."
mkdir ${moodleLocalCacheRootDirPath}
echo "Updating file permission on ${moodleLocalCacheRootDirPath}..."
chown -R ${apache2User} ${moodleLocalCacheRootDirPath}
echo "Done."

###############################################################################
echo_title "Download and extract Moodle files and plugins."
###############################################################################
# Ref.: https://download.moodle.org/releases/supported/
echo "Downloading Moodle 3.8.4 tar file..."
wget https://download.moodle.org/download.php/direct/stable38/moodle-3.8.4.tgz
echo "Extracting moodle tar file..."
if [ -d ${moodleDocumentRootDirPath} ]; then
    echo "Deleting old ${moodleDocumentRootDirPath} folder..."
    rm -rf ${moodleDocumentRootDirPath}
fi
tar zxfv moodle-3.8.4.tgz -C ${apache2DefaultDocumentRootDirPath}

# Ref.: https://moodle.org/plugins/filter_multilang2
installMoodlePlugin "Filters: Multi-Language Content (v2)" \
                    "https://moodle.org/plugins/download.php/20674/filter_multilang2_moodle38_2019111900.zip" \
                    "${moodleDocumentRootDirPath}/filter"

# Ref.: https://moodle.org/plugins/mod_bigbluebuttonbn
installMoodlePlugin "Activities: BigBlueButtonBN" \
                    "https://moodle.org/plugins/download.php/21195/mod_bigbluebuttonbn_moodle38_2019042008.zip" \
                    "${moodleDocumentRootDirPath}/mod"

# Ref.: https://moodle.org/plugins/local_navbarplus
installMoodlePlugin "General plugins (Local): Navbar Plus" \
                    "https://moodle.org/plugins/download.php/21066/local_navbarplus_moodle38_2020021800.zip" \
                    "${moodleDocumentRootDirPath}/local"

# Ref.: https://moodle.org/plugins/block_qrcode
installMoodlePlugin "Blocks: QR code" \
                    "https://moodle.org/plugins/download.php/20732/block_qrcode_moodle38_2019112100.zip" \
                    "${moodleDocumentRootDirPath}/blocks"

# Ref.: https://moodle.org/plugins/mod_facetoface
installMoodlePlugin "Activities: Facetoface" \
                    "https://moodle.org/plugins/download.php/18183/mod_facetoface_moodle35_2018110900.zip" \
                    "${moodleDocumentRootDirPath}/mod"

# Ref.: https://moodle.org/plugins/mod_questionnaire
installMoodlePlugin "Activities: Questionnaire" \
                    "https://moodle.org/plugins/download.php/21849/mod_questionnaire_moodle39_2020011508.zip" \
                    "${moodleDocumentRootDirPath}/mod"

# Ref.: https://moodle.org/plugins/theme_boost_campus
installMoodlePlugin "Themes: Boost Campus" \
                    "https://moodle.org/plugins/download.php/21973/theme_boost_campus_moodle38_2020071400.zip" \
                    "${moodleDocumentRootDirPath}/theme"

# Ref.: https://moodle.org/plugins/local_staticpage
installMoodlePlugin "General plugins (Local): Static Pages" \
                    "https://moodle.org/plugins/download.php/21045/local_staticpage_moodle38_2020021400.zip" \
                    "${moodleDocumentRootDirPath}/local"

# Ref.: https://moodle.org/plugins/mod_customcert
installMoodlePlugin "Activities: Custom certificate" \
                    "https://moodle.org/plugins/download.php/21208/mod_customcert_moodle38_2019111804.zip" \
                    "${moodleDocumentRootDirPath}/mod"

# Ref.: https://moodle.org/plugins/mod_hvp
installMoodlePlugin "Activities: Interactive Content – H5P" \
                    "https://moodle.org/plugins/download.php/21001/mod_hvp_moodle39_2020020500.zip" \
                    "${moodleDocumentRootDirPath}/mod"

# Ref.: https://moodle.org/plugins/mod_attendance
installMoodlePlugin "Activities: Attendance" \
                    "https://moodle.org/plugins/download.php/22326/mod_attendance_moodle39_2020082500.zip" \
                    "${moodleDocumentRootDirPath}/mod"

# Ref.: https://moodle.org/plugins/block_completion_progress
installMoodlePlugin "Blocks: Completion Progress" \
                    "https://moodle.org/plugins/download.php/22199/block_completion_progress_moodle39_2020081000.zip" \
                    "${moodleDocumentRootDirPath}/blocks"

# Ref.: https://moodle.org/plugins/availability_coursecompleted
installMoodlePlugin "Availability conditions: Restriction by course completion" \
                    "https://moodle.org/plugins/download.php/21684/availability_coursecompleted_moodle39_2020052401.zip" \
                    "${moodleDocumentRootDirPath}/availability/condition"

# Ref.: https://moodle.org/plugins/block_configurable_reports
installMoodlePlugin "Blocks: Configurable Reports" \
                    "https://moodle.org/plugins/download.php/20829/block_configurable_reports_moodle38_2019122000.zip" \
                    "${moodleDocumentRootDirPath}/blocks"

# Ref.: https://moodle.org/plugins/tool_coursedates
installMoodlePlugin "Admin tools: Set course dates" \
                    "https://moodle.org/plugins/download.php/22237/tool_coursedates_moodle39_2020081400.zip" \
                    "${moodleDocumentRootDirPath}/admin/tool"

# Ref.: https://moodle.org/plugins/local_mailtest
installMoodlePlugin "General plugins (Local): Moodle eMail Test" \
                    "https://moodle.org/plugins/download.php/22516/local_mailtest_moodle39_2020092000.zip" \
                    "${moodleDocumentRootDirPath}/local"

echo "Updating file ownership on ${moodleDocumentRootDirPath}..."
chown -R ${apache2User} ${moodleDocumentRootDirPath}
chgrp -R root ${moodleDocumentRootDirPath}

echo "Done."

###############################################################################
echo_title "Run Moodle Installer."
###############################################################################
# Assess whether the moodle tables already exist.
# If yes then add the "--skip-database" option to the install script.
export PGPASSWORD="${parameters[dbServerAdminPassword]}"
tablePrefix='mdl_'
tableCount=$(psql "host=${parameters[dbServerFqdn]} port=5432 user=${parameters[dbServerAdminUsername]}@${parameters[dbServerName]} dbname=${parameters[moodleDbName]} sslmode=require" --tuples-only --command="select count(*) from information_schema.tables where table_catalog='${parameters[moodleDbName]}' and table_name like '${tablePrefix}%'")
if [[ $tableCount -eq 0 ]]; then
    echo 'Moodle tables NOT found in database. Database must be setup as part of the install.'
    skipDatabaseOption=''
else
    echo 'Moodle tables found in database. Skipping database setup.'
    skipDatabaseOption='--skip-database'
fi

sudo -u ${apache2User} /usr/bin/php ${moodleDocumentRootDirPath}/admin/cli/install.php \
--non-interactive \
--lang=en \
--chmod=2777 \
--wwwroot=https://${parameters[moodleFqdn]}/ \
--dataroot=/mnt/${parameters[fileShareName]}/ \
--dbtype=pgsql \
--dbhost=${parameters[dbServerFqdn]} \
--dbname=${parameters[moodleDbName]} \
--prefix=$tablePrefix \
--dbport=5432 \
--dbuser=${parameters[moodleDbUsername]}@${parameters[dbServerName]} \
--dbpass="${parameters[moodleDbPassword]}" \
--fullname="Moodle" \
--shortname="Moodle" \
--summary="Welcome - Bienvenue" \
--adminuser=${parameters[moodleAdminUsername]} \
--adminpass="${parameters[moodleAdminPassword]}" \
--adminemail=${parameters[moodleAdminEmail]} \
--upgradekey=${parameters[moodleUpgradeKey]} \
${skipDatabaseOption} \
--agree-license

###############################################################################
echo_title "Update Moodle config for SSL Proxy and Local Cache directory."
###############################################################################
# No need to test for existing values since the file is always new.
echo "Adding SSL Proxy setting to ${moodleDocumentRootDirPath}/config.php file..."
sed -i '/^\$CFG->wwwroot.*/a \$CFG->sslproxy\t= true;' ${moodleDocumentRootDirPath}/config.php

echo "Adding Local Cache Directory setting to ${moodleDocumentRootDirPath}/config.php file..."
sed -i "/^\$CFG->dataroot.*/a \$CFG->localcachedir\t= '${moodleLocalCacheRootDirPath}';" ${moodleDocumentRootDirPath}/config.php

echo "Adding default timezone setting to ${moodleDocumentRootDirPath}/config.php file..."
sed -i "/^\$CFG->upgradekey.*/a date_default_timezone_set('America/Toronto');" ${moodleDocumentRootDirPath}/config.php

echo "Done"

###############################################################################
echo_title "Update Moodle Universal Cache (MUC) config for Redis."
###############################################################################
mucConfigFile="/mnt/${parameters[fileShareName]}/muc/config.php"
if ! grep -q ${parameters[redisName]} ${mucConfigFile}; then
    echo "Updating ${mucConfigFile} file..."
    php ${installDirPath}/update_muc.php ${parameters[redisHostName]} ${parameters[redisName]} ${parameters[redisPrimaryKey]} ${mucConfigFile}
else
    echo "Skipping ${mucConfigFile} file update."
fi
echo "Done"

###############################################################################
echo_title "Install plugins that have been recently added on the file system."
###############################################################################
sudo -u ${apache2User} /usr/bin/php ${moodleDocumentRootDirPath}/admin/cli/upgrade.php --non-interactive
echo "Done."

###############################################################################
echo_title "Uninstall plugings that have been recently removed from the file system."
###############################################################################
sudo -u ${apache2User} /usr/bin/php ${moodleDocumentRootDirPath}/admin/cli/uninstall_plugins.php --purge-missing --run
echo "Done."

###############################################################################
echo_title "Purge all Moodle Caches."
###############################################################################
sudo -u ${apache2User} /usr/bin/php ${moodleDocumentRootDirPath}/admin/cli/purge_caches.php
echo "Done"

###############################################################################
echo_title "Set Moodle Crontab."
###############################################################################
crontab -l | { cat; echo "* * * * * sudo -u www-data php ${moodleDocumentRootDirPath}/admin/cli/cron.php > /dev/null"; } | crontab -
echo "Done"

###############################################################################
echo_title "Finishing $0 on $(date)."
###############################################################################
trap - EXIT