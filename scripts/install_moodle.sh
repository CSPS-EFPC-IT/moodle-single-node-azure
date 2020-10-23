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

function echo_action {
    echo ""
    echo "$1"
}

function echo_feedback {
    echo "-> $1"
}

function installMoodlePlugin {
    local pluginTitle=$1
    local pluginZipFileUrl=$2
    local pluginDirPath=$3

    echo_action "Installing Moodle \"${pluginTitle}\" plugin..."
    echo_feedback "Downloading \"${pluginTitle}\" plugin zip file..."
    wget $pluginZipFileUrl
    echo_feedback "Extracting \"${pluginTitle}\" plugin files..."
    unzip -q $(basename $pluginZipFileUrl) -d $pluginDirPath
    echo_feedback "Done."
}

###############################################################################
echo_title "Starting $0 on $(date)."
###############################################################################

###############################################################################
echo_title 'Read input parameters.'
###############################################################################
echo_action 'Initializing expected parameters array...'
declare -A parameters=(     [dataDiskSize]= \
                            [dbServerAdminPassword]= \
                            [dbServerAdminUsername]= \
                            [dbServerFqdn]= \
                            [dbServerName]= \
                            [moodleAdminEmail]= \
                            [moodleAdminPassword]= \
                            [moodleAdminUsername]= \
                            [moodleDbName]= \
                            [moodleDbPassword]= \
                            [moodleDbUsername]= \
                            [moodleFqdn]= \
                            [moodleUpgradeKey]= \
                            [smtpRelayFqdn]= \
                            [smtpRelayPrivateIp]=)

sortedParameterList=$(echo ${!parameters[@]} | tr " " "\n" | sort | tr "\n" " ");

echo_action "Mapping input parameter values and checking for extra parameters..."
while [[ ${#@} -gt 0 ]];
do
    key=$1
    value=$2

    ## Test if the parameter key start with "-" and if the parameter key (without the first dash) is in the expected parameter list.
    if [[ ${key} =~ ^-.*$ && ${parameters[${key:1}]+_} ]]; then
        parameters[${key:1}]="$value"
    else
        echo_feedback "ERROR: Unexpected parameter: $key"
        extraParameterFlag=true;
    fi

    # Move to the next key/value pair or up to the end of the parameter list.
    shift $(( 2 < ${#@} ? 2 : ${#@} ))
done

echo_action "Checking for missing parameters..."
for p in $sortedParameterList; do
    if [[ -z ${parameters[$p]} ]]; then
        echo_feedback "ERROR: Missing parameter: $p."
        missingParameterFlag=true;
    fi
done

# Abort if missing or extra parameters.
if [[ -z $extraParameterFlag && -z $missingParameterFlag ]]; then
    echo_feedback "INFO: No missing or extra parameters."
else
    echo_feedback "ERROR: Execution aborted due to missing or extra parameters."
    usage="USAGE: $(basename $0)"
    for p in $sortedParameterList; do
        usage="${usage} -${p} \$${p}"
    done
    echo_feedback "${usage}";
    exit 1;
fi

echo_action 'Echo parameter values for debug purposes...'
for p in $sortedParameterList; do
    echo_feedback "DEBUG: $p = \"${parameters[$p]}\""
done

echo_feedback "Done."

###############################################################################
echo_title "Set useful variables."
###############################################################################
apache2DefaultDocumentRootDirPath="/var/www/html"
apache2ConfEnabledSecurityFilePath="/etc/apache2/conf-enabled/security.conf"
apache2SitesEnabledDefaultFilePath="/etc/apache2/sites-enabled/000-default.conf"
apache2User="www-data"
hostsFilePath="/etc/hosts"
installDirPath="$(pwd)"
moodleDataMountPointPath="/moodledata"
moodleDocumentRootDirPath="${apache2DefaultDocumentRootDirPath}/moodle"
moodleLocalCacheRootDirPath="${apache2DefaultDocumentRootDirPath}/moodlelocalcache"
phpIniFilePath="/etc/php/7.2/apache2/php.ini"
echo_feedback "Done."

###############################################################################
echo_title "Update server package index files."
###############################################################################
apt-get update
echo_feedback "Done."

###############################################################################
echo_title "Upgrade all installed server packages."
###############################################################################
apt-get upgrade -y
echo_feedback "Done."

###############################################################################
echo_title "Install tools."
###############################################################################
apt-get install --yes --quiet postgresql-client-10 php-cli unzip
echo_feedback "Done."

###############################################################################
echo_title "Install Moodle dependencies."
###############################################################################
apt-get install --yes --quiet apache2 libapache2-mod-php redis
apt-get install --yes --quiet graphviz aspell ghostscript clamav php7.2-pspell php7.2-curl php7.2-gd php7.2-intl php7.2-pgsql php7.2-xml php7.2-xmlrpc php7.2-ldap php7.2-zip php7.2-soap php7.2-mbstring php7.2-redis
echo_feedback "Done."

###############################################################################
echo_title "Remove server packages that are no longer needed."
###############################################################################
apt-get autoremove -y
echo_feedback "Done."

###############################################################################
echo_title "Setup SMTP Relay."
###############################################################################
echo_action "Adding SMTP Relay Private IP address in ${hostsFilePath}..."
if ! grep -q "${parameters[smtpRelayFqdn]}" $hostsFilePath; then
    echo -e "\n# Redirect SMTP Relay FQDN to Private IP Address.\n${parameters[smtpRelayPrivateIp]}\t${parameters[smtpRelayFqdn]}" >> $hostsFilePath
    echo_feedback "Done."
else
    echo_feedback "Skipped: ${hostsFilePath} file already set up."
fi

###############################################################################
echo_title "Update PHP config."
###############################################################################
echo_action "Updating upload_max_filesize and post_max_size settings in ${phpIniFilePath}..."
sed -i "s/upload_max_filesize.*/upload_max_filesize = 2048M/" $phpIniFilePath
sed -i "s/post_max_size.*/post_max_size = 2048M/" $phpIniFilePath
echo_feedback "Done."

###############################################################################
echo_title "Update Apache config."
###############################################################################
if ! grep -q "${moodleDocumentRootDirPath}" $apache2SitesEnabledDefaultFilePath; then
    echo_action "Updating Apache default site DocumentRoot property in ${apache2SitesEnabledDefaultFilePath}..."
    escapedApache2DefaultDocumentRootDirPath=$(sed -E 's/(\/)/\\\1/g' <<< ${apache2DefaultDocumentRootDirPath})
    escapedMoodleDocumentRootDirPath=$(sed -E 's/(\/)/\\\1/g' <<< ${moodleDocumentRootDirPath})
    sed -i -E "s/DocumentRoot[[:space:]]*${escapedApache2DefaultDocumentRootDirPath}/DocumentRoot ${escapedMoodleDocumentRootDirPath}/g" $apache2SitesEnabledDefaultFilePath
else
    echo_feedback "Skipping $apache2SitesEnabledDefaultFilePath file update: DocumentRoot already properly set."
fi

echo_action "Updating Apache ServerSignature and ServerToken directives in ${apache2ConfEnabledSecurityFilePath}..."
sed -i "s/^ServerTokens[[:space:]]*\(Full\|OS\|Minimal\|Minor\|Major\|Prod\)$/ServerTokens Prod/" $apache2ConfEnabledSecurityFilePath
sed -i "s/^ServerSignature[[:space:]]*\(On\|Off\|EMail\)$/ServerSignature Off/" $apache2ConfEnabledSecurityFilePath

echo_action "Restarting Apache2..."
service apache2 restart

echo_feedback "Done."

###############################################################################
echo_title "Create Moodle database user if not existing."
###############################################################################
echo_action "Creating and granting privileges to database user ${parameters[moodleDbUsername]}..."
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
echo_feedback "Done."

###############################################################################
echo_title "Mount Moodle Data Disk."
###############################################################################
echo_action 'Retrieving the data disk block path using the data disk size as index...'
dataDiskBlockPath=/dev/$(lsblk --noheadings --output name,size | awk "{if (\$2 == \"${parameters[dataDiskSize]}\") print \$1}")
echo_feedback "Data disk block path found: $dataDiskBlockPath"

echo_action 'Creating a file system in the data disk block if none exists...'
dataDiskFileSystemType=$(lsblk --noheadings --output fstype $dataDiskBlockPath)
if [ -z $dataDiskFileSystemType ]; then
    echo_feedback "No file system detected on $dataDiskBlockPath."
    dataDiskFileSystemType=ext4
    echo "Creating file system of type $dataDiskFileSystemType on $dataDiskBlockPath..."
    mkfs.$dataDiskFileSystemType $dataDiskBlockPath
else
    echo_feedback "File system $dataDiskFileSystemType already exist on $dataDiskBlockPath."
fi

echo_action 'Retrieving data disk file System UUID...'
# Bug Fix:  Experience demonstrated that the UUID of the new file system is not immediately 
#           available through lsblk, thus we wait and loop for up to 60 seconds to get it.
elapsedTime=0
dataDiskFileSystemUuid=""
while [ -z "$dataDiskFileSystemUuid" -a "$elapsedTime" -lt "60" ]; do
    echo_feedback "Waiting for 1 second..."
    sleep 1
    dataDiskFileSystemUuid=$(lsblk --noheadings --output UUID ${dataDiskBlockPath})
    ((elapsedTime+=1))
done
echo_feedback "Data disk file system UUID: $dataDiskFileSystemUuid"

echo_action "Creating Moodle Data mount point..."
mkdir -p ${moodleDataMountPointPath}
echo_feedback "${moodleDataMountPointPath} directory created."

fstabFilePath=/etc/fstab
echo_action "Updating $fstabFilePath file to automount the data disk using its UUID..."
if ! grep -q "$dataDiskFileSystemUuid" $fstabFilePath; then
    printf "UUID=${dataDiskFileSystemUuid}\t${moodleDataMountPointPath}\t${dataDiskFileSystemType}\tdefaults,nofail\t0\t2\n" >> $fstabFilePath
    echo_feedback "Updated."
else
    echo_feedback "Skipped: already set up."
fi

echo_action 'Mounting all drives...'
mount -a

echo_action 'Setting permissions ...'
chown -R ${apache2User}:root ${moodleDataMountPointPath}
chmod -R 775 ${moodleDataMountPointPath}

echo_feedback "Done."

###############################################################################
echo_title "Create Moodle Local Cache directory."
###############################################################################
if [ -d ${moodleLocalCacheRootDirPath} ]; then
    echo_action "Deleting old ${moodleLocalCacheRootDirPath} folder..."
    rm -rf ${moodleLocalCacheRootDirPath}
fi

echo_action "Creating new ${moodleLocalCacheRootDirPath} folder..."
mkdir ${moodleLocalCacheRootDirPath}

echo_action "Updating file permission on ${moodleLocalCacheRootDirPath}..."
chown -R ${apache2User} ${moodleLocalCacheRootDirPath}

echo_feedback "Done."

###############################################################################
echo_title "Download and extract Moodle files and plugins."
###############################################################################
# Ref.: https://download.moodle.org/releases/supported/
echo_action "Downloading Moodle 3.8.4 tar file..."
wget https://download.moodle.org/download.php/direct/stable38/moodle-3.8.4.tgz

if [ -d ${moodleDocumentRootDirPath} ]; then
    echo_action "Deleting old ${moodleDocumentRootDirPath} folder..."
    rm -rf ${moodleDocumentRootDirPath}
fi

echo_action "Extracting moodle tar file..."
tar zxf moodle-3.8.4.tgz -C ${apache2DefaultDocumentRootDirPath}

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

echo_action "Updating file ownership on ${moodleDocumentRootDirPath}..."
chown -R ${apache2User}:root ${moodleDocumentRootDirPath}

echo_feedback "Done."

###############################################################################
echo_title "Run Moodle Installer."
###############################################################################
echo_action 'Assessing whether the moodle tables already exist...'
# If yes then add the "--skip-database" option to the install script.
export PGPASSWORD="${parameters[dbServerAdminPassword]}"
tablePrefix='mdl_'
tableCount=$(psql "host=${parameters[dbServerFqdn]} port=5432 user=${parameters[dbServerAdminUsername]}@${parameters[dbServerName]} dbname=${parameters[moodleDbName]} sslmode=require" --tuples-only --command="select count(*) from information_schema.tables where table_catalog='${parameters[moodleDbName]}' and table_name like '${tablePrefix}%'")
if [[ $tableCount -eq 0 ]]; then
    echo_feedback 'Moodle tables NOT found in database. Database must be setup as part of the install.'
    skipDatabaseOption=''
else
    echo_feedback 'Moodle tables found in database. Skipping database setup.'
    skipDatabaseOption='--skip-database'
fi

echo_action 'Running Moodle installation script...'
sudo -u ${apache2User} /usr/bin/php ${moodleDocumentRootDirPath}/admin/cli/install.php \
--non-interactive \
--lang=en \
--chmod=2777 \
--wwwroot=https://${parameters[moodleFqdn]}/ \
--dataroot=${moodleDataMountPointPath}/ \
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

echo_feedback "Done."

###############################################################################
echo_title "Update Moodle config for SSL Proxy and Local Cache directory."
###############################################################################
# No need to test for existing values since the file is always new.
echo_action "Adding SSL Proxy setting to ${moodleDocumentRootDirPath}/config.php file..."
sed -i '/^\$CFG->wwwroot.*/a \$CFG->sslproxy\t= true;' ${moodleDocumentRootDirPath}/config.php

echo_action "Adding Local Cache Directory setting to ${moodleDocumentRootDirPath}/config.php file..."
sed -i "/^\$CFG->dataroot.*/a \$CFG->localcachedir\t= '${moodleLocalCacheRootDirPath}';" ${moodleDocumentRootDirPath}/config.php

echo_action "Adding default timezone setting to ${moodleDocumentRootDirPath}/config.php file..."
sed -i "/^\$CFG->upgradekey.*/a date_default_timezone_set('America/Toronto');" ${moodleDocumentRootDirPath}/config.php

echo_feedback "Done."

###############################################################################
echo_title "Install plugins that have been recently added on the file system."
###############################################################################
sudo -u ${apache2User} /usr/bin/php ${moodleDocumentRootDirPath}/admin/cli/upgrade.php --non-interactive
echo_feedback "Done."

###############################################################################
echo_title "Uninstall plugings that have been recently removed from the file system."
###############################################################################
sudo -u ${apache2User} /usr/bin/php ${moodleDocumentRootDirPath}/admin/cli/uninstall_plugins.php --purge-missing --run
echo_feedback "Done."

###############################################################################
echo_title "Purge all Moodle Caches."
###############################################################################
sudo -u ${apache2User} /usr/bin/php ${moodleDocumentRootDirPath}/admin/cli/purge_caches.php
echo_feedback "Done."

###############################################################################
echo_title "Set Moodle Crontab."
###############################################################################
crontabEntry="* * * * * sudo -u ${apache2User} php ${moodleDocumentRootDirPath}/admin/cli/cron.php > /dev/null"
if [ -z "$(crontab -l | grep --fixed-strings "$crontabEntry")" ]; then
    crontab -l | { cat; echo "$crontabEntry"; } | crontab -
    echo "Done."
else
    echo "Skipped: crontab already set up."
fi

###############################################################################
echo_title "Finishing $0 on $(date)."
###############################################################################
trap - EXIT