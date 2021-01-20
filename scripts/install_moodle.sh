#!/bin/bash
# Install Moodle 3.10.1 and some plugins.
# This script must be run as root (ex.: sudo sh [script_name])
# Style Guide: https://google.github.io/styleguide/shellguide.html

# Constants
readonly APACHE2_DEFAULT_DOCUMENT_ROOT_DIR_PATH="/var/www/html"
readonly APACHE2_CONF_ENABLED_SECURITY_FILE_PATH="/etc/apache2/conf-enabled/security.conf"
readonly APACHE2_SITE_ENABLED_DEFAULT_FILE_PATH="/etc/apache2/sites-enabled/000-default.conf"
readonly APACHE2_USER="www-data"
readonly DATE_FORMAT='%Y-%m-%d %H:%M:%S (%Z)'
readonly HOSTS_FILE_PATH="/etc/hosts"
readonly MOODLE_DOCUMENT_ROOT_DIR_PATH="${APACHE2_DEFAULT_DOCUMENT_ROOT_DIR_PATH}/moodle"
readonly MOODLE_LOCAL_CACHE_DIR_PATH="${APACHE2_DEFAULT_DOCUMENT_ROOT_DIR_PATH}/moodlelocalcache"
readonly PHP_INI_FILE_PATH="/etc/php/7.2/apache2/php.ini"

# Helper functions
function echo_title {
  echo ""
  echo "###############################################################################"
  echo "$1"
  echo "###############################################################################"
}

function echo_action {
  echo ""
  echo "$(date +"$DATE_FORMAT") | ACTION - $1"
}

function echo_info {
  echo "$(date +"$DATE_FORMAT") | INFO   - $1"
}

function echo_error {
  echo "$(date +"$DATE_FORMAT") | ERROR  - $1" >&2
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

  echo_action "Checking downloaded file integrity..."
  echo "${plugin_md5_sum}  ${plugin_zip_file}" | md5sum --check
  if [[ $? != 0 ]]; then
    echo_error "Downloaded file corrupted. Aborting."
    exit 1;
  fi;
  echo_info "Done."

  echo_action "Extracting plugin files..."
  unzip -q ${plugin_zip_file} -d ${plugin_dir_path}
  echo_info "Done."
}

function main {
  # Exit when any command fails
  set -e
  # Keep track of the last executed command
  trap 'last_command=${current_command}; current_command=$BASH_COMMAND' DEBUG
  # Echo an error message before exiting
  trap 'echo "\"${last_command}\" command failed with exit code $?."' EXIT

  ###############################################################################
  echo_title "Start of $0"
  ###############################################################################

  ###############################################################################
  echo_title 'Process input parameters.'
  ###############################################################################
  echo_action 'Initializing expected parameters array...'
  declare -A parameters=( \
    [dataDiskSize]= \
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
  sorted_parameter_keys=$(echo ${!parameters[@]} | tr " " "\n" | sort | tr "\n" " ");
  echo_info "Done."

  echo_action "Mapping input parameter values and checking for unexpected parameters..."
  while [[ ${#@} -gt 0 ]];
  do
    key=$1
    value=$2

    # Test if the parameter key start with "-" and
    # if the parameter key (without the first dash) is in the expected parameter list.
    if [[ ${key} =~ ^-.*$ && ${parameters[${key:1}]+_} ]]; then
      parameters[${key:1}]="${value}"
    else
      echo_error "Unexpected parameter: ${key}"
      unexpected_parameter_flag=true
    fi

    # Move to the next key/value pair or up to the end of the parameter list.
    shift $(( 2 < ${#@} ? 2 : ${#@} ))
  done
  echo_info "Done."

  echo_action "Checking for missing parameters..."
  for parameter_key in ${sorted_parameter_keys}; do
    if [[ -z ${parameters[${parameter_key}]} ]]; then
      echo_error "Missing parameter: ${parameter_key}."
      missing_parameter_flag=true
    fi
  done
  echo_info "Done."

  # Abort if missing or extra parameters.
  if [[ ${unexpected_parameter_flag} == "true" || ${missing_parameter_flag} == "true" ]]; then
    echo_error "Execution aborted due to missing or extra parameters."
    usage="USAGE: $(basename $0)"
    for parameter_key in ${sorted_parameter_keys}; do
      usage="${usage} -${parameter_key} \$${parameter_key}"
    done
    echo_error "${usage}";
    exit 1;
  fi

  echo_action 'Printing input parameter values fro debugging purposes...'
  for parameter_key in ${sorted_parameter_keys}; do
    echo_info "$p = \"${parameters[${parameter_key}]}\""
  done
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
  apt-get install --yes --quiet \
    php-cli \
    postgresql-client-10 \
    unzip
  echo_info "Done."

  ###############################################################################
  echo_title "Install Moodle dependencies."
  ###############################################################################
  echo_action "Installing apache2 and redis packages..."
  apt-get install --yes --quiet \
    apache2 \
    libapache2-mod-php \
    redis
  echo_info "Done."

  echo_action "Installing php packages..."
  apt-get install --yes --quiet \
    aspell \
    clamav \
    ghostscript \
    graphviz \
    php7.2-curl \
    php7.2-gd \
    php7.2-intl \
    php7.2-ldap \
    php7.2-mbstring \
    php7.2-pgsql \
    php7.2-pspell \
    php7.2-redis \
    php7.2-soap \
    php7.2-xml \
    php7.2-xmlrpc \
    php7.2-zip
  echo_info "Done."

  ###############################################################################
  echo_title "Clean up server."
  ###############################################################################
  echo_action "Removing server packages that are no longer needed."
  apt autoremove -y
  echo_info "Done."

  ###############################################################################
  echo_title "Setup SMTP Server."
  ###############################################################################
  echo_action "Adding SMTP Server Private IP address in ${HOSTS_FILE_PATH}..."
  if ! grep -q "${parameters[smtpRelayFqdn]}" ${HOSTS_FILE_PATH}; then
    cat <<EOF >> ${HOSTS_FILE_PATH}
# Redirect SMTP Server FQDN to Private IP Address.
${parameters[smtpRelayPrivateIp]} ${parameters[smtpRelayFqdn]}
EOF
    echo_info "Done."
  else
    echo_info "Skipped: ${HOSTS_FILE_PATH} file already set up."
  fi

  ###############################################################################
  echo_title "Update PHP config."
  ###############################################################################
  echo_action "Updating upload_max_filesize and post_max_size settings in ${PHP_INI_FILE_PATH}..."
  sed -i "s/upload_max_filesize.*/upload_max_filesize = 2048M/" ${PHP_INI_FILE_PATH}
  sed -i "s/post_max_size.*/post_max_size = 2048M/" ${PHP_INI_FILE_PATH}
  echo_info "Done."

  ###############################################################################
  echo_title "Update Apache config."
  ###############################################################################
  echo_action "Updating Apache default site DocumentRoot property in ${APACHE2_SITE_ENABLED_DEFAULT_FILE_PATH}..."
  if ! grep -q "${MOODLE_DOCUMENT_ROOT_DIR_PATH}" ${APACHE2_SITE_ENABLED_DEFAULT_FILE_PATH}; then
    sed -i -E "s|DocumentRoot[[:space:]]*${APACHE2_DEFAULT_DOCUMENT_ROOT_DIR_PATH}|DocumentRoot ${MOODLE_DOCUMENT_ROOT_DIR_PATH}|g" ${APACHE2_SITE_ENABLED_DEFAULT_FILE_PATH}
    echo_info "Done."
  else
    echo_info "Skipped. DocumentRoot already properly set."
  fi

  echo_action "Updating Apache ServerSignature and ServerToken directives in ${APACHE2_CONF_ENABLED_SECURITY_FILE_PATH}..."
  sed -i "s/^ServerTokens[[:space:]]*\(Full\|OS\|Minimal\|Minor\|Major\|Prod\)$/ServerTokens Prod/" ${APACHE2_CONF_ENABLED_SECURITY_FILE_PATH}
  sed -i "s/^ServerSignature[[:space:]]*\(On\|Off\|EMail\)$/ServerSignature Off/" ${APACHE2_CONF_ENABLED_SECURITY_FILE_PATH}
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
  data_disk_block_path=/dev/$(lsblk --noheadings --output name,size | awk "{if (\$2 == \"${parameters[dataDiskSize]}\") print \$1}")
  echo_info "Data disk block path found: ${data_disk_block_path}"
  echo_info "Done."

  echo_action 'Creating a file system in the data disk block if none exists...'
  data_disk_file_system_type=$(lsblk --noheadings --output fstype ${data_disk_block_path})
  if [ -z $data_disk_file_system_type ]; then
    echo_info "No file system detected on ${data_disk_block_path}."
    data_disk_file_system_type=ext4
    echo_action "Creating file system of type ${data_disk_file_system_type} on ${data_disk_block_path}..."
    mkfs.$data_disk_file_system_type ${data_disk_block_path}
    echo_info "Done."
  else
    echo_info "Skipped: File system ${data_disk_file_system_type} already exist on ${data_disk_block_path}."
  fi

  echo_action 'Retrieving data disk file System UUID...'
  # Bug Fix:  Experience demonstrated that the UUID of the new file system is not immediately
  #           available through lsblk, thus we wait and loop for up to 60 seconds to get it.
  elapsed_time=0
  data_disk_file_system_uuid=""
  while [[ -z "${data_disk_file_system_uuid}" && "${elapsed_time}" -lt "60" ]]; do
    echo_info "Waiting for 1 second..."
    sleep 1
    data_disk_file_system_uuid=$(lsblk --noheadings --output UUID ${data_disk_block_path})
    ((elapsed_time+=1))
  done
  echo_info "Data disk file system UUID: ${data_disk_file_system_uuid}"
  echo_info "Done."

  echo_action "Creating Moodle Data mount point..."
  mkdir -p ${parameters[moodleDataMountPointPath]}
  echo_info "${parameters[moodleDataMountPointPath]} directory created."
  echo_info "Done."

  fstab_file_path=/etc/fstab
  echo_action "Updating $fstab_file_path file to automount the data disk using its UUID..."
  if ! grep -q "${data_disk_file_system_uuid}" ${fstab_file_path}; then
    printf "UUID=${data_disk_file_system_uuid}\t${parameters[moodleDataMountPointPath]}\t${data_disk_file_system_type}\tdefaults,nofail\t0\t2\n" >> ${fstab_file_path}
    echo_info "Done."
  else
    echo_info "Skipped: already set up."
  fi

  echo_action 'Mounting all drives...'
  mount -a
  echo_info "Done."

  echo_action 'Setting permissions ...'
  chown -R ${APACHE2_USER}:root ${parameters[moodleDataMountPointPath]}
  chmod -R 775 ${parameters[moodleDataMountPointPath]}
  echo_info "Done."

  ###############################################################################
  echo_title "Create Moodle Local Cache directory."
  ###############################################################################
  if [ -d ${MOODLE_LOCAL_CACHE_DIR_PATH} ]; then
    echo_action "Deleting old ${MOODLE_LOCAL_CACHE_DIR_PATH} folder..."
    rm -rf ${MOODLE_LOCAL_CACHE_DIR_PATH}
    echo_info "Done."
  fi

  echo_action "Creating new ${MOODLE_LOCAL_CACHE_DIR_PATH} folder with proper ownership..."
  install -o ${APACHE2_USER} -d ${MOODLE_LOCAL_CACHE_DIR_PATH}
  echo_info "Done."

  ###############################################################################
  echo_title "Download and extract Moodle files."
  ###############################################################################
  # Ref.: https://download.moodle.org/releases/supported/
  echo_action "Downloading Moodle 3.10.1 tar file..."
  moodle_tgz_file_url=https://download.moodle.org/download.php/direct/stable310/moodle-3.10.1.tgz
  moodle_tgz_file=$(basename ${moodle_tgz_file_url})
  wget ${moodle_tgz_file_url} -O ${moodle_tgz_file}
  echo_info "Done."

  echo_action "Verifying downloaded file integrity..."
  echo "SHA256(${moodle_tgz_file})= 547973f2dc2ca7b992c193dab4991c88768338fd2bd04b9d786e62de08cf513f" | sha256sum --check
  if [[ $? != 0 ]]; then
    exit 1
  fi
  echo_info "Done."

  if [ -d ${MOODLE_DOCUMENT_ROOT_DIR_PATH} ]; then
    echo_action "Deleting old ${MOODLE_DOCUMENT_ROOT_DIR_PATH} folder..."
    rm -rf ${MOODLE_DOCUMENT_ROOT_DIR_PATH}
    echo_info "Done."
  fi

  echo_action "Extracting moodle tgz file..."
  tar zxf ${moodle_tgz_file} -C ${APACHE2_DEFAULT_DOCUMENT_ROOT_DIR_PATH}
  echo_info "Done."

  # Ref.: https://moodle.org/plugins/availability_coursecompleted
  get_moodle_plugin \
    "Availability conditions: Restriction by course completion" \
    "https://moodle.org/plugins/download.php/22755/availability_coursecompleted_moodle310_2020110200.zip" \
    "30ae974217c013b6fc2ea561428c4fce" \
    "${MOODLE_DOCUMENT_ROOT_DIR_PATH}/availability/condition"

  # Ref.: https://moodle.org/plugins/block_completion_progress
  get_moodle_plugin \
    "Blocks: Completion Progress" \
    "https://moodle.org/plugins/download.php/22199/block_completion_progress_moodle310_2020081000.zip" \
    "c4c7047dcce96761bb2ccbab118008c5" \
    "${MOODLE_DOCUMENT_ROOT_DIR_PATH}/blocks"

  # Ref.: https://moodle.org/plugins/block_configurable_reports
  get_moodle_plugin \
    "Blocks: Configurable Reports" \
    "https://moodle.org/plugins/download.php/22758/block_configurable_reports_moodle310_2020110300.zip" \
    "e693f9f78b7fc486f70c9d1dbc578ba0" \
    "${MOODLE_DOCUMENT_ROOT_DIR_PATH}/blocks"

  # Ref.: https://moodle.org/plugins/block_qrcode
  get_moodle_plugin \
    "Blocks: QR code" \
    "https://moodle.org/plugins/download.php/22878/block_qrcode_moodle310_2020111700.zip" \
    "1d6b72e2ae6f2325f9faaf3938a97e8b" \
    "${MOODLE_DOCUMENT_ROOT_DIR_PATH}/blocks"

  # Ref.: https://moodle.org/plugins/filter_multilang2
  get_moodle_plugin \
    "Filters: Multi-Language Content (v2)" \
    "https://moodle.org/plugins/download.php/22662/filter_multilang2_moodle310_2020101300.zip" \
    "9c4c72c2ef9a00f97889a81cc62da715" \
    "${MOODLE_DOCUMENT_ROOT_DIR_PATH}/filter"

  # Ref.: https://moodle.org/plugins/local_mailtest
  get_moodle_plugin \
    "General plugins (Local): Moodle eMail Test" \
    "https://moodle.org/plugins/download.php/22516/local_mailtest_moodle310_2020092000.zip" \
    "a71b20c5a5d805577c1521a63d54a06f" \
    "${MOODLE_DOCUMENT_ROOT_DIR_PATH}/local"

  # Ref.: https://moodle.org/plugins/mod_attendance
  get_moodle_plugin \
    "Activities: Attendance" \
    "https://moodle.org/plugins/download.php/23075/mod_attendance_moodle310_2020120300.zip" \
    "71074c78a4bf2aa932fac9531c531a6b" \
    "${MOODLE_DOCUMENT_ROOT_DIR_PATH}/mod"

  # Ref.: https://moodle.org/plugins/mod_customcert
  get_moodle_plugin \
    "Activities: Custom certificate" \
    "https://moodle.org/plugins/download.php/22980/mod_customcert_moodle310_2020110900.zip" \
    "e1fc30a97ea4b1f39f18302cd3711b08" \
    "${MOODLE_DOCUMENT_ROOT_DIR_PATH}/mod"

  # Ref.: https://moodle.org/plugins/mod_hvp
  get_moodle_plugin \
    "Activities: Interactive Content – H5P" \
    "https://moodle.org/plugins/download.php/22165/mod_hvp_moodle39_2020080400.zip" \
    "025be22e2c2d7a79f0d15f725fd9c577" \
    "${MOODLE_DOCUMENT_ROOT_DIR_PATH}/mod"

  # Ref.: https://moodle.org/plugins/mod_questionnaire
  get_moodle_plugin \
    "Activities: Questionnaire" \
    "https://moodle.org/plugins/download.php/22949/mod_questionnaire_moodle310_2020062302.zip" \
    "333f1a31d9d313c914d661b40a8c5dd8" \
    "${MOODLE_DOCUMENT_ROOT_DIR_PATH}/mod"

  # Ref.: https://moodle.org/plugins/theme_boost_campus
  get_moodle_plugin \
    "Themes: Boost Campus" \
    "https://moodle.org/plugins/download.php/23226/theme_boost_campus_moodle310_2020112801.zip" \
    "e9dd4a1338ca2ea8002d3e7ad5185bcf" \
    "${MOODLE_DOCUMENT_ROOT_DIR_PATH}/theme"

  # Ref.: https://moodle.org/plugins/tool_coursedates
  get_moodle_plugin \
    "Admin tools: Set course dates" \
    "https://moodle.org/plugins/download.php/22237/tool_coursedates_moodle310_2020081400.zip" \
    "1deb78e3608ab027f88e3e7063586f05" \
    "${MOODLE_DOCUMENT_ROOT_DIR_PATH}/admin/tool"

  echo_action "Updating file ownership on ${MOODLE_DOCUMENT_ROOT_DIR_PATH}..."
  chown -R ${APACHE2_USER}:root ${MOODLE_DOCUMENT_ROOT_DIR_PATH}
  echo_info "Done."

  ###############################################################################
  echo_title "Run Moodle Installer."
  ###############################################################################
  echo_action 'Assessing whether Moodle installer should skip database setup...'
  # If moodle database tables already exist then
  # add the "--skip-database" option to the install script.
  export PGPASSWORD="${parameters[dbServerAdminPassword]}"
  table_prefix='mdl_'
  table_count=$(
    psql \
      "host=${parameters[dbServerFqdn]} port=5432 user=${parameters[dbServerAdminUsername]}@${parameters[dbServerName]} dbname=${parameters[moodleDbName]} sslmode=require" \
      --tuples-only \
      --command="select count(*) from information_schema.tables where table_catalog='${parameters[moodleDbName]}' and table_name like '${table_prefix}%'" \
    )
  if (( ${table_count} == 0 )); then # Use arithmetic expansion operator ((...)) to convert string into integer.
    echo_info 'Moodle tables NOT found in database. Database must be setup as part of the install.'
    skip_database_option=''
  else
    echo_info 'Moodle tables found in database. Skipping database setup.'
    skip_database_option='--skip-database'
  fi
  echo_info "Done."

  echo_action 'Running Moodle installation script...'
  sudo -u ${APACHE2_USER} /usr/bin/php ${MOODLE_DOCUMENT_ROOT_DIR_PATH}/admin/cli/install.php \
    --non-interactive \
    --lang=en \
    --chmod=2777 \
    --wwwroot=https://${parameters[moodleFqdn]}/ \
    --dataroot=${parameters[moodleDataMountPointPath]}/ \
    --dbtype=pgsql \
    --dbhost=${parameters[dbServerFqdn]} \
    --dbname=${parameters[moodleDbName]} \
    --prefix=$table_prefix \
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
    ${skip_database_option} \
    --agree-license
  echo_info "Done."

  ###############################################################################
  echo_title "Moodle Post installation process."
  ###############################################################################
  # No need to test for existing values since the file is always new.
  echo_action "Adding SSL Proxy setting to ${MOODLE_DOCUMENT_ROOT_DIR_PATH}/config.php file..."
  sed -i '/^\$CFG->wwwroot.*/a \$CFG->sslproxy\t= true;' ${MOODLE_DOCUMENT_ROOT_DIR_PATH}/config.php
  echo_info "Done."

  echo_action "Adding Local Cache Directory setting to ${MOODLE_DOCUMENT_ROOT_DIR_PATH}/config.php file..."
  sed -i "/^\$CFG->dataroot.*/a \$CFG->localcachedir\t= '${MOODLE_LOCAL_CACHE_DIR_PATH}';" ${MOODLE_DOCUMENT_ROOT_DIR_PATH}/config.php
  echo_info "Done."

  echo_action "Adding default timezone setting to ${MOODLE_DOCUMENT_ROOT_DIR_PATH}/config.php file..."
  sed -i "/^\$CFG->upgradekey.*/a date_default_timezone_set('America/Toronto');" ${MOODLE_DOCUMENT_ROOT_DIR_PATH}/config.php
  echo_info "Done."

  echo_action "Installing plugins that have been recently added on the file system..."
  sudo -u ${APACHE2_USER} /usr/bin/php ${MOODLE_DOCUMENT_ROOT_DIR_PATH}/admin/cli/upgrade.php --non-interactive
  echo_info "Done."

  echo_action "Uninstalling plugings that have been recently removed from the file system..."
  sudo -u ${APACHE2_USER} /usr/bin/php ${MOODLE_DOCUMENT_ROOT_DIR_PATH}/admin/cli/uninstall_plugins.php --purge-missing --run
  echo_info "Done."

  echo_action "Purging all Moodle Caches..."
  sudo -u ${APACHE2_USER} /usr/bin/php ${MOODLE_DOCUMENT_ROOT_DIR_PATH}/admin/cli/purge_caches.php
  echo_info "Done."

  echo_action "Setting up Moodle Crontab..."
  crontab_entry="* * * * * sudo -u ${APACHE2_USER} php ${MOODLE_DOCUMENT_ROOT_DIR_PATH}/admin/cli/cron.php > /dev/null"
  if [ -z "$(crontab -l | grep --fixed-strings "${crontab_entry}")" ]; then
    crontab -l | { cat; echo "${crontab_entry}"; } | crontab -
    echo_info "Done."
  else
    echo_info "Skipped: crontab already set up."
  fi

  ###############################################################################
  echo_title "End of $0"
  ###############################################################################

  # Remove all trap
  trap - EXIT
}

main "$@"
