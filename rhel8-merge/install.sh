#!/bin/bash
#
# Aveksa Install Script
#

LOG=/tmp/aveksa-install.log
export INSTALL_FILE=Y
QUIET=N
OPT_CREATESCHEMA=N
OPT_MIGRATE=N
OPT_NOCREATEMIGRATE=N
OPT_ASMPART=
OPT_STAGING=
OPT_PACKAGES=
OPT_NOSTART=N
OPT_AFX=N
OPT_TESTS=N
OPT_UIMAP=N
OPT_FORCEFRESHORACLE=N
OPT_SECURE_COOKIES=Y
# Do not run any shifts on OPT_STRING_TO_LOG
OPT_STRING_TO_LOG=$@
while [ $1 ]; do
	case $1 in
	-h)
		cat <<EOF

$0 [options...]

-h                  show help and exit
-q                  do not ask any questions
-createschema       force createSchema
-migrate            force migration
-nocreatemigrate    prevent createSchema or migrate
-asmpart {part}     set the ASM partition
-staging {dir}      set the staging directory
-packages {dir}     set the packages directory
-nostart            do not start the server at end of installation
-tests              add tests
-uimap              add uimap
-forcefreshoracle   force removal of 11G and 0lder version of Oracle
                    includes removal of database without backup verification
-afx                add connector packages

EOF
		exit 0
		;;
	-q)
		QUIET=Y
		shift
		;;
	-createschema)
		OPT_CREATESCHEMA=Y
		CREATE_DATABASE=Y
		MIGRATE_DATABASE=N
		shift
		;;
	-migrate)
		OPT_MIGRATE=Y
		CREATE_DATABASE=N
		MIGRATE_DATABASE=Y
		shift
		;;
	-nocreatemigrate)
		OPT_NOCREATEMIGRATE=Y
		shift
		;;
	-asmpart)
		shift
		if [ -z "$1" ]; then echo ASM partition not specified; exit 1; fi
		OPT_ASMPART=$1
		shift
		;;
	-staging)
		shift
		if [ -z "$1" ]; then echo staging directory not specified; exit 1; fi
		OPT_STAGING=$1
		shift
		;;
	-packages)
		shift
		if [ -z "$1" ]; then echo packages directory not specified; exit 1; fi
		OPT_PACKAGES=$1
		shift
		;;
	-nostart)
		OPT_NOSTART=Y
		shift
		;;
	-afx)
		OPT_AFX=Y
		shift
		;;
	-tests)
		OPT_TESTS=Y
		shift
		;;
	-uimap)
		OPT_UIMAP=Y
		shift
		;;
	-forcefreshoracle)
		OPT_FORCEFRESHORACLE=Y
		OPT_CREATESCHEMA=Y
		shift
		;;
	-disablesecurecookies)
		OPT_SECURE_COOKIES=N
		shift
		;;
	*)
		echo Unknown option $1
		exit 1
		;;
	esac
done

# Export these options for other scripts to use
export OPT_AFX
export OPT_TESTS
export OPT_UIMAP
export OPT_FORCEFRESHORACLE
export OPT_SECURE_COOKIES

. ./common.sh

# Make sure AVEKSA_HOME is set
test -z "$AVEKSA_HOME" && export AVEKSA_HOME=/home/oracle
cd "$(dirname "$0")"

# Figure out if this is a new install or not
test -d "$AVEKSA_WILDFLY_HOME" && FRESH_INSTALL=N || FRESH_INSTALL=Y
export FRESH_INSTALL

. ./common_root.sh

if isVapp; then
    OPT_AFX=Y
    export OPT_AFX
    OPT_CREATESCHEMA=N
    OPT_NOSTART=Y
    QUIET=Y
fi

# Header to indication start of the installation. We cannot print
# the version and build number here yet because those info come
# from the version.txt and changesetinfo.txt in the staging
# directory, and we don't know where staging directory is
# at this point.
headerNoLeadingNL "Starting installation of $PRODUCT_NAME"
echo Installation started on `date` | tee -a $LOG
# Output the options passed thru the command line
echo Install Options: $OPT_STRING_TO_LOG | tee -a $LOG
headerNoLeadingNL

if [ $QUIET = N ]; then
    license
    ret=$?
    if [ $ret -ne 0 ]; then
        echo User does not agree with the license agreement. Exit installation. >> $LOG
        exit 1
    fi
fi

# Load user input $AVEKSA_HOME location from configure.sh to the current script
source configure.sh || exit 1

checkSupportedOS || exit 1
checkforExistingInstall

if [ ${FRESH_INSTALL} = N ]; then
    backupCacerts
fi

# Execute configuration if necessary
export QUIET
export OPT_ASMPART
export OPT_STAGING
export OPT_PACKAGES
export LOG
# If Aveksa_System.cfg exists, save for shutdownSoftware of old software during upgrade
# It is also used when un-deploying an ear. See ACM-60039
test -f "$AVEKSA_HOME"/Aveksa_System.cfg && cp -f "$AVEKSA_HOME"/Aveksa_System.cfg "$AVEKSA_HOME"/Aveksa_System.cfg.shutdown

# The configure.sh could make changes to the variables (e.g. REMOTE_ORACLE) in the Aveksa_System.cfg
# So, refresh the variables here.
setVariables "$AVEKSA_HOME"/Aveksa_System.cfg

# Now that the staging directory is confirmed, lets check for the artifacts that are
# necessary for the installation to go forward. If everything checks out, the
# function will set the $NEW_IMG_VER and $NEW_IMG_BLD variables, based on the files
# in the staging directory.
checkForRequiredFiles
if [ $? -ne 0 ]; then
    logLine Failed check for required Files: Exit installation.
    exit 1
fi

# In case of upgrade, we need to make sure the staging directory and its content
# are owned by oracle/oinstall
#
if [ "${FRESH_INSTALL}" = N ]; then
    updateStagingOwnership
    if [ $? -ne 0 ]; then
        logLine Failed check for staging ownwership :Exit installation.
        exit 1
    fi
fi

header "Starting installation of $PRODUCT_NAME version=${NEW_IMG_VER} build=${NEW_IMG_BLD}"

confirmVersion
ret=$?
if [ $ret -ne 0 ]; then
    echo User indicates this is not the desired version to be installed. Exit installation. >> $LOG
    exit 1
fi

if [ ! -L /tmp/Aveksa_System.cfg ]; then
    rm -f /tmp/Aveksa_System.cfg
    ln -s "$AVEKSA_HOME"/Aveksa_System.cfg /tmp/Aveksa_System.cfg
fi


echo [`date`] Performing pre-requisite checks | tee -a $LOG
${DEPLOY_DIR}/ENV-setup-scripts/InspectSystem.sh other | tee -a $LOG
[ ${PIPESTATUS[0]} -eq 0 ] || error
logLine Pass ... requirements defined by 'Inspect System'
echo [`date`] Pre-requisite checks completed | tee -a $LOG

# We set up vapp users in kiwi, but we need this step to set up their .bash_profile and setDeployEnv.sh

./ENV-setup-scripts/configureUsers.sh
if [ $? -gt 0 ]; then error; fi

#If the required users and groups did not exist and are created as a part of configureUsers.sh, we need to update the staging directory to have owner and group as oracle and oinstall respectively
updateStagingOwnership

header [`date`] Check for and install jdk as needed

checkReqJDKVersion
if [ $? -ne 0 ]; then
    ./JDK-scripts/installJDK.sh
    if [ ${PIPESTATUS[0]} -gt 0 ]; then error; fi
fi

if [ -f "/root/setDeployEnv.sh" ]; then
    # Get the installed Java environment:
    eval $(egrep '^(export )?JAVA_HOME=' /root/setDeployEnv.sh)
    export JAVA_HOME
    export PATH="${JAVA_HOME}/bin:$PATH"
fi

header [`date`] Check for newer install version
header [`date`] Checking environment...
checkForNewerInstalledVersion
if [ $? -eq 0 ] ; then
	echo ""| tee -a $LOG
	echo "=====> A newer version of $PRODUCT_NAME has already been installed <====="| tee -a $LOG
	echo "Downgrade of the $PRODUCT_NAME is not a supported method of installation."| tee -a $LOG
	echo "The existing product needs to be fully removed for the system."| tee -a $LOG
	echo "If using a remote database, the database instance will need to be fully recreated to"
	echo "match the version you are now trying now trying to install"| tee -a $LOG
	echo ""| tee -a $LOG
	echo "Exiting install..."| tee -a $LOG
	exit 1
fi

# Log summary info Log file.
logSummary
echo [`date`] Checking environment completed | tee -a $LOG
############################

#
# In Bowmore (7.0.0), we used to ask the user to confirm about having a off-site backup of the
# database only if an older Oracle version exists on the local system. Now we ask that
# question if this is an upgrade install, regardless of what Oracle version is installed.
#
if [ $FRESH_INSTALL = N -a $QUIET = N ]; then
    if [ $OPT_FORCEFRESHORACLE = Y ]; then
        echo "The installer flag 'FORCEFRESHORACLE' has been used" | tee -a $LOG
        echo "Existing database will be deleted" | tee -a $LOG
        echo "" | tee -a $LOG
    else
        echo "" | tee -a $LOG
        echo "You will need to import a backup after completion of this install to restore your environment."| tee -a $LOG
        echo "Before proceeding, please verify that you have a current backup off of this system." | tee -a $LOG
        echo "See the Upgrade and Migration guide for details on how to generate a database backup." | tee -a $LOG
        echo "" | tee -a $LOG
        echo "Type 'BACKUP-OFFSITE-VERIFIED' to verify backup of the database exists off of this system" | tee -a $LOG
        echo "before upgrading the software [ ]? " >> $LOG
        read -p 'before upgrading the software [ ]? '
        case $REPLY in
            backup-offsite-verified | BACKUP-OFFSITE-VERIFIED)
                echo "Response was : $REPLY" | tee -a $LOG
                ;;
            *)
                echo "Response was : $REPLY" | tee -a $LOG
                echo "" | tee -a $LOG
                echo "The database backup is not verified." | tee -a $LOG
                echo "Exit installation." | tee -a $LOG
                echo "" | tee -a $LOG
                exit 1
                ;;
        esac
    fi
fi

if ! isVapp && [ "$AMAZON_RDS" != "Y" ]; then
    #
    # We are doing 2 things here:
    # 1) Check the database (remote or local) version.
    # 2) Check for any older database is installed on the local system.
    #
    # If this is a new install and using a local database, we do not have to check for
    # database version (because the database is not installed yet). So, only check for
    # the database version in any other cases.
    #
    CONTINUE_WO_LOCAL_DB=N # This variable is for continuing installation without a local database instance. This could
                           # happen when a previous upgrade installation went bad after the point where Oracle was uninstalled.
                           # The next upgrade installation will be running without a local db instance. We
                           # would give the user an option to continue in that case and this variable will be set to 'Y' to indicate that.
    CLEANUP_OLD_DATABASE=N
    ORACLE_UPGRADED=N      # This variable is for logging purpose only.
    if [ $FRESH_INSTALL = N -o $REMOTE_ORACLE = Y ]; then
        if [ -f ${DEPLOY_DIR}/../database/database-supported-versions.properties ]; then
        . ${DEPLOY_DIR}/../database/database-supported-versions.properties
             headerNoLog Below are the list of Supported Oracle Versions...
             supportedVersions=$(echo $supportedVersions | sed 's/\.$/.x/g')
             logLine $supportedVersions
        fi
		header Checking for supported database version...
        checkDBSupportedVersion
        ret=${PIPESTATUS[0]}
        case $ret in
            # Oracle supported version detected
            1)  # Let's see if we need to clean up any old database installed on the local system.
                logLine "=====> Version check for Oracle Database configuration : Oracle Database $ORACLE_CURRENT_VERSION is supported and certified <====="
                if [ -d /u01/app/oracle/product/10.2.0/db_1 \
                  -o -d /u01/app/oracle/product/11.1.0/db_1 \
                  -o -d /u01/app/oracle/product/11.2.0/db_1 \
                  -o -d "$ORACLE_BASE"/product/10.2.0/db_1 \
                  -o -d "$ORACLE_BASE"/product/11.1.0/db_1 \
                  -o -d "$ORACLE_BASE"/product/11.2.0/db_1 ] ; then
                    logLine "=====> Existing Oracle 10.X or 11.X version has been detected <====="
                    logLine "An older version of Oracle was found to be installed on this machine."
                    logLine "This will need to be removed"
                    CLEANUP_OLD_DATABASE=Y
                else
                    CLEANUP_OLD_DATABASE=N
                fi
                ;;
            # Minor version changes detected
            2)  # Prompt user whether to continue with advanced version.
                logLine "=====> Version check for Oracle Database configuration: Oracle Database $ORACLE_CURRENT_VERSION is NOT a certified version <====="
                logLine "=====> WARNING: The Oracle Database $ORACLE_CURRENT_VERSION has not been certified and unexpected issues may occur. Continue the installation at your own risk. <====="
                confirmDatabaseConfiguration
                if [ $? -eq 1 ]; then
                        logLine "Exit installation."
                        exit 1
                fi
                ;;
            # Advanced version detected
            3)  # Prompt user whether to continue with minor version differences.
                logLine "=====> Version check for Oracle Database configuration: Oracle Database $ORACLE_CURRENT_VERSION is NOT a certified version <====="
                logLine "=====> WARNING: The Oracle Database $ORACLE_CURRENT_VERSION has not been certified and unexpected issues may occur. Continue the installation at your own risk. <====="
                confirmDatabaseConfiguration
                if [ $? -eq 1 ]; then
                        logLine "Exit installation."
                        exit 1
                fi
                ;;
            # Older version has been detected.
            4)  # For local database, we're going to uninstall older and install one of supported version. Therefore,
                # print a message about removing the older versions
                #
                # For remote database, since we cannot install any supported version remotely, we'd exit installation.
                if [ $REMOTE_ORACLE = N ]; then
                    CLEANUP_OLD_DATABASE=Y
                    ORACLE_UPGRADED=Y
                    logLine "Current database version... $ORACLE_CURRENT_VERSION"
                    logLine "=====> Older version of Oracle has been detected <====="
                    logLine "${NEW_IMG_VER} requires Oracle Database Version(s) $supportedVersions"
                    logLine "The installer must remove your version of Oracle and install one of certified version(s) $supportedVersions to continue"
                else
                    logLine "Current database version... $ORACLE_CURRENT_VERSION"
                    logLine "=====> Older version of Oracle has been detected <====="
                    logLine "${NEW_IMG_VER} requires Oracle Database Version(s) $supportedVersions"
                    logLine "Because the installation is configured to use a remote database, the installation cannot proceed"
                    logLine "See the Installation guide for more information about upgrade to Oracle version(s) $supportedVersions"
                    logLine ""
                    logLine "Exit installation."
                    exit 1
                fi
                ;;
            # Bad Oracle version detected
            5)
                logLine "Version check for Oracle Database configuration: Oracle Database $ORACLE_CURRENT_VERSION is NOT a certified version and is NOT Supported. The installation cannot proceed."
                logLine "Exit installation."
                exit 1
                ;;
            # Error detecting the Oracle version
            6)
                # We know this is not a fresh install, so we should be able to determine the database version. However,
                # if a previous upgrade installation error out after uninstalling Oracle (for example, the system check
                # failed), we will not be able to check the Oracle version when installation runs again since the local
                # database instance is gone. In this case, check for the existence of /etc/oratab to see if Oracle is
                # installed or not. If it is installed, continue the installation. Otherwise, exit.
                if [ $REMOTE_ORACLE = N ]; then
                    logLine "Error occurred when determining the Oracle version."
                    logLine ""
                    if [ -f /etc/oratab ]; then
                        logLine "Detected Oracle is installed on this server, please use 'service aveksa_server startoracle' to bring Oracle online"
                        logLine "and restart installation."
                        exit 1
                    else
                        logLine "Oracle is not detected on this server, installation will continue to install Oracle and create schema."
                        CONTINUE_WO_LOCAL_DB=Y
                    fi
                else
                    logLine ""
                    logLine "Failed to connect remote Oracle server. Please bring Oracle online and restart installation."
                    logLine ""
                    logLine "Exit installation."
                    exit 1
                fi
                ;;
            # Unexpected return code
            *)
                logLine "Encountered unexpected return code $ret when determining Oracle version."
                logLine "Exit installation."
                exit 1
                ;;
        esac
        logLine ""
        logLine Checking for supported database version completed
    fi

    # After the user confirmed the backup is done (or the script will
    # exit above, and we will not get here), start cleaning the old
    # Oracle version.
    #
    # TODO: The above code checks for multiple old Oracle versions, but the cleanOracle11G.sh has
    #       hard coded 11.2.0 version in it. So, we might need to:
    #       1) Make sure to clean up every old version we find, and
    #       2) Make the cleanOracle11G.sh to not hard code the Oracle version (if the uninstall
    #          process is the same for all the older versions).
    if [ $CLEANUP_OLD_DATABASE = Y ]; then
        ./cleanOracle11G.sh | tee -a $LOG
        if [ ${PIPESTATUS[0]} -ne 0 ]; then
            echo "Encounter error in cleanOracle11G.sh." | tee -a $LOG
            echo "Exit installation." | tee -a $LOG
            exit 1
        fi
    fi

    setOracle12CHomes
    ####################

    # If we're running an upgrade installation without the local db instance, set the db options as it is a new installation.
    if [ $CONTINUE_WO_LOCAL_DB = Y ]; then
        MIGRATE_DATABASE=N
        CREATE_DATABASE=Y
        PRESERVE_DATABASE=N
        CHECK_LOCAL_INSTANCE=N
    else
        decideDatabase || exit 1
    fi
    checkEnvironmentPreReqs || exit 1

    header [`date`] Checking for required packages...
    checkRequiredPackages
    if [ $? -gt 0 ]; then error; else echo [`date`] Checking for required packages completed | tee -a $LOG; fi

    header [`date`] Checking for packages directory...
    checkPackagesDir
    if [ $? -gt 0 ]; then error; else echo [`date`] Checking for packages directory completed | tee -a $LOG; fi

    if [ $REMOTE_ORACLE = N ]; then
    	if [ $PRESERVE_DATABASE = N ]; then

    		header [`date`] Checking System Settings...
    		z=0
    		${DEPLOY_DIR}/ENV-setup-scripts/InspectSystem.sh sysctl | tee -a $LOG
    		RETVAL=${PIPESTATUS[0]}
    		while [ $RETVAL -ne 0 ] ; do
    			if [ $RETVAL -eq 2 ] ; then
    				error
    			else
    				z=`expr $z + 1`
    				logLine Checking System Settings after interation $z of /tmp/modify_kernel_settings.sh ...
    				cat /tmp/modify_kernel_settings.sh  >>$LOG
    				${DEPLOY_DIR}/ENV-setup-scripts/InspectSystem.sh sysctl | tee -a $LOG
    				RETVAL=${PIPESTATUS[0]}
    			fi
    		done
    	fi
    fi

    if [ $REMOTE_ORACLE = N ]; then
    	if [ $PRESERVE_DATABASE = N ]; then
    		if [ ! -f ${ORACLE_HOME}/${ORACLE_BASENAME} -a $CHECK_LOCAL_INSTANCE = Y -a $CREATE_DATABASE = N ]; then
    			header Preparing for Oracle Upgrade...
    			if [ $CHECK_CONNECT = N ]; then
    				echo Cannot connect to the local database instance to run pre-upgrade script. | tee -a $LOG
    				error
    			fi

    			# execute the Oracle 11.2 pre-upgrade script
    			echo "PURGE DBA_RECYCLEBIN;" > /tmp/recycle.in
                # Removed the call to utlu112i.sql until we figure out what we should do for 12c:
    			#echo "@$DEPLOY_DIR/oracle/utlu112i.sql" >> /tmp/recycle.in
                chmod 777 /tmp/recycle.in
                $AS_AVEKSA_OWNER "$DEPLOY_DIR/../database/cliAveksa.sh -f /tmp/recycle.in -sys" >> $LOG
                rm /tmp/pfile.in
    		fi
    	fi
    fi

    header [`date`] Shutting down $PRODUCT_NAME...
    if [ -f "$AVEKSA_HOME"/Aveksa_System.cfg.shutdown ]; then
    	# restore the original Aveksa_System.cfg so that shutdown will work right
    	mv "$AVEKSA_HOME"/Aveksa_System.cfg "$AVEKSA_HOME"/Aveksa_System.cfg.new
    	mv "$AVEKSA_HOME"/Aveksa_System.cfg.shutdown "$AVEKSA_HOME"/Aveksa_System.cfg
    fi
    shutdownSoftware >>$LOG 2>&1
    if [ -f "$AVEKSA_HOME"/Aveksa_System.cfg.new ]; then
    	# restore the new Aveksa_System.cfg now that shutdown is complete
    	mv "$AVEKSA_HOME"/Aveksa_System.cfg.new "$AVEKSA_HOME"/Aveksa_System.cfg
    fi
    echo [`date`] Shutting down $PRODUCT_NAME completed | tee -a $LOG
fi

if ! isVapp; then
    # Install or configure Oracle
    if [ $REMOTE_ORACLE = N ]; then
    	#  First check if we have a local instance if we do then we do not have to install.
    	if [ $CHECK_LOCAL_INSTANCE = N ]; then
    		# Install Oracle ASM drivers if appliance and we have installed Oracle
    		if [ $APPLIANCE = Y -a $CREATE_ASM = Y -a -f ${PACKAGES_DIR}/${ASMLIB_PACKAGE} -a ! -f "${AVEKSA_HOME}"/.${ASMLIB_BASENAME} ]; then
    			header [`date`] Installing Oracle ASM drivers...
    			./installOracleASM.sh >>$LOG
    			if [ $? -gt 0 ]; then error; else echo [`date`] Installing Oracle ASM drivers completed | tee -a $LOG; fi
    		fi
    	fi

    	# Determine if we needed ASM packages
    	ASM_OK=N
    	if [ $APPLIANCE = N -o $CREATE_ASM = N -o -f "${AVEKSA_HOME}"/.${ASMLIB_BASENAME} ]; then
    		ASM_OK=Y
    	fi

    	# Install Oracle
    	if [ $ASM_OK = Y -a -f ${PACKAGES_DIR}/${ORACLE_PACKAGE1} -a -f ${PACKAGES_DIR}/${ORACLE_PACKAGE2} -a -f ${PACKAGES_DIR}/${ORACLE_PACKAGE3}  -a ! -f ${ORACLE_HOME}/${ORACLE_BASENAME} ]; then
    		header [`date`] Installing ${ORACLE_BASENAME} ...
    		./installOracle.sh >>$LOG
    		if [ $? -gt 0 ]; then error; else echo [`date`] Installing ${ORACLE_BASENAME} completed | tee -a $LOG; fi
    	fi

    	# bring up the database in case we skipped installing Oracle
    	header [`date`] Starting Oracle...
    	$DEPLOY_DIR/init.d/aveksa_server startoracle >>$LOG
        echo [`date`] Starting Oracle completed | tee -a $LOG

    	logToFile =============================================================================
    	logToFile Customizing ${ORACLE_SID} memory settings . . .
    	logToFile

    	if [ $USE_ASM = Y ]; then
    		cp -f $DEPLOY_DIR/create_avdb/templates/AVDBASM-generic.dbt $DEPLOY_DIR/create_avdb/templates/AVDBASM-custom.dbt
    		custom=$DEPLOY_DIR/create_avdb/templates/AVDBASM-custom.dbt
    	else
    		cp -f $DEPLOY_DIR/create_avdb/templates/AVDBFS-generic.dbt $DEPLOY_DIR/create_avdb/templates/AVDBFS-custom.dbt
    		custom=$DEPLOY_DIR/create_avdb/templates/AVDBFS-custom.dbt
    	fi

        # MEM will be in kb; convert to mb
        MEM=$(($(grep MemTotal /proc/meminfo | awk -F" " '{print $2}')/1024))

        # 2GB for base OS
        OS_MEM=2048

        # 3GB to AFX if installed
        [[ -f /etc/init.d/afx_server || $OPT_AFX = Y ]] && AFX_MEM=3072 || AFX_MEM=0

        # Available memory for application server and database
        APP_MEM=$(($MEM - $OS_MEM - $AFX_MEM ))
        # 65% to Oracle : 22% - PGA, 43% - SGA

        sed -i "s/PGA_AGG_VALUE/$((${APP_MEM} * 22 / 100))/g"  ${custom}
        sed -i "s/SGA_VALUE/$((${APP_MEM} * 43 / 100))/g"  ${custom}

    	# Create the database instance if it doesn't exist
    	if [ $CHECK_LOCAL_INSTANCE = N -o $CREATE_DATABASE = Y ]; then
    		header [`date`] Creating AVDB Instance...
    		./createDB.sh >>$LOG
    		if [ $? -gt 0 ]; then error; else echo [`date`] Completed Create AVDB `/bin/date` | tee -a $LOG; fi
    	else
    		header [`date`] Upgrading AVDB Instance...
    		$AS_AVEKSA_OWNER "$STAGING_DIR/database/cliAveksa.sh -upgradeDB $*" >>$LOG
    		if [ $? -gt 0 ]; then error; else echo [`date`] Upgrading AVDB Instance completed | tee -a $LOG; fi
    	fi
    fi


    if [ "${CHECK_CONNECT}" = N ]; then
        if [ $REMOTE_ORACLE = Y ]; then
            echo "Checking for database connections again..."
        fi
    	checkDatabase
    fi
    if [ "${CHECK_CONNECT}" = N ]; then
    	echo ''
    	echo ERROR: Unable to connect to the database\; aborting installation   | tee -a $LOG
    	echo ''
    	echo Use \"sudo $DEPLOY_DIR/configure.sh\" to repeat the configuration questions. | tee -a $LOG
    	echo Use \"sudo $DEPLOY_DIR/install.sh\" to retry the installation.  | tee -a $LOG
    	exit 1
    fi
fi

#TBD This should be moved to end of script.
header [`date`] Installing Aveksa Support Files....
./ENV-setup-scripts/installSupportFiles-root.sh >>$LOG
if [ $? -gt 0 ]; then error; else echo [`date`] Installation of Aveksa support files completed | tee -a $LOG; fi

header [`date`] Installing database Support Files....
./ENV-setup-scripts/installSupportFiles.sh >>$LOG
if [ $? -gt 0 ]; then error; else echo [`date`] Installation of database support files completed | tee -a $LOG; fi

if ! isVapp; then
    if [ $MIGRATE_DATABASE = Y ]; then
    	header Migrating database ... `date`
    	echo Migrating database started : `date` >>$LOG
    	./migrate.sh >>$LOG 2>&1
    	# show the migration errors (oracle errors)
    	# Skip ones that are part of a sql comment -- ORA- or /* ORA- */
    	egrep "(ORA-)|(SP-)|(ERROR \[)" "$AVEKSA_HOME"/database/log/migrate.log |  egrep -v "*--.* ORA-*" | egrep -v "/\*.*ORA-.*\*/"

    	echo Migrating database completed : `date` | tee -a $LOG
    fi

    if [ $CREATE_DATABASE = Y ]; then
    	header [`date`] Creating schema...
    	./createSchema.sh >>$LOG
    	if [ $? -gt 0 ]; then error; else echo [`date`] Creating schema completed | tee -a $LOG; fi
    fi
else
    cp ${DEPLOY_DIR}/oracle/Check_Instance_Running.sh ${USR_BIN}/.
    chmod 755 ${USR_BIN}/Check_Instance_Running.sh
fi

# Install tests
if [ $OPT_TESTS = Y ]; then
    header [`date`] Install tests
    ./installTests.sh >>$LOG
    ${AS_AVEKSA_OWNER} "'$AVEKSA_HOME'/qa/deploy/setup_tests.sh" >>$LOG
    echo [`date`] Install test scripts completed | tee -a $LOG
fi

if ! isVapp; then
    header [`date`] Configuring SSL Certificates...
    ./ACM-scripts/configureSSLCertificates.sh >>$LOG
    if [ $? -gt 0 ]; then error; else echo [`date`] Configuring SSL Certificates completed | tee -a $LOG; fi
fi

header [`date`] Installing Aveksa Web Application...
header [`date`] Checking for ${WILDFLY_BASENAME}...
if [ -d "${AVEKSA_HOME}"/${WILDFLY8_BASENAME} ] ; then
    echo [`date`] Removing older wildfly symbolic link | tee -a $LOG
    rm -f "$AVEKSA_HOME"/wildfly
fi
if [ -d "${AVEKSA_HOME}"/wildfly ] ; then
    $DEPLOY_DIR/init.d/aveksa_server start >>$LOG || error
    if checkEarDeployed; then
        ./ACM-scripts/cleanACM${APPSERVER}.sh >>$LOG || error
    fi
    $DEPLOY_DIR/init.d/aveksa_server stop >>$LOG
    # If functional testing, always revert back to base app server config
    if [ "$OPT_TESTS" = "Y" ]; then
        cp "${AVEKSA_HOME}"/${WILDFLY_BASENAME}/standalone/configuration/standalone-full.xml "${AVEKSA_HOME}"/${WILDFLY_BASENAME}/standalone/configuration/aveksa-standalone-full.xml
    fi
else
	header [`date`] Installing Wildfly...
	./Wildfly-scripts/installWildfly.sh >>$LOG
	if [ $? -gt 0 ]; then error; echo [`date`] Installing Wildfly completed | tee -a $LOG; fi
fi
echo [`date`] Checking for Wildfly completed | tee -a $LOG

if ! isVapp; then
	# Stop AFX services before install/upgrade
    if [ $OPT_AFX = Y ]; then
          
		header [`date`] Stopping AFX services for install/upgrade preparation...
                service afx_server stop 2>/dev/null
		
		if [ $? -ne 0 ]; then
			header [`date`] Retry AFX stop as service does not exist
			/etc/init.d/afx_server stop 2>/dev/null
		fi
	fi
    ./ACM-scripts/installACM.sh
fi

if ! isVapp; then
    header [`date`] Configuring System Settings...
    ./ENV-setup-scripts/configureSystemSettings.sh >>$LOG
    if [ $? -gt 0 ]; then error; else echo [`date`] Configuring System Settings completed | tee -a $LOG; fi


    header [`date`] Restoring Files from Database...
    ./restoreFilesFromDB.sh >>$LOG
    if [ $? -gt 0 ]; then error; else echo [`date`] Restoring Files from Database completed | tee -a $LOG; fi

    if [ $APPLIANCE = Y ]; then
    	header [`date`] Configuring FTP Server...:w:
    	./ENV-setup-scripts/configureFTP.sh >>$LOG
    	if [ $? -gt 0 ]; then error; else echo [`date`] Configuring FTP Server completed | tee -a $LOG; fi
    fi
fi

# Install AFX
if [ $OPT_AFX = Y ]; then
	header [`date`] Installing/upgrading AFX services...
	./AFX-scripts/installAFX.sh -q >>$LOG
	RESULT=$?
	if [ $RESULT -gt 0 ]; then
	    if [ $RESULT -ne 99 ]; then
	        error;
        fi
    fi
    echo [`date`] Installing/upgrading services completed | tee -a $LOG
fi

#TBD : This should be moved out.
# Remove deprecated files during upgrade
if [ "${FRESH_INSTALL}" = "N" ]; then
    header Removing deprecated files...
    DEPRECATED_FILE=deprecatedFiles.txt

    if [ -f  ${DEPRECATED_FILE} ]; then
        for f in $(cat ${DEPRECATED_FILE}); do
            file="$(echo "$f" | sed -e "s#\${AVEKSA_HOME}#$AVEKSA_HOME#g")"
            if [ -f "$file" -o -d "$file" ]; then
               rm -rf "$file"
               if [ $? -eq 0 ] ; then
                  logToFile "Removed deprecated file: $file"
               else
                  logToFile "Removing deprecated file: $file failed"
               fi
            fi
        done
    fi
fi

ln -sf "${AVEKSA_WILDFLY_HOME}"/bin/jboss-cli.xml "${AVEKSA_HOME}"/deploy/jboss-cli.xml

# Start services
if ! isVapp && [ $OPT_NOSTART = N ]; then
	header [`date`] Starting services...
	$DEPLOY_DIR/init.d/aveksa_watchdog start >>$LOG
	if [ $? -gt 0 ]; then error; fi
	$DEPLOY_DIR/init.d/aveksa_server start >>$LOG
	if [ $? -gt 0 ]; then error; fi

    if [ $OPT_AFX = Y ]; then
    	service afx_server start >>$LOG
    fi
	echo [`date`] Starting services completed | tee -a $LOG
fi

# update permissions and ownership
echo "Changing ownership $AVEKSA_OWNER:$AVEKSA_GROUP"
chown  ${AVEKSA_OWNER}:${AVEKSA_GROUP} "$AVEKSA_HOME"/Aveksa_System.cfg
chown  ${AVEKSA_OWNER}:${AVEKSA_GROUP} /tmp/Aveksa_System.cfg

chmod o-rwx "$AVEKSA_HOME"/Aveksa_System.cfg

lockdown_user_privileges
chmod o-rwx "${AVEKSA_HOME}"
if  [ $REMOTE_ORACLE = N ]; then
# Ensure usage of 64-bit pam limits library, rather then 32-bit, force 64-bit path. prevents lockout from console login
	if [ -f /lib64/security/pam_limits.so ] ; then sed -i 's#^session.*.required.*.pam_limits.so.*#session required /lib64/security/pam_limits.so#g' /etc/pam.d/login; fi
fi

#### Print out the summary of the installation
printConfiguration | tee -a $LOG

if [ "${ORACLE_UPGRADED}" = "Y" ]; then
    echo Oracle is upgraded: Yes, it has been upgraded to 12c | tee -a $LOG
else
    echo Oracle is upgraded: No | tee -a $LOG
fi

if [ "${FRESH_INSTALL}" = "Y" ]; then
    echo New install: Yes | tee -a $LOG
else
    echo New install: No | tee -a $LOG
fi
####

#### Print out the message and time of completion
echo ""
echo Installation of ${PRODUCT_NAME} version=${NEW_IMG_VER} build=${NEW_IMG_BLD} completed on `date` | tee -a $LOG
headerNoLeadingNL
####

echo
echo "Log available at $LOG"
echo
