#!/bin/bash 
#
# Collect the configuration information
#checkPackagesDir
# configure.sh [-q]
# -q	quiet; do not ask questions
#

. ./common.sh

QUIET_CONFIGURE="$QUIET"

while [ $1 ]; do
	case $1 in
	-q)
		QUIET_CONFIGURE=Y
		shift
		;;
	-asmpart)
		shift
		if [ -z "$1" ]; then echo ASM partition not specified; exit 1; fi
		OPT_ASMPART=$1
		shift
		;;
	-staging)
        echo The -staging option has been obsoleted and the staging directory will always be /tmp/aveksa/staging; exit 1;
		;;
	-packages)
		shift
		if [ -z "$1" ]; then echo packages directory not specified; exit 1; fi
		OPT_PACKAGES=$1
		shift
		;;
	-vapp)
	    OPT_VAPP=Y
	    shift
	    RESPFILE=${1?Must specify path to configuration file}
	    shift
	    ;;
	*)
		echo Error: unknown option $1
		exit 1
		;;
	esac
done

# Make sure that you are root
#if [ $OSTYPE != cygwin ]; then
#	if [ `id -u` != "0" ]; then
#		echo "You must be root to run this script."
#		exit 1
#	fi
#fi

# Check for the template configuration file
if [ ! -f Aveksa_System.cfg ]; then
	echo Could not find Aveksa_System.cfg in the current directory, $(pwd). | tee -a $LOG
	exit 1
fi

# Load prior settings and set defaults
export CONFIGURE=Y

# These are the options provided explicitly with install.sh
if [ -n "$OPT_ASMPART" ]; then
	export ASM_PARTITION=$OPT_ASMPART
	if [ -f "$DEPLOY_DIR"/Aveksa_System.cfg ]; then
	    sed -i "s^ASM_PARTITION=.*^ASM_PARTITION=$ASM_PARTITION^" Aveksa_System.cfg
    fi
fi
if [ -z "$STAGING_DIR" ]; then
    export STAGING_DIR=/tmp/aveksa/staging
fi
if [ -n "$OPT_PACKAGES" ]; then
	export PACKAGES_DIR=$OPT_PACKAGES
	if [ -f "$DEPLOY_DIR"/Aveksa_System.cfg ]; then
	    sed -i "s^PACKAGES_DIR=.*^PACKAGES_DIR=$PACKAGES_DIR^" Aveksa_System.cfg
    fi
fi

checkStagingDir
ret=${PIPESTATUS[0]}
if [ ${ret} -ne 0 ]; then
    echo "Missing file/directory in the staging directory ${STAGING_DIR}. Exit Installation." | tee -a $LOG
    exit 1
fi

remoteOracleVapp() {
	source $RESPFILE
}

remoteOraclePrompts() {
    echo
    CFG_QUESTION="What is the Oracle listener hostname [$REMOTE_ORACLE_IP]? "
    echo -n "$CFG_QUESTION" >> $LOG
    read -p "$CFG_QUESTION"
    echo $REPLY >> $LOG
    if [ $REPLY ]; then
        REMOTE_ORACLE_IP=$REPLY
    fi

    echo
    CFG_QUESTION="What is the Oracle listener port number [$REMOTE_ORACLE_PORT]? "
    echo -n "$CFG_QUESTION" >> $LOG
    read -p "$CFG_QUESTION"
    echo $REPLY >> $LOG
    if [ $REPLY ]; then
        REMOTE_ORACLE_PORT=$REPLY
    fi

    echo
    CFG_QUESTION="What is the Oracle SID [$ORACLE_SID]? "
    echo -n "$CFG_QUESTION" >> $LOG
    read -p "$CFG_QUESTION"
    echo $REPLY >> $LOG
    if [ $REPLY ]; then
        ORACLE_SID=$REPLY
        ORACLE_SERVICE_NAME=$REPLY
        ORACLE_CONNECTION_ID=$REPLY
    fi
    echo
    CFG_QUESTION="Is the Oracle Service name the same as the Oracle SID [$ORACLE_SID]? (yes/no) "
    echo -n "$CFG_QUESTION" >> $LOG
    read -p "$CFG_QUESTION"
    echo $REPLY >> $LOG
    case $REPLY in
        y* | Y*)
#			no-op do nothing
        ;;
        n* | N*)
            CFG_QUESTION="What is the Oracle Service Name [$ORACLE_SID]? "
            echo -n "$CFG_QUESTION" >> $LOG
            read -p "$CFG_QUESTION"
            echo $REPLY >> $LOG
            if [ $REPLY ]; then
                ORACLE_SERVICE_NAME=$REPLY
                ORACLE_CONNECTION_ID=$REPLY

            fi
        ;;
    esac

    echo
    read -p "What is the AVUSER username [$AVEKSA_USER]? "
    if [ $REPLY ]; then
        AVEKSA_USER=$REPLY
    fi

    echo
    read -p "What is the AVUSER password [$AVEKSA_PASS]? "
    if [ $REPLY ]; then
        AVEKSA_PASS=$REPLY
    fi

    echo
    read -p "What is the AVDWUSER username [$AVEKSA_REPORTS_USER]? "
    if [ $REPLY ]; then
        AVEKSA_REPORTS_USER=$REPLY
    fi

    echo
    read -p "What is the AVDWUSER password [$AVEKSA_REPORTS_PASS]? "
    if [ $REPLY ]; then
        AVEKSA_REPORTS_PASS=$REPLY
    fi

    echo
    read -p "What is the ACMDB username [$AVEKSA_PUBLIC_DB_USER]? "
    if [ $REPLY ]; then
        AVEKSA_PUBLIC_DB_USER=$REPLY
    fi

    echo
    read -p "What is the ACMDB password [$AVEKSA_PUBLIC_DB_PASS]? "
    if [ $REPLY ]; then
        AVEKSA_PUBLIC_DB_PASS=$REPLY
    fi

    echo
    read -p "What is the PERFSTAT username [$AVEKSA_AVPERF_USER]? "
    if [ $REPLY ]; then
        AVEKSA_AVPERF_USER=$REPLY
    fi

    echo
    read -p "What is the PERFSTAT password [$AVEKSA_AVPERF_PASS]? "
    if [ $REPLY ]; then
        AVEKSA_AVPERF_PASS=$REPLY
    fi
}

localOraclePrompt(){
if [ "$REMOTE_ORACLE" = N -a ! -f /etc/oratab ]; then
	    while true; do
		    echo
		    read -p "What is the location for Oracle installation [$ORACLE_BASE]? "
		    if [ "$REPLY" ]; then
			    ORACLE_BASE="$REPLY"
		    fi

		    if checkOracleDir; then
			        break;
		    else
	            . ./common.sh
		    fi
	    done
	fi

}

locationPrompts(){

. ./common.sh

if [ -d "$AVEKSA_WILDFLY_HOME" ]; then
    logLine -e "\e[5mNote - Installation directory "${AVEKSA_HOME}" contains an existing installation of wildfly. \e[25m"
    if [ ! -w "$AVEKSA_HOME"/Aveksa_System.cfg ]; then
	        logLine Unable to write to Aveksa_System.cfg in "${AVEKSA_HOME}".
	        exit 1
    fi
fi

# Figure out if this is a new install or not
test -d "$AVEKSA_WILDFLY_HOME" && FRESH_INSTALL=N || FRESH_INSTALL=Y

if [ "$QUIET_CONFIGURE" = N -a "$FRESH_INSTALL" = Y ]; then
    while true; do
		echo
		read -p "What is the location for installation [$AVEKSA_HOME]? "
		if [ "$REPLY" ]; then
			AVEKSA_HOME="$REPLY"
		fi

		if checkInstallDir; then
			break;
	    else
	        . ./common.sh
		fi
	  done
fi

if [ "$OPT_VAPP" = "Y" ]; then
    REMOTE_ORACLE=Y
    remoteOracleVapp
elif [ "$QUIET_CONFIGURE" = N ]; then
	while true; do
		echo
		read -p "Where are the package files located [$PACKAGES_DIR]? "
		if [ $REPLY ]; then
			PACKAGES_DIR=$REPLY
		fi
		
		if checkPackagesDir; then
			break;
		fi
	done

    if [ "$FRESH_INSTALL" = Y ]; then
	    checkLocalOracleAllowed
	    if [ $? -eq 1 ]; then
		    echo This OS version only supports a remote Oracle installation | tee -a $LOG
		    REMOTE_ORACLE=Y
	    else
		    echo
		    echo "Database configurations:" >> $LOG
		    CFG_QUESTION="Use a remote Oracle server installation [$REMOTE_ORACLE]? "
		    echo -n "$CFG_QUESTION" >> $LOG
		    read -p "$CFG_QUESTION"
		    echo $REPLY >> $LOG
		    case $REPLY in
			    y* | Y*)
			    REMOTE_ORACLE=Y
			    ;;
			    n* | N*)
			    REMOTE_ORACLE=N
			    ;;
		    esac

	    fi
	    if [ $REMOTE_ORACLE = Y ]; then
		    remoteOraclePrompts
	    fi

	    if [ $APPLIANCE = Y -a $REMOTE_ORACLE = N ]; then
		    echo
		    echo "ASM partition (sda3 or sdb1) depends on the hardware. Consult documentation for more information."
		    CFG_QUESTION="What is the Oracle ASM partition [$ASM_PARTITION]? "
		    echo -n "$CFG_QUESTION" >> $LOG
		    while true; do
			    read -p "$CFG_QUESTION"
			    if [ $REPLY ] ; then
				    ASM_PARTITION=$REPLY
			    fi
			    if [ ! -b /dev/$ASM_PARTITION -o $(fdisk -l 2>/dev/null | grep -q "Disk /dev/$ASM_PARTITION" ; echo $?) -eq 0 ]; then
				    echo /dev/$ASM_PARTITION is not a valid partition
			    else
				    grep -q "/dev/${ASM_PARTITION} " /etc/fstab
				    if [ $? -eq 0 ]; then
					    echo "This partition was found to be in use already (see /etc/fstab)."
				    else
					    pvdisplay -C >> /dev/null 2>&1
					    if [ $? -eq 0 ]; then
						    pvdisplay -C| grep -q "/dev/${ASM_PARTITION} "
						    if [ $? -eq 0 ]; then
							    echo "This partition was found to be in used by a logical volume group."
						    else
							    break
						    fi
					    else
						    # need to handle the pvdisplay command failure for non root users.
						    break
					    fi
				    fi
			    fi
		    done
		    echo $ASM_PARTITION >> $LOG
		    if [ -f "$DEPLOY_DIR"/Aveksa_System.cfg ]; then
				sed -i "s^ASM_PARTITION=.*^ASM_PARTITION=$ASM_PARTITION^" Aveksa_System.cfg
		    fi
	    fi
	fi
	localOraclePrompt
fi

#reset oracle vars based on user input
resetOracleVariables
}

COMPLETE_CONFIGURE=N

if [ "$INSTALL_DATABASE_ONLY" = Y ]; then
    if [ "$QUIET_CONFIGURE" = N ]; then
        localOraclePrompt
        while true
	    do
	    # look to confirm the configuration loop until good
	    confirmConfiguration
	    if [ $? -gt 0 ]; then
	        if [ ! -f /etc/oratab ]; then
		        if [ -f "$DEPLOY_DIR"/Aveksa_System.cfg ]; then
				    sed -i "s^ORACLE_BASE=.*^ORACLE_BASE=/u01/app/oracle^" Aveksa_System.cfg
		        fi
		        if [ -f "$AVEKSA_HOME"/Aveksa_System.cfg ]; then
		            sed -i "s^ORACLE_BASE=.*^ORACLE_BASE=/u01/app/oracle^" "$AVEKSA_HOME"/Aveksa_System.cfg
		        fi
		    fi
	    else
	        if [ -n "$ORACLE_BASE" -a "$REMOTE_ORACLE" = N -a ! -d "$ORACLE_BASE" -a "$ORACLE_BASE" != "/u01/app/oracle" ]; then
			    mkdir -p "$ORACLE_BASE" > /dev/null 2>&1
			    if [ $? -ne 0 ]; then
				    logLine Unable to create the install directory : "$ORACLE_BASE". Please check permissions.
				    if [ -f "$DEPLOY_DIR"/Aveksa_System.cfg ]; then
					    sed -i "s^ORACLE_BASE=.*^ORACLE_BASE=/u01/app/oracle^" Aveksa_System.cfg
				    fi
			    else
			        chown -R "${AVEKSA_OWNER}:${AVEKSA_GROUP}" "$ORACLE_BASE"
				    chmod 775 "$ORACLE_BASE"
				    COMPLETE_CONFIGURE=Y
				    break;
			    fi
		    else
			    COMPLETE_CONFIGURE=Y
			    break;
		    fi
		fi
		. ./common.sh
	    localOraclePrompt
	    done
	fi

	# Update ORACLE_BASE in Aveksa_System.cfg under /tmp/aveksa/staging/deploy
    if [ -f $DEPLOY_DIR/Aveksa_System.cfg ]; then
        sed -i "s^ORACLE_BASE=.*^ORACLE_BASE=$ORACLE_BASE^;\
        s^ORACLE_HOME=.*^ORACLE_HOME=$ORACLE_BASE/product/12.1.0/db_1^;" Aveksa_System.cfg
        sed -i "s^ORACLE_BASE=.*^ORACLE_BASE=$ORACLE_BASE^;\
        s^ORACLE_HOME=.*^ORACLE_HOME=$ORACLE_BASE/product/12.1.0/db_1^;" db.rsp >/tmp/db.rsp
        sed -i "s^ORACLE_BASE=.*^ORACLE_BASE=$ORACLE_BASE^;" grid.rsp >/tmp/grid.rsp
    fi
else
    locationPrompts
    if [ "$QUIET_CONFIGURE" = N ]; then
	    while true
	    do
	    # look to confirm the configuration loop until good
	    confirmConfiguration
	    if [ $? -gt 0 ]; then
		    # Express need to reconfigure
		    if [ "$FRESH_INSTALL" = Y ]; then
		        if [ -d "$AVEKSA_HOME" ]; then
		            rm -rf "$AVEKSA_HOME"/Aveksa_System.cfg "$AVEKSA_HOME"/Aveksa_System.cfg.shutdown > /dev/null 2>&1
			        count=`ls "$AVEKSA_HOME" |wc -l`
			        if [ $count -eq 0 ]; then
			            rmdir "$AVEKSA_HOME"
			        fi
			    fi
			    if [ -f "$DEPLOY_DIR"/Aveksa_System.cfg ]; then
				    sed -i "s^AVEKSA_HOME=.*^AVEKSA_HOME=/home/oracle^" Aveksa_System.cfg
			    fi
		    fi
		    if [ ! -f /etc/oratab ]; then
		        if [ -f "$DEPLOY_DIR"/Aveksa_System.cfg ]; then
				    sed -i "s^ORACLE_BASE=.*^ORACLE_BASE=/u01/app/oracle^" Aveksa_System.cfg
		        fi
		        if [ "$FRESH_INSTALL" = N -a -f "$AVEKSA_HOME"/Aveksa_System.cfg ]; then
		            sed -i "s^ORACLE_BASE=.*^ORACLE_BASE=/u01/app/oracle^" "$AVEKSA_HOME"/Aveksa_System.cfg
		        fi
		    fi
	    else
		    if [ ! -d "$AVEKSA_HOME" ]; then
			    mkdir -p "$AVEKSA_HOME" > /dev/null 2>&1
			    if [ $? -ne 0 ]; then
				    logLine Unable to create the install directory : "$AVEKSA_HOME". Please check permissions.
				    if [ -f "$DEPLOY_DIR"/Aveksa_System.cfg ]; then
					    sed -i "s^AVEKSA_HOME=.*^AVEKSA_HOME=/home/oracle^" Aveksa_System.cfg
				    fi
				    locationPrompts
			    else
				    COMPLETE_CONFIGURE=Y
			    fi
		    fi
		    if [ -n "$ORACLE_BASE" -a $REMOTE_ORACLE = N -a ! -d "$ORACLE_BASE" -a "$ORACLE_BASE" != "/u01/app/oracle" ]; then
			    mkdir -p "$ORACLE_BASE" > /dev/null 2>&1
			    if [ $? -ne 0 ]; then
				    logLine Unable to create the install directory : "$ORACLE_BASE". Please check permissions.
				    if [ -f "$DEPLOY_DIR"/Aveksa_System.cfg ]; then
					    sed -i "s^ORACLE_BASE=.*^ORACLE_BASE=/u01/app/oracle^" Aveksa_System.cfg
				    fi
			    else
			        chown -R "${AVEKSA_OWNER}:${AVEKSA_GROUP}" "$ORACLE_BASE"
				    chmod 775 "$ORACLE_BASE"
				    COMPLETE_CONFIGURE=Y
				    break;
			    fi
		    else
			    COMPLETE_CONFIGURE=Y
			    break;
		    fi
	    fi
	    locationPrompts
	    done
    else
        # Create the AVEKSA_HOME if it does not exist even during a quiet install
        if [ ! -d "${AVEKSA_HOME}" ]; then
	        mkdir -p "${AVEKSA_HOME}"
        fi
    fi

    # Update AVEKSA_HOME in Aveksa_System.cfg under /tmp/aveksa/staging/deploy
    if [ -f $DEPLOY_DIR/Aveksa_System.cfg ]; then
        sed -i "s^AVEKSA_HOME=.*^AVEKSA_HOME=$AVEKSA_HOME^;\
        s^ORACLE_BASE=.*^ORACLE_BASE=$ORACLE_BASE^;\
        s^ORACLE_HOME=.*^ORACLE_HOME=$ORACLE_BASE/product/12.1.0/db_1^;" Aveksa_System.cfg
        sed -i "s^ORACLE_BASE=.*^ORACLE_BASE=$ORACLE_BASE^;\
        s^ORACLE_HOME=.*^ORACLE_HOME=$ORACLE_BASE/product/12.1.0/db_1^;" db.rsp >/tmp/db.rsp
        sed -i "s^ORACLE_BASE=.*^ORACLE_BASE=$ORACLE_BASE^;" grid.rsp >/tmp/grid.rsp
    fi
fi

if [ "$COMPLETE_CONFIGURE" = Y ]; then
    logLine "Install configuration setup complete. " `date`
fi

# these are relative paths 
AVEKSA_WILDFLY_HOME="$AVEKSA_HOME"/wildfly
AGENT_HOME="$AVEKSA_HOME"/AveksaAgent
ARCHIVE_DIR="$AVEKSA_HOME"/archive
AVEKSAEXPORTIMPORT_DIR="$AVEKSA_HOME"/AveksaExportImportDir
ORACLE_HOME="$ORACLE_BASE"/product/12.1.0/db_1

# Update the settings
sed -e "s^STAGING_DIR=.*^STAGING_DIR=$STAGING_DIR^;\
s^PACKAGES_DIR=.*^PACKAGES_DIR=$PACKAGES_DIR^;\
s^AVEKSA_OWNER=.*^AVEKSA_OWNER=$AVEKSA_OWNER^;\
s^AVEKSA_GROUP=.*^AVEKSA_GROUP=$AVEKSA_GROUP^;\
s^AVEKSA_ADMIN=.*^AVEKSA_ADMIN=$AVEKSA_ADMIN^;\
s^AVEKSA_ADMIN_GROUP=.*^AVEKSA_ADMIN_GROUP=$AVEKSA_ADMIN_GROUP^;\
s^REMOTE_ORACLE=.*^REMOTE_ORACLE=$REMOTE_ORACLE^;\
s^REMOTE_ORACLE_IP=.*^REMOTE_ORACLE_IP=$REMOTE_ORACLE_IP^;\
s^REMOTE_ORACLE_PORT=.*^REMOTE_ORACLE_PORT=$REMOTE_ORACLE_PORT^;\
s^ORACLE_HOME=.*^ORACLE_HOME=$ORACLE_HOME^;\
s^ORACLE_SID=.*^ORACLE_SID=$ORACLE_SID^;\
s^ORACLE_SERVICE_NAME=.*^ORACLE_SERVICE_NAME=$ORACLE_SERVICE_NAME^;\
s^ORACLE_CONNECTION_ID=.*^ORACLE_CONNECTION_ID=$ORACLE_CONNECTION_ID^;\
s^AVEKSA_PASS=.*^AVEKSA_PASS=$AVEKSA_PASS^;\
s^AVEKSA_REPORTS_PASS=.*^AVEKSA_REPORTS_PASS=$AVEKSA_REPORTS_PASS^;\
s^AVEKSA_PUBLIC_DB_PASS=.*^AVEKSA_PUBLIC_DB_PASS=$AVEKSA_PUBLIC_DB_PASS^;\
s^AVEKSA_AVPERF_PASS=.*^AVEKSA_AVPERF_PASS=$AVEKSA_AVPERF_PASS^;\
s^AVEKSA_USER=.*^AVEKSA_USER=$AVEKSA_USER^;\
s^AVEKSA_REPORTS_USER=.*^AVEKSA_REPORTS_USER=$AVEKSA_REPORTS_USER^;\
s^AVEKSA_PUBLIC_DB_USER=.*^AVEKSA_PUBLIC_DB_USER=$AVEKSA_PUBLIC_DB_USER^;\
s^AVEKSA_AVPERF_USER=.*^AVEKSA_AVPERF_USER=$AVEKSA_AVPERF_USER^;\
s^REMOTE_ORACLE=.*^REMOTE_ORACLE=$REMOTE_ORACLE^;\
s^REMOTE_ORACLE_IP=.*^REMOTE_ORACLE_IP=$REMOTE_ORACLE_IP^;\
s^REMOTE_ORACLE_PORT=.*^REMOTE_ORACLE_PORT=$REMOTE_ORACLE_PORT^;\
s^REMOTE_ORACLE_JDBC_URL=.*^REMOTE_ORACLE_JDBC_URL=$REMOTE_ORACLE_JDBC_URL^;\
s^ORACLE_CLIENT_HOME=.*^ORACLE_CLIENT_HOME=$ORACLE_CLIENT_HOME^;\
s^TWO_TASK=.*^TWO_TASK=$TWO_TASK^;\
s^SQLPATH=.*^SQLPATH=$SQLPATH^;\
s^TNS_ADMIN=.*^TNS_ADMIN=$TNS_ADMIN^;\
s^ORACLE_BASE=.*^ORACLE_BASE=$ORACLE_BASE^;\
s^ORACLE_GRID_HOME=.*^ORACLE_GRID_HOME=$ORACLE_GRID_HOME^;\
s^LISTENER_PORT=.*^LISTENER_PORT=$LISTENER_PORT^;\
s^AVEKSA_HOME=.*^AVEKSA_HOME=$AVEKSA_HOME^;\
s^USE_ASM=.*^USE_ASM=$USE_ASM^;\
s^CREATE_ASM=.*^CREATE_ASM=$CREATE_ASM^;\
s^ASM_PARTITION=.*^ASM_PARTITION=$ASM_PARTITION^;\
s^USE_FS=.*^USE_FS=$USE_FS^;\
s^DATA1_TABLESPACE=.*^DATA1_TABLESPACE=$DATA1_TABLESPACE^;\
s^DATA2_TABLESPACE=.*^DATA2_TABLESPACE=$DATA2_TABLESPACE^;\
s^DATA3_TABLESPACE=.*^DATA3_TABLESPACE=$DATA3_TABLESPACE^;\
s^DATA4_TABLESPACE=.*^DATA4_TABLESPACE=$DATA4_TABLESPACE^;\
s^INDX1_TABLESPACE=.*^INDX1_TABLESPACE=$INDX1_TABLESPACE^;\
s^INDX2_TABLESPACE=.*^INDX2_TABLESPACE=$INDX2_TABLESPACE^;\
s^INDX3_TABLESPACE=.*^INDX3_TABLESPACE=$INDX3_TABLESPACE^;\
s^INDX4_TABLESPACE=.*^INDX4_TABLESPACE=$INDX4_TABLESPACE^;\
s^DEFAULT_TABLESPACE=.*^DEFAULT_TABLESPACE=$DEFAULT_TABLESPACE^;\
s^TEMP_TABLESPACE=.*^TEMP_TABLESPACE=$TEMP_TABLESPACE^;\
s^DATA1_FILENAME=.*^DATA1_FILENAME=$DATA1_FILENAME^;\
s^DATA2_FILENAME=.*^DATA2_FILENAME=$DATA2_FILENAME^;\
s^DATA3_FILENAME=.*^DATA3_FILENAME=$DATA3_FILENAME^;\
s^DATA4_FILENAME=.*^DATA4_FILENAME=$DATA4_FILENAME^;\
s^INDX1_FILENAME=.*^INDX1_FILENAME=$INDX1_FILENAME^;\
s^INDX2_FILENAME=.*^INDX2_FILENAME=$INDX2_FILENAME^;\
s^INDX3_FILENAME=.*^INDX3_FILENAME=$INDX3_FILENAME^;\
s^INDX4_FILENAME=.*^INDX4_FILENAME=$INDX4_FILENAME^;\
s^AVEKSAEXPORTIMPORT_DIR=.*^AVEKSAEXPORTIMPORT_DIR=$AVEKSAEXPORTIMPORT_DIR^;\
s^AVEKSA_WILDFLY_HOME=.*^AVEKSA_WILDFLY_HOME=$AVEKSA_WILDFLY_HOME^;\
s^JAVA_HOME=.*^JAVA_HOME=$JAVA_HOME^;\
s^SYS_USER=.*^SYS_USER=$SYS_USER^;\
s^SYS_PASS=.*^SYS_PASS=$SYS_PASS^;\
s^AVEKSA_AVPERF_USER=.*^AVEKSA_AVPERF_USER=$AVEKSA_AVPERF_USER^;\
s^AVEKSA_AVPERF_PASS=.*^AVEKSA_AVPERF_PASS=$AVEKSA_AVPERF_PASS^;\
s^AGENT_HOME=.*^AGENT_HOME=$AGENT_HOME^;\
s^ARCHIVE_DIR=.*^ARCHIVE_DIR=$ARCHIVE_DIR^;" $DEPLOY_DIR/Aveksa_System.cfg >"$AVEKSA_HOME"/Aveksa_System.cfg

chmod 777 "$AVEKSA_HOME"/Aveksa_System.cfg

header Updating configuration information in  "$AVEKSA_HOME"/Aveksa_System.cfg
