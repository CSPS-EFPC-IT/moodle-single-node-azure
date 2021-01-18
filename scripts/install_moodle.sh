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
    echo "ACTION - $1 "
}

function echo_info {
    echo "INFO   - $1"
}

function echo_error {
    echo "ERROR  - $1"
}

function get_moodle_plugin {
    local plugin_title=$1
    local plugin_zip_file_url=$2
    local plugin_md5_sum=$3
    local plugin_dir_path=$4
    local plugin_zip_file=$(basename ${plugin_zip_file_url})

    echo_title "Get Moodle \"${plugin_title}\" plugin..."

    echo_action "Downloading plugin zip file..."
    wget ${plugin_zip_file_url} -O ${plugin_zip_file}
    echo_info "Done."

    echo_action "Checking plugin MD5 Sum..."
    echo "${plugin_md5_sum}  ${plugin_zip_file}" | md5sum --check
    if [[ $? -ne 0 ]]; then
        -- Abort if MD5 Sum is wrong
        exit 1;
    fi;
    echo_info "Done."

    echo_action "Extracting plugin files..."
    unzip -q ${plugin_zip_file} -d ${plugin_dir_path}
    echo_info "Done."
}

###############################################################################
echo_title "Starting $0 on $(date)."
###############################################################################

###############################################################################
echo_title 'Process input parameters.'
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
                            [moodleDataMountPointPath]= \
                            [moodleDbName]= \
                            [moodleDbPassword]= \
                            [moodleDbUsername]= \
                            [moodleFqdn]= \
                            [moodleUpgradeKey]= \
                            [smtpRelayFqdn]= \
                            [smtpRelayPrivateIp]=)
sortedParameterList=$(echo ${!parameters[@]} | tr " " "\n" | sort | tr "\n" " ");
echo_info "Done."

echo_action "Mapping input parameter values and checking for extra parameters..."
while [[ ${#@} -gt 0 ]];
do
    key=$1
    value=$2

    ## Test if the parameter key start with "-" and if the parameter key (without the first dash) is in the expected parameter list.
    if [[ ${key} =~ ^-.*$ && ${parameters[${key:1}]+_} ]]; then
        parameters[${key:1}]="$value"
    else
        echo_error "Unexpected parameter: $key"
        extraParameterFlag=true;
    fi

    # Move to the next key/value pair or up to the end of the parameter list.
    shift $(( 2 < ${#@} ? 2 : ${#@} ))
done
echo_info "Done."

echo_action "Checking for missing parameters..."
for p in $sortedParameterList; do
    if [[ -z ${parameters[$p]} ]]; then
        echo_error "Missing parameter: $p."
        missingParameterFlag=true;
    fi
done
echo_info "Done."

# Abort if missing or extra parameters.
if [[ $extraParameterFlag == "true" || $missingParameterFlag == "true" ]]; then
    echo_error "Execution aborted due to missing or extra parameters."
    usage="USAGE: $(basename $0)"
    for p in $sortedParameterList; do
        usage="${usage} -${p} \$${p}"
    done
    echo_error "${usage}";
    exit 1;
fi

echo_action 'Printing input parameter values fro debugging purposes...'
for p in $sortedParameterList; do
    echo_info "$p = \"${parameters[$p]}\""
done
echo_info "Done."

###############################################################################
echo_title "Set internal parameters."
###############################################################################
echo_action "Setting useful variables..."
apache2DefaultDocumentRootDirPath="/var/www/html"
apache2ConfEnabledSecurityFilePath="/etc/apache2/conf-enabled/security.conf"
apache2SitesEnabledDefaultFilePath="/etc/apache2/sites-enabled/000-default.conf"
apache2User="www-data"
hostsFilePath="/etc/hosts"
installDirPath="$(pwd)"
moodleDocumentRootDirPath="${apache2DefaultDocumentRootDirPath}/moodle"
moodleLocalCacheRootDirPath="${apache2DefaultDocumentRootDirPath}/moodlelocalcache"
phpIniFilePath="/etc/php/7.2/apache2/php.ini"
echo_info "Done."

###############################################################################
echo_title "Upgrade server."
###############################################################################
echo_action "Updating server package index files before the upgrade..."
apt update
echo_info "Done."

echo_action "Upgrading all installed server packages to their latest version and apply available security patches..."
apt upgrade -y
echo_info "Done."

###############################################################################
echo_title "Install tools."
###############################################################################
echo_action "Installing postgres client, php client and unzip packages..."
apt-get install --yes --quiet postgresql-client-10 php-cli unzip
echo_info "Done."

###############################################################################
echo_title "Install Moodle dependencies."
###############################################################################
echo_action "Installing apache2 and redis packages..."
apt-get install --yes --quiet apache2 libapache2-mod-php redis
echo_info "Done."

echo_action "Installing php packages..."
apt-get install --yes --quiet graphviz aspell ghostscript clamav php7.2-pspell php7.2-curl php7.2-gd php7.2-intl php7.2-pgsql php7.2-xml php7.2-xmlrpc php7.2-ldap php7.2-zip php7.2-soap php7.2-mbstring php7.2-redis
echo_info "Done."

###############################################################################
echo_title "Clean up server."
###############################################################################
echo_action "Removing server packages that are no longer needed."
apt-get autoremove -y
echo_info "Done."

###############################################################################
echo_title "Setup SMTP Relay."
###############################################################################
echo_action "Adding SMTP Relay Private IP address in ${hostsFilePath}..."
if ! grep -q "${parameters[smtpRelayFqdn]}" $hostsFilePath; then
    echo -e "\n# Redirect SMTP Relay FQDN to Private IP Address.\n${parameters[smtpRelayPrivateIp]}\t${parameters[smtpRelayFqdn]}" >> $hostsFilePath
    echo_info "Done."
else
    echo_info "Skipped: ${hostsFilePath} file already set up."
fi

###############################################################################
echo_title "Update PHP config."
###############################################################################
echo_action "Updating upload_max_filesize and post_max_size settings in ${phpIniFilePath}..."
sed -i "s/upload_max_filesize.*/upload_max_filesize = 2048M/" $phpIniFilePath
sed -i "s/post_max_size.*/post_max_size = 2048M/" $phpIniFilePath
echo_info "Done."

###############################################################################
echo_title "Update Apache config."
###############################################################################
echo_action "Updating Apache default site DocumentRoot property in ${apache2SitesEnabledDefaultFilePath}..."
if ! grep -q "${moodleDocumentRootDirPath}" $apache2SitesEnabledDefaultFilePath; then
    escapedApache2DefaultDocumentRootDirPath=$(sed -E 's/(\/)/\\\1/g' <<< ${apache2DefaultDocumentRootDirPath})
    escapedMoodleDocumentRootDirPath=$(sed -E 's/(\/)/\\\1/g' <<< ${moodleDocumentRootDirPath})
    sed -i -E "s/DocumentRoot[[:space:]]*${escapedApache2DefaultDocumentRootDirPath}/DocumentRoot ${escapedMoodleDocumentRootDirPath}/g" $apache2SitesEnabledDefaultFilePath
    echo_info "Done."
else
    echo_info "Skipped. DocumentRoot already properly set."
fi

echo_action "Updating Apache ServerSignature and ServerToken directives in ${apache2ConfEnabledSecurityFilePath}..."
sed -i "s/^ServerTokens[[:space:]]*\(Full\|OS\|Minimal\|Minor\|Major\|Prod\)$/ServerTokens Prod/" $apache2ConfEnabledSecurityFilePath
sed -i "s/^ServerSignature[[:space:]]*\(On\|Off\|EMail\)$/ServerSignature Off/" $apache2ConfEnabledSecurityFilePath
echo_info "Done."

echo_action "Restarting Apache2..."
service apache2 restart
echo_info "Done."

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
echo_info "Done."

###############################################################################
echo_title "Mount Moodle Data Disk."
###############################################################################
echo_action 'Retrieving the data disk block path using the data disk size as index...'
dataDiskBlockPath=/dev/$(lsblk --noheadings --output name,size | awk "{if (\$2 == \"${parameters[dataDiskSize]}\") print \$1}")
echo_info "Data disk block path found: $dataDiskBlockPath"
echo_info "Done."

echo_action 'Creating a file system in the data disk block if none exists...'
dataDiskFileSystemType=$(lsblk --noheadings --output fstype $dataDiskBlockPath)
if [ -z $dataDiskFileSystemType ]; then
    echo_info "No file system detected on $dataDiskBlockPath."
    dataDiskFileSystemType=ext4
    echo_action "Creating file system of type $dataDiskFileSystemType on $dataDiskBlockPath..."
    mkfs.$dataDiskFileSystemType $dataDiskBlockPath
    echo_info "Done."
else
    echo_info "Skipped: File system $dataDiskFileSystemType already exist on $dataDiskBlockPath."
fi

echo_action 'Retrieving data disk file System UUID...'
# Bug Fix:  Experience demonstrated that the UUID of the new file system is not immediately 
#           available through lsblk, thus we wait and loop for up to 60 seconds to get it.
elapsedTime=0
dataDiskFileSystemUuid=""
while [ -z "$dataDiskFileSystemUuid" -a "$elapsedTime" -lt "60" ]; do
    echo_info "Waiting for 1 second..."
    sleep 1
    dataDiskFileSystemUuid=$(lsblk --noheadings --output UUID ${dataDiskBlockPath})
    ((elapsedTime+=1))
done
echo_info "Data disk file system UUID: $dataDiskFileSystemUuid"
echo_info "Done."

echo_action "Creating Moodle Data mount point..."
mkdir -p ${parameters[moodleDataMountPointPath]}
echo_info "${parameters[moodleDataMountPointPath]} directory created."
echo_info "Done."

fstabFilePath=/etc/fstab
echo_action "Updating $fstabFilePath file to automount the data disk using its UUID..."
if ! grep -q "$dataDiskFileSystemUuid" $fstabFilePath; then
    printf "UUID=${dataDiskFileSystemUuid}\t${parameters[moodleDataMountPointPath]}\t${dataDiskFileSystemType}\tdefaults,nofail\t0\t2\n" >> $fstabFilePath
    echo_info "Done."
else
    echo_info "Skipped: already set up."
fi

echo_action 'Mounting all drives...'
mount -a
echo_info "Done."

echo_action 'Setting permissions ...'
chown -R ${apache2User}:root ${parameters[moodleDataMountPointPath]}
chmod -R 775 ${parameters[moodleDataMountPointPath]}
echo_info "Done."

###############################################################################
echo_title "Create Moodle Local Cache directory."
###############################################################################
if [ -d ${moodleLocalCacheRootDirPath} ]; then
    echo_action "Deleting old ${moodleLocalCacheRootDirPath} folder..."
    rm -rf ${moodleLocalCacheRootDirPath}
    echo_info "Done."
fi

echo_action "Creating new ${moodleLocalCacheRootDirPath} folder..."
mkdir ${moodleLocalCacheRootDirPath}
echo_info "Done."

echo_action "Updating file permission on ${moodleLocalCacheRootDirPath}..."
chown -R ${apache2User} ${moodleLocalCacheRootDirPath}
echo_info "Done."

###############################################################################
echo_title "Download and extract Moodle files."
###############################################################################
# Ref.: https://download.moodle.org/releases/supported/
echo_action "Downloading Moodle 3.10.1 tar file..."
moodle_zip_file_url=https://download.moodle.org/download.php/direct/stable310/moodle-3.10.1.tgz
moodle_zip_file=$(basename ${moodle_zip_file_url})
wget ${moodle_zip_file_url} -O ${moodle_zip_file}
echo_info "Done."

echo_action "Verifying downloaded file integrity..."
echo "SHA256(${moodle_zip_file})= 547973f2dc2ca7b992c193dab4991c88768338fd2bd04b9d786e62de08cf513f" | sha256sum --check
if [[ $? -ne 0 ]]; then
    exit 1
fi
echo_info "Done."

if [ -d ${moodleDocumentRootDirPath} ]; then
    echo_action "Deleting old ${moodleDocumentRootDirPath} folder..."
    rm -rf ${moodleDocumentRootDirPath}
    echo_info "Done."
fi

echo_action "Extracting moodle tar file..."
tar zxf ${moodle_zip_file} -C ${apache2DefaultDocumentRootDirPath}
echo_info "Done."

# Ref.: https://moodle.org/plugins/availability_coursecompleted
get_moodle_plugin   "Availability conditions: Restriction by course completion" \
                    "https://moodle.org/plugins/download.php/22755/availability_coursecompleted_moodle310_2020110200.zip" \
                    "30ae974217c013b6fc2ea561428c4fce" \
                    "${moodleDocumentRootDirPath}/availability/condition"

# Ref.: https://moodle.org/plugins/block_completion_progress
get_moodle_plugin   "Blocks: Completion Progress" \
                    "https://moodle.org/plugins/download.php/22199/block_completion_progress_moodle310_2020081000.zip" \
                    "c4c7047dcce96761bb2ccbab118008c5" \
                    "${moodleDocumentRootDirPath}/blocks"

# Ref.: https://moodle.org/plugins/block_configurable_reports
get_moodle_plugin   "Blocks: Configurable Reports" \
                    "https://moodle.org/plugins/download.php/22758/block_configurable_reports_moodle310_2020110300.zip" \
                    "e693f9f78b7fc486f70c9d1dbc578ba0" \
                    "${moodleDocumentRootDirPath}/blocks"

# Ref.: https://moodle.org/plugins/block_qrcode
get_moodle_plugin   "Blocks: QR code" \
                    "https://moodle.org/plugins/download.php/22878/block_qrcode_moodle310_2020111700.zip" \
                    "1d6b72e2ae6f2325f9faaf3938a97e8b" \
                    "${moodleDocumentRootDirPath}/blocks"

# Ref.: https://moodle.org/plugins/filter_multilang2
get_moodle_plugin   "Filters: Multi-Language Content (v2)" \
                    "https://moodle.org/plugins/download.php/22662/filter_multilang2_moodle310_2020101300.zip" \
                    "9c4c72c2ef9a00f97889a81cc62da715" \
                    "${moodleDocumentRootDirPath}/filter"

# Ref.: https://moodle.org/plugins/local_mailtest
get_moodle_plugin   "General plugins (Local): Moodle eMail Test" \
                    "https://moodle.org/plugins/download.php/22516/local_mailtest_moodle310_2020092000.zip" \
                    "a71b20c5a5d805577c1521a63d54a06f" \
                    "${moodleDocumentRootDirPath}/local"

# Ref.: https://moodle.org/plugins/mod_attendance
get_moodle_plugin   "Activities: Attendance" \
                    "https://moodle.org/plugins/download.php/23075/mod_attendance_moodle310_2020120300.zip" \
                    "71074c78a4bf2aa932fac9531c531a6b" \
                    "${moodleDocumentRootDirPath}/mod"

# Ref.: https://moodle.org/plugins/mod_customcert
get_moodle_plugin   "Activities: Custom certificate" \
                    "https://moodle.org/plugins/download.php/22980/mod_customcert_moodle310_2020110900.zip" \
                    "e1fc30a97ea4b1f39f18302cd3711b08" \
                    "${moodleDocumentRootDirPath}/mod"

# Ref.: https://moodle.org/plugins/mod_hvp
get_moodle_plugin   "Activities: Interactive Content – H5P" \
                    "https://moodle.org/plugins/download.php/22165/mod_hvp_moodle39_2020080400.zip" \
                    "025be22e2c2d7a79f0d15f725fd9c577" \
                    "${moodleDocumentRootDirPath}/mod"

# Ref.: https://moodle.org/plugins/mod_questionnaire
get_moodle_plugin   "Activities: Questionnaire" \
                    "https://moodle.org/plugins/download.php/22949/mod_questionnaire_moodle310_2020062302.zip" \
                    "333f1a31d9d313c914d661b40a8c5dd8" \
                    "${moodleDocumentRootDirPath}/mod"

# Ref.: https://moodle.org/plugins/theme_boost_campus
get_moodle_plugin   "Themes: Boost Campus" \
                    "https://moodle.org/plugins/download.php/23226/theme_boost_campus_moodle310_2020112801.zip" \
                    "e9dd4a1338ca2ea8002d3e7ad5185bcf" \
                    "${moodleDocumentRootDirPath}/theme"

# Ref.: https://moodle.org/plugins/tool_coursedates
get_moodle_plugin   "Admin tools: Set course dates" \
                    "https://moodle.org/plugins/download.php/22237/tool_coursedates_moodle310_2020081400.zip" \
                    "1deb78e3608ab027f88e3e7063586f05" \
                    "${moodleDocumentRootDirPath}/admin/tool"

echo_action "Updating file ownership on ${moodleDocumentRootDirPath}..."
chown -R ${apache2User}:root ${moodleDocumentRootDirPath}
echo_info "Done."

###############################################################################
echo_title "Run Moodle Installer."
###############################################################################
echo_action 'Assessing whether the moodle tables already exist...'
# If yes then add the "--skip-database" option to the install script.
export PGPASSWORD="${parameters[dbServerAdminPassword]}"
tablePrefix='mdl_'
tableCount=$(psql "host=${parameters[dbServerFqdn]} port=5432 user=${parameters[dbServerAdminUsername]}@${parameters[dbServerName]} dbname=${parameters[moodleDbName]} sslmode=require" --tuples-only --command="select count(*) from information_schema.tables where table_catalog='${parameters[moodleDbName]}' and table_name like '${tablePrefix}%'")
if [[ $tableCount -eq 0 ]]; then
    echo_info 'Moodle tables NOT found in database. Database must be setup as part of the install.'
    skipDatabaseOption=''
else
    echo_info 'Moodle tables found in database. Skipping database setup.'
    skipDatabaseOption='--skip-database'
fi
echo_info "Done."

echo_action 'Running Moodle installation script...'
sudo -u ${apache2User} /usr/bin/php ${moodleDocumentRootDirPath}/admin/cli/install.php \
    --non-interactive \
    --lang=en \
    --chmod=2777 \
    --wwwroot=https://${parameters[moodleFqdn]}/ \
    --dataroot=${parameters[moodleDataMountPointPath]}/ \
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
echo_info "Done."

###############################################################################
echo_title "Moodle Post installation process."
###############################################################################
# No need to test for existing values since the file is always new.
echo_action "Adding SSL Proxy setting to ${moodleDocumentRootDirPath}/config.php file..."
sed -i '/^\$CFG->wwwroot.*/a \$CFG->sslproxy\t= true;' ${moodleDocumentRootDirPath}/config.php
echo_info "Done."

echo_action "Adding Local Cache Directory setting to ${moodleDocumentRootDirPath}/config.php file..."
sed -i "/^\$CFG->dataroot.*/a \$CFG->localcachedir\t= '${moodleLocalCacheRootDirPath}';" ${moodleDocumentRootDirPath}/config.php
echo_info "Done."

echo_action "Adding default timezone setting to ${moodleDocumentRootDirPath}/config.php file..."
sed -i "/^\$CFG->upgradekey.*/a date_default_timezone_set('America/Toronto');" ${moodleDocumentRootDirPath}/config.php
echo_info "Done."

echo_action "Installing plugins that have been recently added on the file system..."
sudo -u ${apache2User} /usr/bin/php ${moodleDocumentRootDirPath}/admin/cli/upgrade.php --non-interactive
echo_info "Done."

echo_action "Uninstalling plugings that have been recently removed from the file system..."
sudo -u ${apache2User} /usr/bin/php ${moodleDocumentRootDirPath}/admin/cli/uninstall_plugins.php --purge-missing --run
echo_info "Done."

echo_action "Purging all Moodle Caches..."
sudo -u ${apache2User} /usr/bin/php ${moodleDocumentRootDirPath}/admin/cli/purge_caches.php
echo_info "Done."

echo_action "Setting up Moodle Crontab..."
crontabEntry="* * * * * sudo -u ${apache2User} php ${moodleDocumentRootDirPath}/admin/cli/cron.php > /dev/null"
if [ -z "$(crontab -l | grep --fixed-strings "$crontabEntry")" ]; then
    crontab -l | { cat; echo "$crontabEntry"; } | crontab -
    echo_info "Done."
else
    echo_info "Skipped: crontab already set up."
fi

###############################################################################
echo_title "Finishing $0 on $(date)."
###############################################################################
trap - EXIT