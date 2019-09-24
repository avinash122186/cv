#!/bin/bash
#
# Common include script for Aveksa deployment scripts.
# Reference using ". ./common.sh"
#

PRODUCT_NAME="@PRODUCT_NAME@"
RELEASE_NOTES_LOC="@RELEASE_NOTES_LOCATION@"

##----------- Hard coded Values ------------------

# JAVA packages
JDK_NAME=AdoptOpenJDK
JAVA_BASENAME=jdk8u212-b03
JAVA_PACKAGE=adoptjdk_8u212b03.tar.gz
JAVA_VERSION=1.8.0
JAVA_PATCH_VERSION=212

# JBOSS packages
JBOSS_BASENAME=jboss-4.2.2.GA
WILDFLY8_BASENAME=wildfly-8.2.0.Final
WILDFLY_BASENAME=wildfly-10.1.0.Final
DOMAIN_MASTER="$(hostname -f)"
DEFAULT_DOMAIN_USER=AveksaClusterAdmin
DEFAULT_DOMAIN_PASSWORD=test

# Oracle Packages
ASMLIB_BASENAME=asmlib-008
ORACLE_BASENAME=Oracle.12.1.0.2.0
ASMLIB_PACKAGE=${ASMLIB_BASENAME}_x64.tar.bz2
ORACLE_PACKAGE1=linuxamd64_12102_database_1of2.zip
ORACLE_PACKAGE2=linuxamd64_12102_database_2of2.zip
ORACLE_PACKAGE3=linuxamd64_12102_grid_1of2.zip
ORACLE_PACKAGE4=linuxamd64_12102_grid_2of2.zip
ORACLE_CURRENT_VERSION=

JBOSS_PACKAGE=${JBOSS_BASENAME}.zip
WILDFLY_PACKAGE=${WILDFLY_BASENAME}.tar

# app server to install: JBoss
APPSERVER=Wildfly

#------- System based Variables ---------------------

# Sets and checks IS64BIT
if [ "$HOSTTYPE" = "x86_64" ]; then
        IS64BIT=Y
else
        echo Operating System is 32 bit. 32 bit is not supported. | tee -a $LOG
        echo "The existing Operating System version is unsupported or unknown." | tee -a $LOG
        echo "Please install a required operating system before proceeding with this install." | tee -a $LOG
        echo "See the $PRODUCT_NAME Installation guide for more information regarding OS installation." | tee -a $LOG
        exit 1
fi
export DEPLOY_DIR=$(cd $(dirname $0) & pwd)

# Make sure we have a home directory
export USER_HOME=`getent passwd ${AVEKSA_OWNER:-oracle} | cut -d: -f6`

if [ -z "$QUIET" ]; then
        QUIET=N
fi
if [ -z "$LOG" ]; then
    LOG=/tmp/aveksa-install.log
fi



# Make sure everything needed is on the path
/bin/echo :$PATH | /bin/grep -q ":/usr/bin" || PATH=/usr/bin:$PATH
/bin/echo :$PATH | /bin/grep -q ":/bin" || PATH=/bin:$PATH
/bin/echo :$PATH | /bin/grep -q ":/usr/sbin" || PATH=/usr/sbin:$PATH
/bin/echo :$PATH | /bin/grep -q ":/sbin" || PATH=/sbin:$PATH
export PATH

#----------------Logging Methods-------------------
# methods take function <String> ie
# these are used to out information to standard Out and/or Log file
# Defined file is $LOG  defaults to /tmp/avkesa-install.log
#
# logLine This is to be logged
# header [`date`] Checking for ${WILDFLY_BASENAME}...
# The echo XXX |tee #LOG should be updated to use logLine

# Just echos to the screen with a header line
headerNoLog() {
    echo
    echo --------------------------------------------------------------------------
    echo $*
}
# Starts a header line to log file and screen
header() {
    headerNoLog $*
        echo >>$LOG
        echo -------------------------------------------------------------------------- >>$LOG
        echo $* >>$LOG
}

logLine() {
# To screen
        echo $*
# To log file
        echo $* >>$LOG
}

logToFile() {
# To log file
        echo $* >>$LOG
}

headerNoLeadingNL() {
    echo -------------------------------------------------------------------------- | tee -a $LOG
    echo $* | tee -a $LOG
}

more() {
	if [ -x /usr/bin/more ]; then
		/usr/bin/more $*
	elif [ -x /usr/bin/less ]; then
		/usr/bin/less -E -F $*
	else
		/usr/bin/cat $*
	fi
}


setVariables() {
	while read line
	do
		if [ "${line}" ]; then
			if [ -n "${line}" ]; then
				if [ "${line:0:1}" != "#" ]; then
					parameter=${line%%=*}
					value="${line#*=}"
					#echo "Parameter: '$parameter', value: '$value'"
					eval $parameter='$value'
					export "$parameter"
				fi
			fi
		fi
	done < "$1"
}

needsConfigure() {
	# Create the system configuration file if missing
	if [ ! -d "$AVEKSA_WILDFLY_HOME" ]; then
		return 0
	fi

	# Checking for missing settings
	if ! grep -q STAGING_DIR "$AVEKSA_HOME"/Aveksa_System.cfg; then
		return 0;
	fi
	if ! grep -q PACKAGES_DIR "$AVEKSA_HOME"/Aveksa_System.cfg; then
		return 0;
	fi
	return 1
}

# Print the configuration information. This
# is being used when confirming the configuration
# and reporting the configuration in the log
printConfiguration() {
    echo
    echo --------------------------------------------------------------------------
    echo "Summary of install information"
    echo
    echo "Location of installation files: $STAGING_DIR "
    echo "Location of package files: $PACKAGES_DIR "
    echo "Location of product installation: $AVEKSA_HOME "
    if [ -n "$ORACLE_BASE" -a $REMOTE_ORACLE = N ]; then
        echo "Location of oracle installation: $ORACLE_BASE "
    fi
    echo "Use remote Oracle server: $REMOTE_ORACLE "
    if  [ $REMOTE_ORACLE = Y ]; then
        echo "Oracle listener hostname: $REMOTE_ORACLE_IP"
        echo "Oracle listener port number: $REMOTE_ORACLE_PORT"
        echo "Oracle SID: $ORACLE_SID"
        echo "Oracle Service Name: $ORACLE_SERVICE_NAME"
    fi
    if [ $APPLIANCE = Y -a $REMOTE_ORACLE = N ]; then
        echo "Oracle ASM partition: $ASM_PARTITION "
    fi
    echo
}

# Print the Database configuration information. This
# is being used when confirming the configuration
# and reporting the configuration in the log
printDBOnlyConfiguration() {
    echo
    echo --------------------------------------------------------------------------
    echo "Summary of Database install information"
    echo
    if [ -n "$ORACLE_BASE" -a "$REMOTE_ORACLE" = N ]; then
        echo "Location of oracle installation: $ORACLE_BASE "
    fi
    echo
}

confirmConfiguration() {
	# Show configure information ask if correct
	if [ "$INSTALL_DATABASE_ONLY" = Y ]; then
	    printDBOnlyConfiguration
	else
	printConfiguration
	fi
    read -p "Does this match your current install information (yes or no)? "
	case $REPLY in
	    y* | Y*)
	        return 0;
		;;
	    n* | N*)
		    return 1;
		;;
	    esac
	return 0
}

logSummary() {
# TBD This should be conditional and only show pertinant information
    logToFile "Install Summary"
    logToFile "System Information: `uname -a` "
    logToFile "OS Version                  $OSVERSION"
    logToFile "IS64BIT                     $IS64BIT"
    logToFile "AVEKSA_OWNER                $AVEKSA_OWNER"
    logToFile "AVEKSA_ADMIN                $AVEKSA_ADMIN"
    logToFile "AVEKSA_GROUP                $AVEKSA_GROUP"
    logToFile "AVEKSA_ADMIN_GROUP          $AVEKSA_ADMIN_GROUP"
    logToFile "DBA_GROUP                   $DBA_GROUP"
    logToFile "DATA_DIR_GROUP              $DATA_DIR_GROUP"
    logToFile "AVEKSA_HOME                 $AVEKSA_HOME"
    logToFile "USR_BIN                     $USR_BIN"
    logToFile "ORACLE_HOME                 $ORACLE_HOME"
    logToFile "JAVA_HOME                   $JAVA_HOME"
    logToFile "AVEKSA_WILDFLY_HOME         $AVEKSA_WILDFLY_HOME"
    logToFile "ASM_SID                     $ASM_SID"
    logToFile "USE_ASM                     $USE_ASM"
    logToFile "ORACLE_SID                  $ORACLE_SID"
    logToFile "ORACLE_SERVICE_NAME         $ORACLE_SERVICE_NAME"
    logToFile "ORACLE_CONNECTION_ID        $ORACLE_CONNECTION_ID"
    logToFile "AVEKSA_ORACLE_DB_USER       $AVEKSA_ORACLE_DB_USER"
    logToFile "STAGING_DIR                 $STAGING_DIR"
    logToFile "PACKAGES_DIR                $PACKAGES_DIR"
    logToFile "ASMLIB_BASENAME             $ASMLIB_BASENAME"
    logToFile "ASMLIB_PACKAGE              $ASMLIB_PACKAGE"
    logToFile "ORACLE_BASENAME             $ORACLE_BASENAME"
    logToFile "ORACLE_PACKAGE1             $ORACLE_PACKAGE1"
    logToFile "ORACLE_PACKAGE2             $ORACLE_PACKAGE2"
    logToFile "ORACLE_PACKAGE3             $ORACLE_PACKAGE3"
    logToFile "ORACLE_PACKAGE4             $ORACLE_PACKAGE4"
    logToFile "AVEKSA_USER                 $AVEKSA_USER"
    logToFile "AVEKSA_REPORTS_USER         $AVEKSA_REPORTS_USER"
    logToFile "AVEKSA_PUBLIC_DB_USER       $AVEKSA_PUBLIC_DB_USER"
    logToFile "AVEKSA_AVPERF_USER          $AVEKSA_AVPERF_USER"
    logToFile "JAVA_BASENAME               $JAVA_BASENAME"
    logToFile "JAVA_PACKAGE                $JAVA_PACKAGE"
    logToFile "WILDFLY_BASENAME            $WILDFLY_BASENAME"
    logToFile "WILDFLY_PACKAGE             $WILDFLY_PACKAGE"
    logToFile "AGENT_HOME                  $AGENT_HOME"
    logToFile "DEPLOY_DIR                  $DEPLOY_DIR"
    logToFile "APPLIANCE                   $APPLIANCE"
    logToFile "AS_AVEKSA_OWNER             $AS_AVEKSA_OWNER"
    logToFile "FRESH_INSTALL               $FRESH_INSTALL"
    logToFile "NEW_IMG_VER                 $NEW_IMG_VER"
    logToFile "NEW_IMG_BLD                 $NEW_IMG_BLD"
    logToFile "DBONLY_INSTALL              $OPT_DBONLY"
}

checkDatabase() {
    header [`date`] Checking database connections...
    echo "Checking database..." | tee -a $LOG
	CHECK_LOCAL_INSTANCE=N
	CHECK_CONNECT=N
	CHECK_SCHEMA=N

	if [ $REMOTE_ORACLE = N ]; then
		if [ -f /etc/oratab ]; then
			if grep -q "^AVDB:" /etc/oratab
			then
				CHECK_LOCAL_INSTANCE=Y
				logToFile "Validated oracle configured to SID: AVDB "
			fi
		fi
	fi

	grep -q "^${AVEKSA_OWNER}:" /etc/passwd || return 1
	USER_HOME=`getent passwd ${AVEKSA_OWNER:-oracle} | cut -d: -f6`
	if [ ! -f "$USER_HOME"/setDeployEnv.sh ]; then
		if [ "${FRESH_INSTALL}" = N ]; then
			# no oracle user so no sqlplus
		    logToFile "No Oracle user found"
			return 3
		else
			return 0
    	fi
	fi

    # Check it is running
    $AS_AVEKSA_OWNER "$DEPLOY_DIR/../database/cliAveksa.sh -check dbrunning silent" >/dev/null 2>&1
	if [ $? -gt 0 ]; then
        logToFile "Failed to connect to the database"
		# not able to connect
		return 2
	fi

    # Check the db user entered credentials in case of install with remote DB

	if [ $REMOTE_ORACLE = Y ]; then
	    $AS_AVEKSA_OWNER "$DEPLOY_DIR/../database/cliAveksa.sh -check dbcredentials" >/dev/null 2>&1
		if [ $? -gt 0 ]; then
			logToFile "Invalid Username/Password"
			# no schema
			return 1
		fi
    fi

    CHECK_CONNECT=Y

    # Check the schema is installed
    $AS_AVEKSA_OWNER "$DEPLOY_DIR/../database/cliAveksa.sh -check dbschema" >/dev/null 2>&1
	if [ $? -gt 0 ]; then
        logToFile "No schema found in database"
		# no schema
		return 1
	fi

	CHECK_SCHEMA=Y
    echo [`date`] Checking database connections completed | tee -a $LOG
	return 0
}

# This function eventually will execute the Java method CheckSettingsModule#checkSupportedDBVersion().
# Returns
#   - 1 if the database certified.
#   - 2 if minor version differences found.
#   - 3 Advanced version found.
#   - 4 Older version found.
#   - 5 Bad version found.
#   - 6 Unknown version found/an error occurred (e.g. cannot connect to the database).
checkDBSupportedVersion() {
    getCurrentDBVersion
    $AS_AVEKSA_OWNER "O12C_PCV=\$($DEPLOY_DIR/../database/cliAveksa.sh -check dbversion silent $*); grep -q "ERROR:" <<< \$O12C_PCV; if [ \$? -eq 0 ]; then echo \$O12C_PCV; exit 2; else exit \$O12C_PCV; fi;";
	O12C_PCV=$($AS_AVEKSA_OWNER "$DEPLOY_DIR/../database/cliAveksa.sh -check dbversion silent $*" 2>&1)
	if echo "$O12C_PCV" | grep -qi 'error'; then
		echo "$O12C_PCV"
		DBVER=2
	else
		DBVER="$O12C_PCV"
	fi

    return $DBVER
}

getCurrentDBVersion(){
    ORACLE_CURRENT_VERSION=$($AS_AVEKSA_OWNER "$DEPLOY_DIR/../database/cliAveksa.sh -check currentdbversion silent  2>&1");
}

confirmDatabaseConfiguration() {
	# Show configure information ask if correct
    read -p "To proceed, agree that you understand that this installation scenario has not been certified and there is a risk of unexpected issues.
                Do you wish to proceed?  [NO/AGREE] ?"
	case $REPLY in
	    a* | A*)
	        return 0;
		;;
	    n* | N*)
		    return 1;
		;;
	    esac
	return 1
}

checkForNewerInstalledVersion() {
    TEMPFILE="/tmp/.installed_productVersion.txt"; test -f $TEMPFILE && rm -f $TEMPFILE
    if [ -z $NEW_IMG_VER ]; then
        NEW_IMG_VER=`cat ${STAGING_DIR}/version.txt | cut -d= -f2`
    fi

	IMG_VER=`$DEPLOY_DIR/../database/cliAveksa.sh -check productversion silent`
	if [ $? -eq 0 ] ; then
		if [ $(echo $IMG_VER | cut -f1 -d.) -gt $(echo $NEW_IMG_VER | cut -f1 -d.) ] ; then
			return 0
		fi
		if [ $(echo $IMG_VER | cut -f1 -d.) -lt $(echo $NEW_IMG_VER | cut -f1 -d.) ] ; then
			return 1
		fi
		if [ $(echo $IMG_VER | cut -f2 -d.) -gt $(echo $NEW_IMG_VER | cut -f2 -d.) ] ; then
			return 0
		fi
		if [ $(echo $IMG_VER | cut -f2 -d.) -lt $(echo $NEW_IMG_VER | cut -f2 -d.) ] ; then
			return 1
		fi
		if [ $(echo $IMG_VER | cut -f3 -d.) -gt $(echo $NEW_IMG_VER | cut -f3 -d.) ] ; then
			return 0
		else
			return 1
		fi
	fi
	return 1
}


decideDatabase() {
	RETVAL=1
	# Determine if we are going to create the schema or migrate the database
	MIGRATE_DATABASE=N
	CREATE_DATABASE=N
	PRESERVE_DATABASE=N
	checkDatabase
	if [ $OPT_MIGRATE == Y ]; then
		MIGRATE_DATABASE=Y
		CREATE_DATABASE=N
	elif [ $OPT_CREATESCHEMA == Y ]; then
		MIGRATE_DATABASE=N
		CREATE_DATABASE=Y
	elif [ $OPT_NOCREATEMIGRATE == Y ]; then
		MIGRATE_DATABASE=N
		CREATE_DATABASE=N
	elif [ $CHECK_SCHEMA = Y ]; then
		if [ $QUIET = N ]; then
			PRESERVE_DATABASE=Y
			INVALID=Y
			while [ $INVALID = Y ]; do
				INVALID=N
				if [ $REMOTE_ORACLE = N ]; then
					echo
					read -p "An existing database was found.  Do you want to keep the database instance[$PRESERVE_DATABASE]? "
					case $REPLY in
					y* | Y*)
						PRESERVE_DATABASE=Y
						MIGRATE_DATABASE=Y
						CREATE_DATABASE=N
						;;
					n* | N*)
						PRESERVE_DATABASE=N
						MIGRATE_DATABASE=N
						CREATE_DATABASE=Y
						;;
					esac
				fi

				if [ $PRESERVE_DATABASE = N ]; then
					echo
					read -p "All data in the database will be destroyed.  Do you want to recreate the database [$CREATE_DATABASE]? "
					case $REPLY in
					y* | Y*)
						CREATE_DATABASE=Y
						;;
					n* | N*)
						CREATE_DATABASE=N
						INVALID=Y
						;;
					esac
				fi
			done
		else
			# When in silent mode, we are assuming this is a non-interactive installation and will require an automated migration.
			MIGRATE_DATABASE=Y
			CREATE_DATABASE=N
			PRESERVE_DATABASE=Y
		fi
	elif [ $CHECK_CONNECT == Y ]; then
		# can connect to remote/local database but there was no schema
		MIGRATE_DATABASE=N
		CREATE_DATABASE=Y
	elif [ $REMOTE_ORACLE == N -a $CHECK_LOCAL_INSTANCE == Y ]; then
		echo
		echo "Unable to connect the local database to determine if the database can be migrated." | tee -a $LOG
		if [ $QUIET = N ]; then
			PRESERVE_DATABASE=Y
			INVALID=Y
			while [ $INVALID = Y ]; do
				INVALID=N
				echo
				read -p "Do you want to keep the database [$PRESERVE_DATABASE]? "
				case $REPLY in
				y* | Y*)
					PRESERVE_DATABASE=Y
					MIGRATE_DATABASE=Y
					CREATE_DATABASE=N
					;;
				n* | N*)
					PRESERVE_DATABASE=N
					MIGRATE_DATABASE=N
					CREATE_DATABASE=Y
					;;
				esac

				if [ $PRESERVE_DATABASE = N ]; then
					echo
					read -p "All data in the database will be destroyed.  Do you want to recreate the database [$CREATE_DATABASE]? "
					case $REPLY in
					y* | Y*)
						CREATE_DATABASE=Y
						;;
					n* | N*)
						CREATE_DATABASE=N
						INVALID=Y
						;;
					esac
				fi
			done
		else
			# assume migration
			MIGRATE_DATABASE=Y
			CREATE_DATABASE=N
		fi
	elif [ $REMOTE_ORACLE == N -a $CHECK_LOCAL_INSTANCE == N ]; then
		# can't connect to local database and there is no local instance
		MIGRATE_DATABASE=N
		CREATE_DATABASE=Y
	fi

	export MIGRATE_DATABASE
	export CREATE_DATABASE
	export PRESERVE_DATABASE
}

error() {

    if [ "${FRESH_INSTALL}" = Y ]; then
    	    echo Fresh install failed.. deleting /tmp/aveksa/install, "${AVEKSA_HOME}"/Aveksa_System.cfg and "$USER_HOME"/setDeployEnv.sh as part of cleanup.
    	    rm -rf /tmp/aveksa/install
    	    rm -f "${AVEKSA_HOME}"/Aveksa_System.cfg
    	    rm -f "$USER_HOME"/setDeployEnv.sh
    fi
    echo Step failed!  See $LOG for more information.
    exit 1
}

# Displays the license text file and prompts if it is acceptable
# also determines if the liences has already been accepted and will not prompt again
#
# The results fo this fucntion should be checked before proceeding
# for example the function does not determine how to proceed only
#   license
#    ret=$?
#    if [ $ret -ne 0 ]; then
#        echo User does not agree with the license agreement. Exit installation. >> $LOG
#        exit 1
#    fi

license() {

	if [ $QUIET = Y ]; then
	    return
	fi

	if [ -z "$LICENSE_DONE" ]; then
        	export LICENSE_DONE=N
	fi

	if [[ $LICENSE_DONE = "Y" ]] ; then
#		logToFile "license file already accepted"
		return
	fi

	RETVAL=1
	more ${STAGING_DIR}/deploy/license.txt
	while true
	do
		echo
		if [ -n "$RELEASE_NOTES_LOC" ]; then
		    echo "Details about what is new, changed and fixed can be found in the release notes. Please review the release notes at ${RELEASE_NOTES_LOC} "
            echo
            read -p "Have you reviewed the release notes and agree to the license terms (yes or no)? "
        else
            read -p "Do you agree to the license terms (yes or no)? "
        fi

		case $REPLY in
			y* | Y*)
				RETVAL=0
				export LICENSE_DONE=Y
				break
				;;
			n* | N*)
				echo
				echo "If you do not agree with the license terms, you cannot install this software.";
				echo
				break
				;;
		esac
	done
	return $RETVAL
}


confirmVersion() {
RETVAL=0
if [ $QUIET = N ]; then
	RETVAL=1
	echo
	echo "$PRODUCT_NAME" version=${NEW_IMG_VER} build=${NEW_IMG_BLD}
	while true
	do
		echo
		read -p "Do you wish to install this version of $PRODUCT_NAME (yes or no)? "
		case $REPLY in
			y* | Y*)
				RETVAL=0
				break
				;;
			n* | N*)
				echo
				echo "If this was not the desired version, please obtain the desired version of $PRODUCT_NAME.";
				echo
				break
				;;
		esac
	done
fi
return $RETVAL
}

checkfor6X() {
	RETVAL=0
	if [ -f "${AVEKSA_HOME}"/jboss-4.2.2.GA/server/default/deploy/aveksa.ear/aveksa.war/WEB-INF/classes/aveksa-version.properties ] ; then
		if  grep -q "version=6." "${AVEKSA_HOME}"/jboss-4.2.2.GA/server/default/deploy/aveksa.ear/aveksa.war/WEB-INF/classes/aveksa-version.properties ; then
			echo Existing 6.x install detected >>$LOG
			RETVAL=1
		fi
	fi
	return $RETVAL
}

checkforExistingInstall() {
	RETVAL=0
	# Check for older installation
	checkfor6X
	if [ $? -gt 0 ]; then
		RETVAL=1
	fi

	return $RETVAL
}

isSLES12() {
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        [[ $ID == sles && $VERSION == 12* ]] && return 0
    fi
    return 1
}

isRHEL7() {
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        [[ $ID == rhel && $VERSION == 7* ]] && return 0
    fi
    return 1
}

isRHEL8() {
  if [ -f /etc/os-release ]; then
        source /etc/os-release
        [[ $ID == rhel && $VERSION == 8* ]] && return 0
    fi
    return 1
}
isVapp() {
    [ "$(facter platform_type 2>/dev/null)" = "vApp" ] && return 0
    return 1
}

getNTPServiceName() {
    if isSLES12; then
        echo ntpd
    elif isRHEL7; then
        echo chronyd
    elif isRHEL8; then
        echo chronyd
    else
        echo ntp
    fi
}

checkEnvironmentPreReqs() {
	if [ $REMOTE_ORACLE = N ]; then
		header Checking for NTP Service Status...
		## Check NTP Configuration ############################
		if [ -f /etc/ntp.conf ]; then
			if [ -f /etc/SuSE-release ]; then
				ntpServiceName=$(getNTPServiceName)
				service $ntpServiceName stop
				sntp $(grep ^server /etc/ntp.conf | head -n1 | awk -F" " '{print $2}')
				if [ $? -ne 0 -a "$QUIET" != "Y" ] ; then
					read -p "NTP Service connectivity issue. Please re-enter your NTP Server FQDN or IP Address [ "$(grep ^server /etc/ntp.conf | head -n1 | awk -F" " '{print $2}')" ]  : "
					case $REPLY in
						*)
						sntp $REPLY
						if [ $? -ne 0 ] ; then
							echo "Failing install, NTP server connection issue";exit 1
						fi
						cat > /etc/ntp.conf <<EOF
server ${REPLY}
fudge ${REPLY} stratum 10
driftfile /var/lib/ntp/drift/ntp.drift
logfile /var/log/ntp
keys /etc/ntp.keys
trustedkey 1
requestkey 1
# key (7) for accessing server variables
# controlkey 15                 # key (6) for accessing server variables
EOF
						;;
					esac
				fi
				service $ntpServiceName start
				sleep 15
				service $ntpServiceName status
				if [ $? -ne 0 ] ; then
					echo "Failing install, NTP server connection/sync issue";exit 1
				fi
				chkconfig $ntpServiceName on
			else
				systemctl stop chronyd
				chronyd -q  /etc/chronyd.conf  #Not Sure
				if [ $? -ne 0  -a "$QUIET" != "Y" ] ; then
					read -p "NTP service connectivity issue. Please re-enter your NTP Server FQDN or IP Address [ "$(grep ^server /etc/ntp.conf | head -n1 | awk -F" " '{print $2}')" ]  : "
					case $REPLY in
						*)
						ntpdate $REPLY
						if [ $? -ne 0 ] ; then
							echo "Failing install, NTP server connection issue";exit 1
						fi
						cat > /etc/chronyd.conf <<EOF
server ${REPLY} iburst
restrict default kod nomodify notrap nopeer noquery
restrict -6 default kod nomodify notrap nopeer noquery
restrict 127.0.0.1
restrict -6 ::1
EOF
						;;
					esac
				fi
				systemctl start chronyd
				sleep 15
				systemctl status chronyd
				if [ $? -ne 0 ] ; then
					echo "Failing install, NTP server connection/sync issue";exit 1
				fi
				systemctl enable chronyd
			fi
			echo "Pass ... NTP service is configured and active"
		else
			echo "Pass ... NTP service is not configured and off"
		fi


	fi
}

checkStagingDir() {
	RETVAL=0
	# The invoker of this script does not require the value of JAVA_HOME to be set here. Assigning a value to it here could corrupt the environment variable.
	if [ "$OPT_DBONLY" = "N" ]; then
	    if [ ! -f ${STAGING_DIR}/aveksa.ear ]; then
		    logLine Could not find ${STAGING_DIR}/aveksa.ear
		    RETVAL=1
	    fi
	fi
	if [ ! -d ${STAGING_DIR}/database ]; then
		logLine could not find ${STAGING_DIR}/database
		RETVAL=1
	fi
	if [ ! -d ${STAGING_DIR}/deploy ]; then
		logLine could not find ${STAGING_DIR}/deploy
		RETVAL=1
	fi
	return $RETVAL
}

# check the installations directory if it exists
checkInstallDir() {
	RETVAL=0

	#Remove all leading white spaces in the directory name
	AVEKSA_HOME="$(echo -e "${AVEKSA_HOME}" | sed -e 's/^[[:space:]]*//')"

	#Check if the installation directory starts with '/', if not then append '/home/oracle/' to the directory provided.
	if [[ "$AVEKSA_HOME" != /* ]]; then
	    AVEKSA_HOME="/home/oracle/${AVEKSA_HOME}"
    fi

    #Check if the directory name is permitted
    echo "${AVEKSA_HOME}" | grep "^[a-zA-Z0-9 @_/-]*$" > /dev/null 2>&1
    if [ $? != 0 ]; then
        logLine Invalid directory path. Only alphanumeric,space,-,_ and @ are allowed. Path cannot start with -,_ and @
        RETVAL=1
        return $RETVAL
    fi

    #Remove all the whitespace characters before and after names of directories or sub-directories and also convert multiple delimiters to a single delimiter(Eg: /  IGL  //   Ave ksa   /// -> /IGL/Ave ksa/)
    AVEKSA_HOME=$(echo "$AVEKSA_HOME" | sed 's/\/[ ]*/\//g' | sed 's/[ ]*\//\//g' | sed 's/[ ]*$//g' | sed 's/[\/]\+/\//g')

    #Check if the specified directory or sub directory starts with any special characters
    echo "${AVEKSA_HOME}" | grep "/[@_-]\+" > /dev/null 2>&1
    if [[ $? == 0 ]]; then
            logLine Invalid directory path. Path cannot start with -,_ and @
        RETVAL=1
        return $RETVAL
    fi

    # Check if directory exists
    if [ -d "$AVEKSA_HOME" ]; then
        logLine Installation directory "$AVEKSA_HOME" exists.
        if [ ! -w "$AVEKSA_HOME" -o "$AVEKSA_HOME" = /root ] ; then
            logLine  Unable to write to "$AVEKSA_HOME"
            RETVAL=1
        fi
        if [ -f "$AVEKSA_HOME"/Aveksa_System.cfg -a ! -w "$AVEKSA_HOME"/Aveksa_System.cfg ]; then
	        logLine Unable to write to Aveksa_System.cfg in "${AVEKSA_HOME}".
	        exit 1
        fi
    fi
    return $RETVAL
}

checkOracleDir() {
	RETVAL=0

	#Remove all leading white spaces in the directory name
	ORACLE_BASE="$(echo -e "${ORACLE_BASE}" | sed -e 's/^[[:space:]]*//')"
	#ORACLE_BASE="${ORACLE_BASE##+([[:space:]])}"

	#Check if the directory name is permitted
    echo "${ORACLE_BASE}" | grep "^[a-zA-Z0-9_/-]*$" > /dev/null 2>&1
    if [ $? != 0 ]; then
        logLine Invalid directory path. Only alphanumeric,- and _ are allowed.
        RETVAL=1
        return $RETVAL
    fi

	#Check if the oracle installation directory starts with '/', if not then append '/' to the directory provided.
	if [[ "$ORACLE_BASE" != /* ]]; then
	    logLine Invalid directory path. Path should start with /
        RETVAL=1
        return $RETVAL
    fi

    #Check if the oracle installation directory starts with '/opt/oracle'
	if [[ "$ORACLE_BASE" = / || "$ORACLE_BASE" = /root || "$ORACLE_BASE" = /opt/oracle || "$ORACLE_BASE" = /opt/oracle/* \
	    || "$ORACLE_BASE" == /u01/app/oracle/product/admin ]]; then
	    logLine oracle installation is not allowed in "$ORACLE_BASE"
        RETVAL=1
        return $RETVAL
    fi

    #Check if the specified directory or sub directory starts with any special characters
    echo "${ORACLE_BASE}" | grep "/[@_-]\+" > /dev/null 2>&1
    if [[ $? == 0 ]]; then
            logLine Invalid directory path. Path cannot start with -,_ and @
        RETVAL=1
        return $RETVAL
    fi

    # Check if directory exists
    if [ -d "$ORACLE_BASE" ]; then
        logLine Installation directory "$ORACLE_BASE" exists.
        if [ ! -w "$ORACLE_BASE" ] ; then
            logLine  Unable to write to "$ORACLE_BASE"
            RETVAL=1
        else
            OWNER=`stat -c "%U" "$ORACLE_BASE"`
            GROUP=`stat -c "%G" "$ORACLE_BASE"`
            if [ "$OWNER" != "${AVEKSA_OWNER}" -a "$GROUP" != "${AVEKSA_GROUP}" ] ; then
                logLine oracle installation is not allowed. The owner:group for "$ORACLE_BASE" is not ${AVEKSA_OWNER}:${AVEKSA_GROUP}
                RETVAL=1
            fi
        fi
    fi
    return $RETVAL
}

# Checks the package directory and expected files within
checkPackagesDir() {
	RETVAL=0
	if [ $REMOTE_ORACLE = N ]; then
		if [ ! -f ${PACKAGES_DIR}/${ASMLIB_PACKAGE} -a $CREATE_ASM = Y -a ! -f "${AVEKSA_HOME}"/.${ASMLIB_BASENAME} ]; then
			echo "info: could not find ${PACKAGES_DIR}/${ASMLIB_PACKAGE}; will not install/upgrade Oracle" | tee -a $LOG
		fi
		if [ ! -f ${PACKAGES_DIR}/${ORACLE_PACKAGE1} -a ! -f ${ORACLE_HOME}/${ORACLE_BASENAME} ]; then
			echo "info: could not find ${PACKAGES_DIR}/${ORACLE_PACKAGE1}; will not install/upgrade Oracle" | tee -a $LOG
		fi
		if [ ! -f ${PACKAGES_DIR}/${ORACLE_PACKAGE2} -a ! -f ${ORACLE_HOME}/${ORACLE_BASENAME} ]; then
			echo "info: could not find ${PACKAGES_DIR}/${ORACLE_PACKAGE2}; will not install/upgrade Oracle" | tee -a $LOG
		fi
		if [ ! -f ${PACKAGES_DIR}/${ORACLE_PACKAGE3} -a ! -f ${ORACLE_HOME}/${ORACLE_BASENAME} ]; then
			echo "info: could not find ${PACKAGES_DIR}/${ORACLE_PACKAGE3}; will not install/upgrade Oracle" | tee -a $LOG
		fi
				if [ ! -f ${PACKAGES_DIR}/${ORACLE_PACKAGE4} -a ! -f ${ORACLE_HOME}/${ORACLE_BASENAME} ]; then
			echo "info: could not find ${PACKAGES_DIR}/${ORACLE_PACKAGE4}; will not install/upgrade Oracle" | tee -a $LOG
		fi
	fi
	if [ ! -f ${PACKAGES_DIR}/${JAVA_PACKAGE} ]; then
		echo "info: could not find ${PACKAGES_DIR}/${JAVA_PACKAGE}; will not install/upgrade Java JDK" | tee -a $LOG
	fi
	if [ $APPSERVER = Wildfly ]; then
		if [ ! -f ${PACKAGES_DIR}/${WILDFLY_PACKAGE} ]; then
			echo "info: could not find ${PACKAGES_DIR}/${WILDFLY_PACKAGE}; will not install/upgrade Wildfly" | tee -a $LOG
		fi
	fi
	if [ ! -d ${PACKAGES_DIR} ]; then
		echo "error: could not find directory ${PACKAGES_DIR}" | tee -a $LOG
		RETVAL=1
	fi
	return $RETVAL
}

# Check for oracle packages
checkRequiredOraclePackages () {
	RETVAL=0
	# Verify Packages Directory exists
	if [ ! -d ${PACKAGES_DIR} ]; then
		logLine "error: could not find directory ${PACKAGES_DIR}"
		return 1
	fi
	if [ $REMOTE_ORACLE = N ]; then
		if [ $APPLIANCE = Y -a $CREATE_ASM = Y -a ! -f ${PACKAGES_DIR}/${ASMLIB_PACKAGE} -a ! -f "${AVEKSA_HOME}"/.${ASMLIB_BASENAME} ]; then
			echo "error: could not find ${PACKAGES_DIR}/${ASMLIB_PACKAGE} and Oracle ASM ${ASMLIB_BASENAME} is not already installed"
			RETVAL=1
		fi
		if [ ! -f ${PACKAGES_DIR}/${ORACLE_PACKAGE1} -a ! -f ${ORACLE_HOME}/${ORACLE_BASENAME} ]; then
			echo "error: could not find ${PACKAGES_DIR}/${ORACLE_PACKAGE1} and Oracle ${ORACLE_BASENAME} is not already installed"
			RETVAL=1
		fi
		if [ ! -f ${PACKAGES_DIR}/${ORACLE_PACKAGE2} -a ! -f ${ORACLE_HOME}/${ORACLE_BASENAME} ]; then
			echo "error: could not find ${PACKAGES_DIR}/${ORACLE_PACKAGE2} and Oracle ${ORACLE_BASENAME} is not already installed"
			RETVAL=1
		fi
		if [ ! -f ${PACKAGES_DIR}/${ORACLE_PACKAGE3} -a ! -f ${ORACLE_HOME}/${ORACLE_BASENAME} ]; then
			echo "error: could not find ${PACKAGES_DIR}/${ORACLE_PACKAGE3} and Oracle ${ORACLE_BASENAME} is not already installed"
			RETVAL=1
		fi
		if [ ! -f ${PACKAGES_DIR}/${ORACLE_PACKAGE4} -a ! -f ${ORACLE_HOME}/${ORACLE_BASENAME} ]; then
			echo "error: could not find ${PACKAGES_DIR}/${ORACLE_PACKAGE4} and Oracle ${ORACLE_BASENAME} is not
			already installed"
			RETVAL=1
		fi
	fi
	return $RETVAL
}
# Check for JDK packages
checkRequiredJDKPackages () {
	RETVAL=0
	# Verify Packages Directory exists
	if [ ! -d ${PACKAGES_DIR} ]; then
		logLine "error: could not find directory ${PACKAGES_DIR}"
		return 1
	fi
	# verify JDK files exist
	if [ ! -f ${PACKAGES_DIR}/${JAVA_PACKAGE} -a ! -f ${JAVA_HOME}/bin/java ]; then
		logLIne "error: could not find ${PACKAGES_DIR}/${JAVA_PACKAGE} and Java ${JAVA_BASENAME} is not already installed"
		RETVAL=1
	fi

	return $RETVAL
}
# Check for Wildfly packages
checkRequiredWildflyPackages () {
	RETVAL=0
	# Verify Packages Directory exists
	if [ ! -d ${PACKAGES_DIR} ]; then
		logLine "error: could not find directory ${PACKAGES_DIR}"
		return 1
	fi
	# verify wildfly files exist
	if [ $APPSERVER = Wildfly ]; then
		if [ ! -f "${PACKAGES_DIR}/${WILDFLY_PACKAGE}" -a ! -f "${AVEKSA_WILDFLY_HOME}/../${WILDFLY_BASENAME}/bin/standalone.sh" ]; then
			logLine "error: could not find ${PACKAGES_DIR}/${WILDFLY_PACKAGE} and Wildfly ${WILDFLY_BASENAME} is not already installed"
			RETVAL=1
		fi
	fi
	return $RETVAL
}

# check for all required Packages/install media
checkRequiredPackages() {
	RETVAL=0

	#check Oracle
    if ! checkRequiredOraclePackages; then
	    RETVAL=1
	fi

    # check JDK
    if ! checkRequiredJDKPackages; then
	    RETVAL=1
	fi

    # check Wildfly
    if ! checkRequiredWildflyPackages; then
	    RETVAL=1
	fi

# TBD Is this obsolete?
	if [ $RETVAL -gt 0 ]; then
		ls ${PACKAGES_DIR} | grep -q x64
		GREP_X64=$?
		if [ $IS64BIT = N -a $GREP_X64 -eq 0 ] 2>/dev/null; then
			echo 'info: 64-bit packages were found; are you trying to install 64-bit packages on a 32-bit operating system?'
		fi
		if [ $IS64BIT = Y -a $GREP_X64 -neq 0 ] 2>/dev/null; then
			echo 'info: no 64-bit packages were found; are you trying to install 32-bit packages on a 64-bit operating system?'
		fi
	fi
	return $RETVAL
}

# Check for required files in the staging directory. If all files
# are there, then the variables NEW_IMG_VER and NEW_IMG_BLD will
# be set to the version and build number of the product in the
# staging directory.
#
# Note that the NEW_IMG_BLD can be null even the function returns 0.
#
# Returns 0 if everything checks out, 1 otherwise.
checkForRequiredFiles() {
    RETVAL=0
    if [ ! -f ${STAGING_DIR}/version.txt ]; then
        echo | tee -a $LOG
        echo The version.txt is missing in the staging directory $STAGING_DIR. | tee -a $LOG
        RETVAL=1
    else
        # Let figure out the version to be installed
        NEW_IMG_VER=`cat ${STAGING_DIR}/version.txt | cut -d= -f2`
        if [ -z $NEW_IMG_VER ]; then
            echo The version to be installed cannot be determined from the ${STAGING_DIR}/version.txt. | tee -a $LOG
            RETVAL=1
        else
            export NEW_IMG_VER
        fi
    fi

    if [ ! -f ${STAGING_DIR}/deploy/license.txt ]; then
        echo | tee -a $LOG
        echo The license.txt is missing in the staging directory $STAGING_DIR/deploy. | tee -a $LOG
        RETVAL=1
    fi

    # Still return 0 if the build number is not there. The rest of the installation (as of 7.0.2)
    # does not require the build number. It is only being used for reporting purpose.
    NEW_IMG_BLD=
    if [ -f ${STAGING_DIR}/changesetinfo.txt ]; then
        NEW_IMG_BLD=`cat ${STAGING_DIR}/changesetinfo.txt | cut -d= -f2`
        export NEW_IMG_BLD
    fi

    return $RETVAL
}

isUnsupportedRHEL(){
  source /etc/os-release
	case "$vers" in
		5.*|6.*|7.[0-4] )
			return 0
			break
			;;
		*)
			return 1
			;;
		esac
}

checkLocalOracleAllowed() {
	if [ -f /etc/redhat-release ]; then
		cat /etc/redhat-release > /tmp/install.tmp
		while read line ;do
			for vers in $line
			do
				case "$vers" in
				7.*|8.*)
					isUnsupportedRHEL || localOracleAllowed="yes"
					break
					;;
				*)
					localOracleAllowed="no"
					;;
				esac
			done
		done < /tmp/install.tmp
	elif [ -f /etc/SuSE-release ]; then
		if egrep -q "^VERSION *= *(11|12)" /etc/SuSE-release; then
			localOracleAllowed="yes"
		fi
	fi
	if [ $localOracleAllowed == "yes" ]; then
		echo "Local Oracle install is permitted on this OS version" | tee -a $LOG
	else
		echo "Local Oracle is not supported on this OS version" | tee -a $LOG
		echo "You Must install $PRODUCT_NAME with remote database" | tee -a $LOG
		return 1
		break
	fi
	return 0

}

checkSupportedOS() {
	acmInstallAllowed="no"
	#### Check Architecture, must be 64-bit
	MACHINE_TYPE=`uname -m`
	if [ ${MACHINE_TYPE} != 'x86_64' ]; then
		echo Operating System is unsupported architecture | tee -a $LOG
		RETVAL=1
		break
	fi
	#### Check OS Release Version
	if [ -f /etc/redhat-release ]; then
		cat /etc/redhat-release > /tmp/install.tmp
		while read line ;do
			for vers in $line
			do
				case "$vers" in
				8.*)
					isUnsupportedRHEL || acmInstallAllowed="yes"
					break
					;;
				7.*)
					isUnsupportedRHEL || acmInstallAllowed="yes"
					break
					;;
				6.*)
				    acmInstallAllowed="no"
				    echo "$PRODUCT_NAME is not supported on RHEL 6. Please upgrade to RHEL 7."
				    return 1
				    break
				    ;;
				*)
					acmInstallAllowed="no"
					;;
				esac
			done
		done < /tmp/install.tmp
	elif [ -f /etc/SuSE-release ]; then
		if egrep -q "^VERSION *= *(11|12)" /etc/SuSE-release ; then
            acmInstallAllowed="yes"
		fi
	fi
	if [ $acmInstallAllowed == "no" ]; then
		echo "$PRODUCT_NAME is not supported on this version of linux"
		return 1
		break
	fi
	return 0
}

checkWildflyMemoryReq() {
    # Skip for Vapp; it is pre-set to use 16 GB RAM
    if isVapp; then
        return 0
    fi

     # MEM will be in kb; convert to mb
	 MEM=$(($(grep MemTotal /proc/meminfo|grep -o -E '[0-9]+')/1024))

	 # 2GB for base OS
	 OS_MEM=2048
	 # 3GB to AFX if installed
	 [ -f /etc/init.d/afx_server ] && AFX_MEM=$((3 * 1024)) || AFX_MEM=0
	 # Available memory for application server and database
     APP_MEM=$(($MEM - $OS_MEM - $AFX_MEM ))
     # 65% to Oracle if exists
     [ -d /u01 ] && ORACLE_MEM=$(($APP_MEM * 65 / 100)) || ORACLE_MEM=0
     WILDFLY_MEM=$(($APP_MEM - $ORACLE_MEM ))

     echo "Total Memory:   ${MEM} MB"
     echo "Reserved for OS: ${OS_MEM} MB"
     [ $AFX_MEM -gt 0 ] && echo "Reserved by AFX: ${AFX_MEM} MB"
     [ $ORACLE_MEM -gt 0 ] && echo "Reserved by DB:  ${ORACLE_MEM} MB"
     echo "Available for WildFly:${WILDFLY_MEM} MB"

     if [ "${MEM}" -lt $((7 * 1024)) ]; then
		# <7G configuration
		echo "Cannot start the application!"
		echo "The server's installed RAM is below the minimum requirement of 8 GB"
		echo "Note that $prog requires 3 GB available out of the total memory to install and run."
		return 1
	 fi

     # Need approximately 3GB for RSA IGL; use 2.5GB for calculations
     if [ "${WILDFLY_MEM}" -lt 2560 ]; then
        echo "Cannot start the application!"
        echo "Available memory is less than 3 GB !!!"
		return 1
	 fi
	 return 0
}

checkSupportedASMOS(){
	test -z ${PACKAGES_DIR} && PACKAGES_DIR=/tmp/aveksa/packages
	asmInstallAllowed="no"
	#### Check Architecture, must be 64-bit
	MACHINE_TYPE=`uname -m`
	if [ ${MACHINE_TYPE} != 'x86_64' ]; then
		echo Operating System is unsupported architecture. | tee -a $LOG
		RETVAL=1
		break
	fi
	#### Check OS Release Version
	test -f /etc/redhat-release && tar -jtf ${PACKAGES_DIR}/${ASMLIB_PACKAGE} | grep -q oracleasm-`uname -r`.*.x86_64.rpm && asmInstallAllowed="yes"
	test -f /etc/redhat-release && grep -q 'release 8\.' /etc/redhat-release 2>/dev/null && asmInstallAllowed="yes"
	test -f /etc/redhat-release && grep -q 'release 7\.' /etc/redhat-release 2>/dev/null && asmInstallAllowed="yes"
	test -d /opt/appliancePatches/asmlib/ && temp=`uname -r` && temp2=$(test -d /opt/appliancePatches/asmlib/ && find /opt/appliancePatches/asmlib/ -name oracleasm-${temp}*.x86_64.rpm | wc -l) && if [ $temp2 -gt 0 ] ; then asmInstallAllowed="yes"; fi
	test -f /etc/SuSE-release && egrep -q "^VERSION *= *(11|12)" /etc/SuSE-release && asmInstallAllowed="yes"
	if [ $asmInstallAllowed == "no" ]; then
		return 1
		break
	fi
	return 0
}

checkRH6() {
	if [ -f /etc/redhat-release ]; then
		grep -q "Red Hat Enterprise Linux Server release 6" /etc/redhat-release
		if [ $? -eq 0 ]; then
			return 0
		else
			return 1
		fi
	else
		return 1
	fi
}


checkAveksaUser() {
	if [ $OSTYPE != cygwin ]; then
		if [ `id -u -n` != $AVEKSA_OWNER ]; then
			echo "You must be $AVEKSA_OWNER to run this script."
			exit 1
		fi
	fi
}

summary() {
    echo "Install OS                  $OSVERSION"
    echo "IS64BIT                     $IS64BIT"
    echo "AVEKSA_OWNER                $AVEKSA_OWNER"
    echo "AVEKSA_ADMIN                $AVEKSA_ADMIN"
    echo "AVEKSA_GROUP                $AVEKSA_GROUP"
    echo "AVEKSA_ADMIN_GROUP          $AVEKSA_ADMIN_GROUP"
    echo "DBA_GROUP                   $DBA_GROUP"
    echo "DATA_DIR_GROUP              $DATA_DIR_GROUP"
    echo "AVEKSA_HOME                 $AVEKSA_HOME"
    echo "USR_BIN                     $USR_BIN"
    echo "ORACLE_HOME                 $ORACLE_HOME"
    echo "JAVA_HOME                   $JAVA_HOME"
    echo "AVEKSA_WILDFLY_HOME         $AVEKSA_WILDFLY_HOME"
    echo "AVEKSA_JBOSS4_HOME          $AVEKSA_JBOSS4_HOME"
    echo "AVEKSA_WILDLFY8_HOME        $AVEKSA_WILDLFY8_HOME"
    echo "AVEKSA_HTTP_PORT            $AVEKSA_HTTP_PORT"
    echo "AVEKSA_HTTPS_PORT           $AVEKSA_HTTPS_PORT"
    echo "AVEKSA_HTTP_SERVICE_PORT    $AVEKSA_HTTP_SERVICE_PORT"
    echo "AVEKSA_HTTPS_SERVICE_PORT   $AVEKSA_HTTPS_SERVICE_PORT"
    echo "ASM_SID                     $ASM_SID"
    echo "ORACLE_SID                  $ORACLE_SID"
    echo "ORACLE_SERVICE_NAME         $ORACLE_SERVICE_NAME"
    echo "ORACLE_CONNECTION_ID        $ORACLE_CONNECTION_ID"
    echo "AVEKSA_ORACLE_DB_USER       $AVEKSA_ORACLE_DB_USER"
    echo "STAGING_DIR                 $STAGING_DIR"
    echo "PACKAGES_DIR                $PACKAGES_DIR"
    echo "ASMLIB_BASENAME             $ASMLIB_BASENAME"
    echo "ASMLIB_PACKAGE              $ASMLIB_PACKAGE"
    echo "ORACLE_BASENAME             $ORACLE_BASENAME"
    echo "ORACLE_PACKAGE1             $ORACLE_PACKAGE1"
    echo "ORACLE_PACKAGE2             $ORACLE_PACKAGE2"
    echo "ORACLE_PACKAGE3             $ORACLE_PACKAGE3"
    echo "ORACLE_PACKAGE4             $ORACLE_PACKAGE4"
    echo "JAVA_BASENAME               $JAVA_BASENAME"
    echo "JAVA_PACKAGE                $JAVA_PACKAGE"
    echo "WILDFLY_BASENAME            $WILDFLY_BASENAME"
    echo "WILDFLY_PACKAGE             $WILDFLY_PACKAGE"
    echo "AGENT_HOME                  $AGENT_HOME"
    echo "DEPLOY_DIR                  $DEPLOY_DIR"
    echo "APPLIANCE                   $APPLIANCE"
    echo "AS_AVEKSA_OWNER             $AS_AVEKSA_OWNER"
}



resetOracleVariables() {
	if [ $REMOTE_ORACLE = N ]; then
		REMOTE_ORACLE_IP=
		REMOTE_ORACLE_PORT=
		SQLPATH=
		TNS_ADMIN=
		TWO_TASK=
	else
		ORACLE_HOME=
		ORACLE_BASE=
		ORACLE_GRID_HOME=
		LISTENER_PORT=
		ASM_SID=
		USE_ASM=
		CREATE_ASM=
		USE_FS=
		AVEKSAEXPORTIMPORT_DIR=

		TWO_TASK=${ORACLE_CONNECTION_ID}
	fi
}
setOracle12CHomes() {
	if [ $OSTYPE = cygwin ]; then
		ORACLE_HOME=c:/oracle/product/12.1.0/db_1
		export $ORACLE_HOME
	else
		ORACLE_HOME=/u01/app/oracle/product/12.1.0/db_1
		ORACLE_GRID_HOME=/u01/app/12.1.0/grid
		export ORACLE_HOME
		export ORACLE_GRID_HOME
	fi
}

checkEarDeployed() {
		su - $AVEKSA_OWNER -c "${AVEKSA_WILDFLY_HOME}/bin/jboss-cli.sh --connect '/deployment=aveksa.ear/:read-attribute(name=status)' 2>/dev/null" | grep OK > /dev/null && return 0
		return 1
}

setStagingDir() {
    if [ -d $(cd ..; pwd)/deploy ]; then
	    export STAGING_DIR=$(cd ..; pwd)
    elif [ -d $(cd ../..; pwd)/deploy ]; then
        export STAGING_DIR=$(cd ../..; pwd)
    else
  	    export STAGING_DIR=/tmp/aveksa/staging
    fi
}

checkSupportedOS
if [ $? -gt 0 ]; then
	echo "The existing Operating System version is unsupported or unknown."
	echo "Please install a required operating system before proceeding with this install."
	echo "See the $PRODUCT_NAME Installation guide for more information regarding OS installation."
	exit 1
fi




# Load prior or default settings

setStagingDir

export DEPLOY_DIR=$STAGING_DIR/deploy

if [ -z "$AVEKSA_HOME" -a -f "$DEPLOY_DIR"/Aveksa_System.cfg ]; then
    source $DEPLOY_DIR/Aveksa_System.cfg 2>/dev/null
    export AVEKSA_HOME
fi

# there can be an istance where the JAVA_HOME is not yet set in Aveksa_System.cfg
# the call to setVariables ends up unsetting the value We dont want a null value
JAVA_HOME_ORIG=$JAVA_HOME

if [ -f "$AVEKSA_HOME"/Aveksa_System.cfg ]; then
	setVariables "$AVEKSA_HOME"/Aveksa_System.cfg
elif [ -f "$DEPLOY_DIR"/Aveksa_System.cfg ]; then
	setVariables "$DEPLOY_DIR"/Aveksa_System.cfg
else
    logToFile Could not find Aveksa_System.cfg file
fi

setStagingDir

if [ -z "$JAVA_HOME" ]; then
    JAVA_HOME=$JAVA_HOME_ORIG
fi

# Check for appliance and at supported patch level
APPLIANCE=N
if [ -f /etc/init.d/kickstartpostinstall.sh ]; then
	checkSupportedASMOS
	if [ $? -eq 0 ]; then
		APPLIANCE=Y
	fi

fi


# Command to use instead of su
if [ $OSTYPE = cygwin ]; then
	AS_AVEKSA_OWNER="sh -c"
else
	AS_AVEKSA_OWNER="su - ${AVEKSA_OWNER} -c"
fi


# Set defaults


if [ -z "$PACKAGES_DIR" ]; then
	if [ -f $STAGING_DIR/$WILDFLY_PACKAGE -o -f $STAGING_DIR/$JAVA_PACKAGE -o -f $STAGING_DIR/$ORACLE_PACKAGE ]; then
		PACKAGES_DIR=$STAGING_DIR
	else
		PACKAGES_DIR=/tmp/aveksa/packages
	fi
fi
if [ -z "$AVEKSA_OWNER" ]; then
	if [ $OSTYPE = cygwin ]; then
		AVEKSA_OWNER=$USER
	else
		AVEKSA_OWNER=oracle
	fi
fi
if [ -z "$AVEKSA_GROUP" ]; then
	if [ $OSTYPE = cygwin ]; then
		AVEKSA_GROUP=Users
	else
		AVEKSA_GROUP=oinstall
	fi
fi
if [ -z "$AVEKSA_ADMIN" ]; then
	AVEKSA_ADMIN=admin;
fi
if [ -z "$AVEKSA_ADMIN_GROUP" ]; then
	AVEKSA_ADMIN_GROUP=$AVEKSA_GROUP
fi
if [ -z "$DBA_GROUP" ]; then
		DBA_GROUP=dba
fi
if [ -z "$DATA_DIR_GROUP" ]; then
		DATA_DIR_GROUP=datadir
fi

if [ -z "$REMOTE_ORACLE" ]; then
	REMOTE_ORACLE=N
fi

if [ -z "$OPT_DBONLY" ]; then
	OPT_DBONLY=N
fi

if [ -z "$USR_BIN" ]; then
	USR_BIN=/usr/bin
fi
#see additional oracle 2-tier settings below
if [ -z "$ORACLE_HOME" ]; then
	if [ $OSTYPE = cygwin ]; then
		ORACLE_HOME=c:/oracle/product/12.1.0/db_1
	else
		ORACLE_HOME="$ORACLE_BASE"/product/12.1.0/db_1
	fi
fi
if [ -z "$AFX_HOME" ]; then
		AFX_HOME="$AVEKSA_HOME"/AFX
fi
if [ -z "$AFX_OWNER" ]; then
		AFX_OWNER=$AVEKSA_OWNER
fi
if [ -z "$AFX_GROUP" ]; then
	AFX_GROUP=$AVEKSA_GROUP
fi
if [ -z "$ACTIVEMQ_HOME" ]; then
	ACTIVEMQ_HOME="$AFX_HOME"/activemq
fi
# override value from SuSE 11 oracle package or previous releases
if [ "$ORACLE_HOME" == /opt/oracle/product/12gR1/db \
-o "$ORACLE_HOME" == /opt/oracle/product/11gR2/db \
-o "$ORACLE_HOME" == /opt/oracle/product/11gR1/db \
-o "$ORACLE_HOME" == c:/oracle/product/10.2.0/db_1 \
-o "$ORACLE_HOME" == c:/oracle/product/11.1.0/db_1 \
-o "$ORACLE_HOME" == /u01/app/oracle/product/10.2.0/db_1 \
-o "$ORACLE_HOME" == /u01/app/oracle/product/11.1.0/db_1 \
-o "$ORACLE_HOME" == /u01/app/oracle/product/11.2.0/db_1 \
-o "$ORACLE_HOME" == "$ORACLE_BASE"/product/10.2.0/db_1 \
-o "$ORACLE_HOME" == "$ORACLE_BASE"/product/11.1.0/db_1 \
-o "$ORACLE_HOME" == "$ORACLE_BASE"/product/11.2.0/db_1 ]; then
	if [ $OSTYPE = cygwin ]; then
		ORACLE_HOME=c:/oracle/product/12.1.0/db_1
	else
		ORACLE_HOME=/u01/app/oracle/product/12.1.0/db_1
	fi
fi
if [ -z "$ORACLE_GRID_HOME" -o "$ORACLE_GRID_HOME" == "/u01/app/11.2.0/grid" ]; then
	ORACLE_GRID_HOME=/u01/app/12.1.0/grid
fi
if [ -z "$ORACLE_BASE" ]; then
	ORACLE_BASE=/u01/app/oracle
fi
if [ -z "$LISTENER_PORT" ]; then
	LISTENER_PORT=1555
fi

# If JAVA_HOME is not set, or was removed (e.g. during upgrade), we need
# to inherit the new value that the installer set in /root/setDeployEnv.sh
if [ -z "$JAVA_HOME" -o ! -d "$JAVA_HOME" ]; then
    [ -f /root/setDeployEnv.sh ] && eval $(egrep '^(export )?JAVA_HOME=' /root/setDeployEnv.sh)
fi
export JAVA_HOME=$JAVA_HOME


# JBOSS settings
if [ -z "$AVEKSA_WILDFLY_HOME" ]; then
	AVEKSA_WILDFLY_HOME="$AVEKSA_HOME"/wildfly
fi
if [ -z "$AVEKSA_JBOSS4_HOME" ]; then
	AVEKSA_JBOSS4_HOME="$AVEKSA_HOME"/jboss-4.2.2.GA
fi
if [ -z "$AVEKSA_WILDFLY8_HOME" ]; then
	AVEKSA_WILDFLY8_HOME="$AVEKSA_HOME"/$WILDFLY8_BASENAME
fi

if [ -z "$ASM_SID" ]; then
	ASM_SID=+ASM
fi
if [ -z "$ORACLE_SID" ]; then
	ORACLE_SID=AVDB
fi
# override value from SuSE 11 oracle package
if [ $ORACLE_SID = orcl ]; then
	ORACLE_SID=AVDB
fi
if [ -z "$ORACLE_SERVICE_NAME" ]; then
	ORACLE_SERVICE_NAME=$ORACLE_SID
fi
if [ -z "$ORACLE_CONNECTION_ID" ]; then
	ORACLE_CONNECTION_ID=$ORACLE_SERVICE_NAME
fi
if [ -z "$AVEKSA_ORACLE_DB_USER" ]; then
	AVEKSA_ORACLE_DB_USER=AVUSER
fi
if [ -z "$AVEKSAEXPORTIMPORT_DIR" ]; then
	AVEKSAEXPORTIMPORT_DIR="$AVEKSA_HOME"/AveksaExportImportDir
fi

if [ -z "$USE_ASM" ]; then
	if [ $APPLIANCE = Y -a $REMOTE_ORACLE = N ]; then
		USE_ASM=Y
	else
		USE_ASM=N
	fi
fi
if [ -z "$CREATE_ASM" ]; then
	if [ $APPLIANCE = Y -a $REMOTE_ORACLE = N ]; then
		CREATE_ASM=Y
	else
		CREATE_ASM=N
	fi
fi
if [ -z "$USE_FS" ]; then
	if [ $APPLIANCE = N -a $REMOTE_ORACLE = N ]; then
		USE_FS=Y
	else
		USE_FS=N
	fi
fi
if [ -z "$ASM_PARTITION" ]; then
	if [ $APPLIANCE = Y -a $REMOTE_ORACLE = N ]; then
		ASM_PARTITION=sda3
	fi
fi
if [ -z "$DATA1_FILENAME" ]; then
	if [ $APPLIANCE = Y ]; then
		DATA1_FILENAME=+DG01\(DATAFILE\)
	else
		DATA1_FILENAME=DATA_256K
	fi
fi
if [ -z "$DATA2_FILENAME" ]; then
	if [ $APPLIANCE = Y ]; then
		DATA2_FILENAME=+DG01\(DATAFILE\)
	else
		DATA2_FILENAME=DATA_1M
	fi
fi
if [ -z "$DATA3_FILENAME" ]; then
	if [ $APPLIANCE = Y ]; then
		DATA3_FILENAME=+DG01\(DATAFILE\)
	else
		DATA3_FILENAME=DATA_25M
	fi
fi
if [ -z "$DATA4_FILENAME" ]; then
	if [ $APPLIANCE = Y ]; then
		DATA4_FILENAME=+DG01\(DATAFILE\)
	else
		DATA4_FILENAME=DATA_50M
	fi
fi
if [ -z "$INDX1_FILENAME" ]; then
	if [ $APPLIANCE = Y ]; then
		INDX1_FILENAME=+DG01\(DATAFILE\)
	else
		INDX1_FILENAME=INDX_256K
	fi
fi
if [ -z "$INDX2_FILENAME" ]; then
	if [ $APPLIANCE = Y ]; then
		INDX2_FILENAME=+DG01\(DATAFILE\)
	else
		INDX2_FILENAME=INDX_1M
	fi
fi
if [ -z "$INDX3_FILENAME" ]; then
	if [ $APPLIANCE = Y ]; then
		INDX3_FILENAME=+DG01\(DATAFILE\)
	else
		INDX3_FILENAME=INDX_25M
	fi
fi
if [ -z "$INDX4_FILENAME" ]; then
	if [ $APPLIANCE = Y ]; then
		INDX4_FILENAME=+DG01\(DATAFILE\)
	else
		INDX4_FILENAME=INDX_50M
	fi
fi

#
if [ -z "$AGENT_HOME" ]; then
	AGENT_HOME="$AVEKSA_HOME"/AveksaAgent
fi

if [ -z "$ARCHIVE_DIR" ]; then
	ARCHIVE_DIR="$AVEKSA_HOME"/archive
fi

# Check if this is part of an Oracle RAC install
if [ -z "$OPT_ORACLE_RAC" ]; then
	OPT_ORACLE_RAC=N
fi


# the default keystore directory
if [ -z "$KEYSTORE_DIR" ]; then
	export KEYSTORE_DIR="${AVEKSA_HOME}"/keystore
fi

# Export oracle settings
export ORACLE_HOME
export ORACLE_BASE
export ORACLE_SID
export AVEKSA_ADMIN
export DBA_GROUP
export DATA_DIR_GROUP
export AVEKSA_ADMIN_GROUP

# Remove extra SuSE 12 Oracle package settings
unset ORA_ASM_HOME
unset ORA_CRS_HOME

# implicitly change staging directory
if [ -f $(cd ..; pwd)/deploy/Aveksa_System.cfg ]; then
	NEW_STAGING_DIR=$(cd ..; pwd)
else
	NEW_STAGING_DIR=$(cd ../..; pwd)
fi
if [ -d $NEW_STAGING_DIR/deploy -a -f $NEW_STAGING_DIR/aveksa.ear -a $NEW_STAGING_DIR != $STAGING_DIR -a $NEW_STAGING_DIR != "$AVEKSA_HOME" ]; then
	STAGING_DIR=$NEW_STAGING_DIR
fi

export DEPLOY_DIR=$(cd $(dirname $0) & pwd)

cd $DEPLOY_DIR

# Prereqs
if [ -z "$CONFIGURE" ]; then
    checkStagingDir
    ret=${PIPESTATUS[0]}
    if [ ${ret} -ne 0 ]; then
        echo "Missing file/directory in the staging directory ${STAGING_DIR}. Exit Installation." | tee -a $LOG
		exit 1
	fi
	# if ! checkPackagesDir; then
		# echo Run $DEPLOY_DIR/configure.sh to set a valid packages directory.
		# exit 1
	# fi
fi

backupCacerts() {
	# Backup the cacerts to $AVEKSA_HOME/backupCertPath
    javaPath="/etc/alternatives/${JAVA_BASENAME}"
    if [ ! -d ${javaPath} ]; then
        javaPath="/etc/alternatives/java_sdk_1.8.0"
        if [ ! -d ${javaPath} ]; then
            javaPath="/etc/alternatives/java_sdk_1.7.0"
            if [ ! -d ${javaPath} ]; then
                # Since the backup gets only executed when an existing environment is detected,
                # we can reuse the existing JAVA_HOME that was already configured for the environment.
                javaPath="$JAVA_HOME"
            fi
        fi
    fi

    backupCertPath="$AVEKSA_HOME/backupcacerts"
    if [ -d ${javaPath} ] ; then
        mkdir -p "${backupCertPath}";
    fi

    bkpFile="${backupCertPath}"/cacerts.$(date +"%s")
    cp -f ${javaPath}/jre/lib/security/cacerts "${bkpFile}"
    echo  "The cacerts keystore is backed up into ${backupCertPath} folder. Prior to upgrade if you have any certificates imported, you will have to re-import them from the backup keystore." | tee -a $LOG
}

createArchiveFolder() {
	if [ ! -d "${AVEKSA_HOME}"/archive ]; then
		logToFile "Creating archive folder "${AVEKSA_HOME}"/archive"
	  mkdir "${AVEKSA_HOME}"/archive
	fi
	chmod 770 "${AVEKSA_HOME}"/archive
	chmod -f 660 "${AVEKSA_HOME}"/archive/*
	chown -R ${AVEKSA_OWNER}:${AVEKSA_GROUP} "${AVEKSA_HOME}"/archive
}
