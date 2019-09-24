#!/bin/bash
#
# Common_root  include script for RSA G&L  deployment scripts.
# Reference using ". ./common_root.sh"
#
# Description
# This script contains functions requiring or testing elevated priviges
# Typically root type privledges.
# This may also include being able to read root based files.

if [ -f "./common.sh" ]; then
	. ./common.sh
else
	if [ -f "../common.sh" ]; then
		. ../common.sh
	else
		echo "common.sh not found"
		exit 1
	fi
fi

isVapp() {
    [ "$(facter platform_type 2>/dev/null)" = "vApp" ] && return 0
    return 1
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
				ntpdate $(grep ^server /etc/chronyd.conf | head -n1 | awk -F" " '{print $2}')
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

# Update the ownership of staging directory, mostly required when the users are created later during installation or at the time of upgrade
updateStagingOwnership() {
        logLine "Updating staging ownership to $AVEKSA_OWNER:$AVEKSA_GROUP"
        chown -R "$AVEKSA_OWNER":"$AVEKSA_GROUP" "$STAGING_DIR" 2>&1 | tee -a $LOG
        return ${PIPESTATUS[0]}
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


checkRoot() {
	if [ $OSTYPE != cygwin ]; then
		if [ `id -u` != "0" ]; then
			logLine "You must be root to run this script."
			logLine "Please re-run script as root user. "
			exit 1
		fi
	fi
}


shutdownSoftware() {
	if [ -x /etc/init.d/aveksa_server ]; then
		echo "Stopping aveksa server services"
		if [ -d /etc/systemd/system ]; then
			# Need to gracefuly shutdown the service if under systemd:
			service aveksa_server stop >> $LOG
		else
			/etc/init.d/aveksa_server stop >> $LOG
		fi
		if [ "$REMOTE_ORACLE" = N ]; then
			/etc/init.d/aveksa_server stoporacle >> $LOG
		fi
	elif [ -x  /etc/init.d/aveksa_cluster ]; then
		echo "Stopping cluster services"
		if [ -d /etc/systemd/system ]; then
			# Need to gracefuly shutdown the service if under systemd:
			service aveksa_cluster stop >> $LOG
		else
			/etc/init.d/aveksa_cluster stop >> $LOG
		fi
	fi
	if [ -x /etc/init.d/aveksa_watchdog ]; then
		if [ -d /etc/systemd/system ]; then
			# Need to gracefuly shutdown the service if under systemd:
			service aveksa_watchdog stop >> $LOG
		else
			/etc/init.d/aveksa_watchdog stop >> $LOG
		fi
	fi
	if [ -x /etc/init.d/dbem ]; then
		/etc/init.d/dbem stop >> $LOG
	fi
	if [ -x /etc/init.d/dbora -a $REMOTE_ORACLE = N ]; then
		/etc/init.d/dbora stop >> $LOG

		pgrep -f ora_pmon >/dev/null
		if [ $? -eq 0 ]; then
			su - $AVEKSA_OWNER -c "'$AVEKSA_HOME'/database/cliAveksa.sh -abort" >> $LOG
		fi
		pgrep -f ora_pmon >/dev/null

		if [ $? -eq 0 ]; then
			pkill -9 -f ora_pmon
			echo "killed process of ora_pmon"
		fi

		pgrep -f tnslsnr >/dev/null
		if [ $? -eq 0 ]; then
			$AS_AVEKSA_OWNER "lsnrctl stop" >> $LOG
		fi
		pgrep -f tnslsnr >/dev/null
		if [ $? -eq 0 ]; then
			pkill -9 -f tnslsnr
			echo "killed process of tnslsnr"
		fi

		pgrep -f ocssd.bin >/dev/null
		if [ $? -eq 0 ]; then
			/etc/init.d/init.ocssd stop >> $LOG
		fi
		pgrep -f ocssd.bin >/dev/null
		if [ $? -eq 0 ]; then
			pkill -9 -f ocssd.bin
			echo "killed process of ocssd.bin"
		fi
	fi
}
shutdownSoftwareNoOracle() {
	if [ -x /etc/init.d/aveksa_server ]; then
		echo "Stopping avesksa server services"
		if [ -d /etc/systemd/system ]; then
			# Need to gracefuly shutdown the service if under systemd:
			service aveksa_server stop >> $LOG
		else
			/etc/init.d/aveksa_server stop >> $LOG
		fi
	elif [ -x  /etc/init.d/aveksa_cluster ]; then
		echo "Stopping cluster services"
		if [ -d /etc/systemd/system ]; then
			# Need to gracefuly shutdown the service if under systemd:
			service aveksa_cluster stop >> $LOG
		else
			/etc/init.d/aveksa_cluster stop >> $LOG
		fi
	fi
	if [ -x /etc/init.d/aveksa_watchdog ]; then
			if [ -d /etc/systemd/system ]; then
			# Need to gracefuly shutdown the service if under systemd:
			service aveksa_watchdog stop >> $LOG
		else
			/etc/init.d/aveksa_watchdog stop >> $LOG
		fi
fi
	if [ -x /etc/init.d/dbem ] && [ -d ${ORACLE_GRID_HOME} ]; then
		/etc/init.d/dbem stop >> $LOG
	fi
	if [ -x /etc/init.d/dbora -a $REMOTE_ORACLE = N ] && [ -d ${ORACLE_GRID_HOME} ]; then
		/etc/init.d/dbora stop >> $LOG
	fi

	pgrep -f ora_pmon >/dev/null
	if [ $? -eq 0 ] && [ -d ${ORACLE_GRID_HOME} ]; then
		su - $AVEKSA_OWNER -c "'$AVEKSA_HOME'/database/cliAveksa.sh -abort" >> $LOG
	fi

	pgrep -f ora_pmon >/dev/null
	if [ $? -eq 0 ]; then
		pkill -9 -f ora_pmon
	    echo "killed process of ora_pmon"
	fi

	pgrep -f tnslsnr >/dev/null
	if [ $? -eq 0 ] && [ -d ${ORACLE_GRID_HOME} ]; then
		$AS_AVEKSA_OWNER "lsnrctl stop" >> $LOG
	fi
	pgrep -f tnslsnr >/dev/null
	if [ $? -eq 0 ]; then
	    pkill -9 -f tnslsnr
	    echo "killed process of tnslsnr"
	fi

	pgrep -f ocssd.bin >/dev/null
	if [ $? -eq 0 ] && [ -d ${ORACLE_GRID_HOME} ]; then
		/etc/init.d/init.ocssd stop >> $LOG
	fi

	pgrep -f ocssd.bin >/dev/null
	if [ $? -eq 0 ]; then
	    pkill -9 -f ocssd.bin
	    echo "killed process of ocssd.bin"
	fi
}



# Check for appliance and at supported patch level
APPLIANCE=N
if [ -f /etc/init.d/kickstartpostinstall.sh ]; then
	checkSupportedASMOS
	if [ $? -eq 0 ]; then
		APPLIANCE=Y
	fi

fi



# adjust ownership
# (ensure deploy files are owned by root to control access esp for editing shell scripts
# and other sensitive files)
lockdown_user_privileges() {

    echo [`date`] locking privileges for root user...
    echo Change deploy area ownership to root:${AVEKSA_GROUP}
    chown -R root:${AVEKSA_GROUP} "${AVEKSA_HOME}"/deploy
    # ensure shell scripts and snippets for sudoers are appropriately locked down for editing
    find "${AVEKSA_HOME}"/deploy -name "*.sh" -exec chmod u=rwx,g=rx,o-rwx {} +
    find "${AVEKSA_HOME}"/deploy -name "*.snippet" -exec chmod u=rw,g=r,o-rwx {} +
    find "${AVEKSA_HOME}"/deploy -name "*.jar" -exec chmod u=rwx,g=rx,o-rwx {} +
    find "${AVEKSA_HOME}"/deploy -name "*.sql" -exec chmod u=rw,g=r,o-rwx {} +
    find "${AVEKSA_HOME}"/deploy -name "*.groovy" -exec chmod u=rwx,g=rx,o-rwx {} +
    find "${AVEKSA_HOME}"/deploy -type f \( -name "dbora" -o -name "setlocaltime" -o -name "avagent" -o -name "itim_agent*" \) -exec chmod u=rwx,g=rx,o-rwx {} +
    echo [`date`] locking privileges for root user completed...

}

updateSetDeployEnvJavaHome(){
    #Update the setDeployEnv.sh scripts in home directories
    for f in /root/setDeployEnv.sh "$USER_HOME"/setDeployEnv.sh /home/admin/setDeployEnv.sh "$AVEKSA_HOME"/deploy/setDeployEnv.sh; do
        if [ -f "$f" ]; then
           sed -i "s#^export JAVA_HOME=.*#export JAVA_HOME=${JAVA_HOME}#g" "$f"
        else
            if [ -d "$(dirname "$f")" ]; then
               # Create the file for the installer to be able to use Java:
               echo "export JAVA_HOME=$JAVA_HOME" > "$f"
               chown --reference="$(dirname "$f")" "$f"
            fi
        fi
    done
}

checkReqJDKVersion() {
    "${JAVA_HOME}"/bin/java -version 2>&1 | grep "${JDK_NAME}" | grep -q "${JAVA_VERSION}"_"${JAVA_PATCH_VERSION}"
    if [ $? -eq 0 ]; then
        header Skipping JDK installation, as "$JDK_NAME" Version: "$JAVA_VERSION" Patch Level: "$JAVA_PATCH_VERSION" is installed and set to default.
        export JAVA_HOME=$(readlink --canonicalize-existing /etc/alternatives/"${JAVA_BASENAME}")
        updateSetDeployEnvJavaHome
        logLine JAVA_HOME = $JAVA_HOME
        return 0
    fi
    return 1
}

