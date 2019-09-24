#!/bin/bash
#
#    NAME
#      InspectSystem.sh - System Inspection routine for databases
#
#  Copyright (c) 2011 by Aveksa
#
#
#    DESCRIPTION
#       This is a script that inspects the kernel settings for the operating
# system where the database server is being installed and adjusts values
# found in the file /etc/sysctl.conf.   This file represents the startup
# values for the various kernel settings.  They do not take effect until
# the command '/sbin/sysctl -p' is run at the end of script The automated
# setting of these kernel settings will only take place on kickstart
# installations.  For other installations, it will simply create a file of
# suggested changes and recommend to the system administrator that they
# apply them.
#
#
#  Modification History
# (MM/DD/YY)- Who       What
#  02/24/11 - alandeck  Modified to only autoapply kernel changes when run from kickstart
#                       - Also the 32 bit shmmax setting is being changed as per Oracle docs
#  01/06/11 - alandeck  Created
#

if [ -z ${DEBUG} ] ; then DEBUG=FALSE ; fi
if [ -z ${TEST_MODE_ON} ] ; then TEST_MODE_ON=FALSE ; fi

# TBD  This is the Pre-req check for 64 bit. 
if [ "$HOSTTYPE" = "x86_64" ]; then
        IS64BIT=Y
else
        echo Operating System is 32 bit. 32 bit is not supported. | tee -a $LOG
        echo "The existing Operating System version is unsupported or unknown." | tee -a $LOG
        echo "Please install a required operating system before proceeding with this install." | tee -a $LOG
        echo "See the $PRODUCT_NAME Installation guide for more information regarding OS installation." | tee -a $LOG
        exit 1
fi


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

if [ -f "./common_root.sh" ]; then
	. ./common_root.sh
else
	if [ -f "../common_root.sh" ]; then
		. ../common_root.sh
	else
		echo "common_root.sh not found"
		exit 1
	fi
fi

funcErrorMessage=()
sysctlSettingsChangePrepFile(){
    rm -f ${MODIFY_SETTINGS_FILE}
    touch ${MODIFY_SETTINGS_FILE}
    chmod 700 ${MODIFY_SETTINGS_FILE}
    cat >> ${MODIFY_SETTINGS_FILE} <<EOF
#!/bin/bash
# Kernel modification script, to be run by root
# Script generated on `date`
EOF

}

sysctlSettingsChangeFinalizeFile(){
    cat >> ${MODIFY_SETTINGS_FILE} <<EOF
logToFile
logToFile Applying changes to system, running /sbin/sysctl -p
logToFile Begin -----------------------------------
/sbin/sysctl -p >> $LOG
logToFile End -----------------------------------
# ------------------------------------
EOF

}
sysctlSettingsChangeDeleteFile(){
    rm -f ${MODIFY_SETTINGS_FILE}
}
checkOneValueMinimumGeneric(){
    SETTING_STRING=$1
    LIMIT=$2
    FOUND_VALUE=$(/sbin/sysctl -a | grep ${SETTING_STRING} | cut -d= -f2 | tr -d ' ')
    if [ ${FOUND_VALUE} -lt ${LIMIT} ]; then
        logToFile --------------------------------------------------------------------------------
        logToFile Changing setting of ${SETTING_STRING},
        logToFile value found is less than recommended value
        logToFile "   Old setting = ${FOUND_VALUE}"
        logToFile "   New setting = ${LIMIT}"
        cat >> ${MODIFY_SETTINGS_FILE} <<EOF
echo "" >>/etc/sysctl.conf
echo "# Current setting of ${SETTING_STRING} " >> /etc/sysctl.conf
echo ${SETTING_STRING} = ${LIMIT} >> /etc/sysctl.conf
# ------------------------------------
EOF
        CHANGES_MADE=1

    fi
}

checkKernelPanicOnOops(){
    checkOneValueMinimumGeneric kernel.panic_on_oops 1
}

checkKernelSemSettings(){
    SET_SEM=0
    SEM=$(/sbin/sysctl -a | grep kernel.sem | cut -d= -f2)
    SEM1=$(echo $SEM|cut -d" " -f1) #semmsl
    SEM2=$(echo $SEM|cut -d" " -f2) #semmns
    SEM3=$(echo $SEM|cut -d" " -f3) #semopm
    SEM4=$(echo $SEM|cut -d" " -f4) #semmni
    if [ $SEM1 -lt 250 ]; then SEM1=250; SET_SEM=1; fi
    if [ $SEM2 -lt 32000 ]; then SEM2=32000; SET_SEM=1; fi
    if [ $SEM3 -lt 100 ]; then SEM3=100; SET_SEM=1; fi
    if [ $SEM4 -lt 128 ]; then SEM4=128; SET_SEM=1; fi

    if [ $SET_SEM -eq 1 ]; then
        logToFile --------------------------------------------------------------------------------
        logToFile Changing setting of kernel.sem
        logToFile "   Old setting = $SEM"
        logToFile "   New setting = $SEM1 $SEM2 $SEM3 $SEM4"
        cat >> ${MODIFY_SETTINGS_FILE} <<EOF
echo "" >>/etc/sysctl.conf
echo "# Changing setting of kernel.sem" >>/etc/sysctl.conf
echo kernel.sem = $SEM1 $SEM2 $SEM3 $SEM4 >>/etc/sysctl.conf
# ------------------------------------
EOF

        CHANGES_MADE=1
    fi
}

checkKernelShmmax(){
    # Oracle needs SHMMAX to be at least half of physical memory, for a production systems
    min_SHMMAX=$(expr $(grep MemTotal /proc/meminfo|grep -o -E '[0-9]+') '*' 512)
    SHMMAX=$(/sbin/sysctl -a | grep kernel.shmmax | cut -d= -f2 | tr -d ' ')
    if [ $SHMMAX == 18446744073709551615 -o $SHMMAX == 18446744073692774399 ]; then
        # ignore crazy big number on SuSE or RHEL7
        logToFile Editing kernel.shmmax value as it is too large to handle
        SHMMAX=0
    fi
    if [ $SHMMAX -lt $min_SHMMAX ]; then
        logToFile --------------------------------------------------------------------------------
        logToFile Changing setting of kernel.shmmax to bring it up to recommended minimums
        logToFile "   Old setting = $SHMMAX"
        logToFile "   New setting = $min_SHMMAX"
        cat >> ${MODIFY_SETTINGS_FILE} <<EOF
echo "" >>/etc/sysctl.conf
echo "# Using the recommended min kernel.shmmax value " >> /etc/sysctl.conf
echo "#    of ($min_SHMMAX) rather than ($SHMMAX)" >> /etc/sysctl.conf
echo kernel.shmmax = $min_SHMMAX >> /etc/sysctl.conf
# ------------------------------------
EOF
        SHMMAX=$min_SHMMAX
        CHANGES_MADE=1
    fi
    if [ $SHMMAX -lt 536870912 ]; then
        logToFile --------------------------------------------------------------------------------
        logToFile Changing setting of kernel.shmmax is below the level recommended by Oracle
        logToFile the new setting is NOT appropriate for production systems
        logToFile "   Old setting = $SHMMAX"
        logToFile "   New setting = 536870912"
        cat >> ${MODIFY_SETTINGS_FILE} <<EOF
echo "" >>/etc/sysctl.conf
echo "# Using the development setting for kernel.shmmax value " >> /etc/sysctl.conf
echo "#    of (536870912) rather than ($SHMMAX)" >> /etc/sysctl.conf
echo kernel.shmmax = 536870912 >> /etc/sysctl.conf
# ------------------------------------
EOF
        CHANGES_MADE=1
    fi
}

checkKernelShmall(){
    # Oracle needs kernel.shmall to reflect the size of all RAM + SWAP, in pages
    TOTAL_RAM_SIZE=$(expr $(grep MemTotal /proc/meminfo|grep -o -E '[0-9]+') '*' 1024)
    TOTAL_SWAP_SIZE=$(expr $(grep SwapTotal /proc/meminfo|grep -o -E '[0-9]+') '*' 1024)
    MEM_PAGE_SIZE=$(getconf PAGE_SIZE)

    rec_SHMALL=$(expr $(expr $TOTAL_RAM_SIZE '+' $TOTAL_SWAP_SIZE) '/' $MEM_PAGE_SIZE)
    cur_SHMALL=$(/sbin/sysctl -a | grep shmall | cut -d= -f2 | tr -d ' ')

    if [ $cur_SHMALL == 18446744073692774399 ]; then
        # ignore crazy big number on RHEL7
        logToFile Editing kernel.shmall value as it is too large to handle
        cur_SHMALL=268435456
    fi

    if [ $rec_SHMALL -lt 2097152 ]; then
        # Oracle minimum value
        rec_SHMALL=2097152
    fi

    if [ $cur_SHMALL -ge 268435456 ]; then # ignore any value greater than 1 TB of RAM
        logToFile --------------------------------------------------------------------------------
        cur_SHMALL_inTB=$(expr $cur_SHMALL '/' 268435456)
        logToFile "Changing setting of kernel.shmall, value found is too large"
        logToFile "   Old setting = $cur_SHMALL which represents $cur_SHMALL_inTB TB of memory"
        logToFile "   New setting = $rec_SHMALL"
        cat >> ${MODIFY_SETTINGS_FILE} <<EOF
echo "" >>/etc/sysctl.conf
echo "# Overriding the kernel.shmall value of ($cur_SHMALL) " >> /etc/sysctl.conf
echo "#   this setting represents $cur_SHMALL_inTB TB of memory" >> /etc/sysctl.conf
echo "# Using a value of ($rec_SHMALL) instead" >> /etc/sysctl.conf
echo kernel.shmall = $rec_SHMALL >> /etc/sysctl.conf
# ------------------------------------
EOF
        cur_SHMALL=$rec_SHMALL
        CHANGES_MADE=1
    fi

    if [ $cur_SHMALL -lt $rec_SHMALL ]; then
        logToFile --------------------------------------------------------------------------------
        logToFile Changing setting of kernel.shmall, value found is less than recommended value
        logToFile "   Old setting = $cur_SHMALL"
        logToFile "   New setting = $rec_SHMALL"
        cat >> ${MODIFY_SETTINGS_FILE} <<EOF
echo "" >>/etc/sysctl.conf
echo "# Current setting of kernel.shmall " >> /etc/sysctl.conf
echo "#   value ($cur_SHMALL) less than recommended value" >> /etc/sysctl.conf
echo "# Using a value of ($rec_SHMALL) instead" >> /etc/sysctl.conf
echo kernel.shmall = $rec_SHMALL >> /etc/sysctl.conf
# ------------------------------------
EOF
        CHANGES_MADE=1
    fi
}

checkKernelShmmni(){
    checkOneValueMinimumGeneric kernel.shmmni 4096
}

checkFsFileMax(){
    checkOneValueMinimumGeneric fs.file-max 6815744
}

checkFsAioMaxNr(){
    checkOneValueMinimumGeneric fs.aio-max-nr 1048576
}

checkNetCoreRmemDefault(){
    checkOneValueMinimumGeneric net.core.rmem_default 262144
}

checkNetCoreRmemMax(){
    checkOneValueMinimumGeneric net.core.rmem_max 4194304
}

checkNetCoreWmemDefault(){
    checkOneValueMinimumGeneric net.core.wmem_default 262144
}

checkNetCoreWmemMax(){
    checkOneValueMinimumGeneric net.core.wmem_max 1048576
}


checkLinkLocalInterfaces(){
    if [ -f /etc/sysconfig/network/config ] ; then
        grep ^LINKLOCAL_INTERFACES /etc/sysconfig/network/config
        if [ $? -eq 0 ] ; then
        echo 'sed -i "s/^LINKLOCAL_INTERFACES/#LINKLOCAL_INTERFACES/g" /etc/sysconfig/network/config' >>${MODIFY_SETTINGS_FILE}
        fi
    fi
    ### Need same for SLES
}

checkNetIpv4IpLocalPortRange(){
    PORT1=$(/sbin/sysctl -a | grep net.ipv4.ip_local_port_range | cut -d= -f2 | cut -f1 | tr -d ' ')
    PORT2=$(/sbin/sysctl -a | grep net.ipv4.ip_local_port_range | cut -d= -f2 | cut -f2 | tr -d ' ')
    if [ $PORT1 -lt 9000 -o $PORT2 -lt 65000 ]; then
        PORT1NEW=$PORT1
        PORT2NEW=$PORT2
        if [ $PORT1 -lt 9000 ]; then PORT1NEW=9000; fi
        if [ $PORT2 -lt 65000 ]; then PORT2NEW=65000; fi
        echo -----------------------------------
        echo Changing setting of net.ipv4.ip_local_port_range, values found are less than recommended values
        echo Old setting = $PORT1 $PORT2
        echo New setting = $PORT1NEW $PORT2NEW
        cat >> ${MODIFY_SETTINGS_FILE} <<EOF
echo "" >>/etc/sysctl.conf
echo "# Current setting of net.ipv4.ip_local_port_range value ($PORT1 $PORT2) less than recommended value" >> /etc/sysctl.conf
echo "# Using a value of ($PORT1NEW $PORT2NEW) instead" >> /etc/sysctl.conf
echo net.ipv4.ip_local_port_range = $PORT1NEW $PORT2NEW >> /etc/sysctl.conf
# ------------------------------------
EOF
        CHANGES_MADE=1
    fi
}
fixSwapSize(){
    # Check for sufficient swap space (sizes in kb)
    MEM_TOTAL=$(grep MemTotal /proc/meminfo|grep -o -E '[0-9]+')
    SWAP_SIZE=$(grep SwapTotal /proc/meminfo|grep -o -E '[0-9]+')
    if [ ${MEM_TOTAL} -le 2097152 ]; then
        # 1G-2G, then 1.5x mem size
        SWAP_MIN=$(expr ${MEM_TOTAL} '*' 3 '/' 2)
    elif [ ${MEM_TOTAL} -le 16777216 ]; then
        # 2G-16G, then 1x mem size
        SWAP_MIN=${MEM_TOTAL}
    else
        # >16G, then 16G
        SWAP_MIN=16777216
    fi
    if [ ${SWAP_SIZE} -lt ${SWAP_MIN} ]; then
        # Increase the size of the swap
        # Add 1M for overhead
        SWAP_MIN=$(expr ${SWAP_MIN} + 1024)
        # Add 4 bytes, testing indicates finished swap allocation may be off
        SWAP_DIFF=$(expr ${SWAP_MIN} - ${SWAP_SIZE} + 4)
        echo -----------------------------------
        echo Increasing the size of the swap memory
        echo Old setting = ${SWAP_SIZE} kb
        echo New setting = ${SWAP_MIN} kb
        cat >> ${MODIFY_SETTINGS_FILE} <<EOF
logToFile Increasing the size of the swap space to ${SWAP_MIN} kb
dd if=/dev/zero of=/swapfile bs=1024 count=$SWAP_DIFF 2>&1
mkswap /swapfile
swapon /swapfile
echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
# ------------------------------------
EOF
        CHANGES_MADE=1
    fi
}

checkIfRsaAppliance(){
    RSA_APPLIANCE=N
    if [ -f /etc/init.d/kickstartpostinstall.sh ]; then
        RSA_APPLIANCE=Y
        logToFile "This system looks like a RSA Appliance, all sysctl changes will be applied automatically"
        logToFile --------------------------------------------------------------------------------
    fi
}

runSysctlIndividualTests(){
    checkKernelPanicOnOops
    checkKernelSemSettings
    checkKernelShmmax
    checkKernelShmall
    checkKernelShmmni
    checkFsFileMax
    checkFsAioMaxNr
    checkNetCoreRmemDefault
    checkNetCoreRmemMax
    checkNetCoreWmemDefault
    checkNetCoreWmemMax
    checkLinkLocalInterfaces
    checkNetIpv4IpLocalPortRange

   if [ $REMOTE_ORACLE = N ]; then
        # Purpose : fix if necessary and check if the system has the swap space matching RAM up to 16GB
        fixSwapSize
        #runtest checkSwapSpace
    fi
}

runSysctlTests(){
    MODIFY_SETTINGS_FILE="/tmp/modify_kernel_settings.sh"
    CHANGES_MADE=0

    logToFile --------------------------------------------------------------------------------
    logToFile Inspecting the kernel settings in /etc/sysctl.conf file

    checkIfRsaAppliance
    sysctlSettingsChangePrepFile
    runSysctlIndividualTests

    if [ ${CHANGES_MADE} -eq 1 ] ; then
        sysctlSettingsChangeFinalizeFile
    else
        sysctlSettingsChangeDeleteFile
    fi
    # If there are changes that need to be applied
    if [ ${CHANGES_MADE} -eq 1 ]; then
        if [[ "$RSA_APPLIANCE" == "Y" || "$QUIET" == "Y" ]]; then
            . ${MODIFY_SETTINGS_FILE}
            logToFile ""
            if [ $? -eq 0 ]; then
               logToFile "The kernel settings change script completed successfully."
            else
               echo "Failed to change the kernel settings."
               echo "Review ${MODIFY_SETTINGS_FILE}; manually update the kernel settings and then re-run the install."
            fi
        else
            echo "   There are kernel settings that must be changed for this product to work"
            echo "   as expected.   Created ${MODIFY_SETTINGS_FILE} to change settings."
            read -p "   Do you want to run kernel settings change script now (yes or no)? "       1>&2
            case $REPLY in
                y | yes | YES | Yes)
                    . ${MODIFY_SETTINGS_FILE}
                    EXIT_STATUS=$?
                    echo ""
                    if [ $? -eq 0 ]; then
                       echo "The kernel settings change script completed successfully."
                    else
                       echo "Failed to change the kernel settings."
                       echo "Review ${MODIFY_SETTINGS_FILE}; manually update the kernel settings and then re-run the install."
                       exit $EXIT_STATUS
                    fi
                ;;
                *)
                    echo "   You have chosen to manually run kernel settings change script."
                    echo "   Execute ${MODIFY_SETTINGS_FILE} as root"
                    echo "   and then start install again."
                    echo --------------------------------------------------------------------------------
                    exit 2
                ;;
                esac
        fi
        #check the resulting swap space after the modify settings file is run. This causes all kernel/swap changes to be applied.
        if [ $REMOTE_ORACLE = N ]; then
            runtest checkSwapSpace
        fi

    else
        return 0
    fi
}
runtest() {
    [ "${DEBUG}" == "TRUE" ] && echo runtest : $*
    if [ "${TEST_MODE_ON}" == "TRUE" ]; then
        printf  "\n next test \n\n"
    fi
    logToFile "Running test :  $*"
    $*
    if [ $? == 0 ]; then
        logToFile "    Test passed"
        return 0
    else
        echo "    Test failed"
        missingReqArr+="$*"
    fi
}
skiptest() {
    echo "Skip test :  $*"
}
setFuncErrorMessage() {
    [ "${DEBUG}" == "TRUE" ] && echo setFuncErrorMessage : $*
    funcErrorMessage+="${1}"$'\n'
}

checkEntitlementStatus(){
    [ "${DEBUG}" == "TRUE" ] && echo checkEntitlementStatus : $*
    getent $1 $2 > /dev/null 2>&1
    if [ $? -eq 0 ] ; then
        return 0
    else
        return 1
    fi
}

checkEntitlementPrereqs() {
    [ "${DEBUG}" == "TRUE" ] && echo checkEntitlementPrereqs : $*
    checkEntitlementStatus $1 $2
    if [ $? -ne 0 ] ; then
        [ $1 == "passwd" ] && entity="User"
        [ $1 == "group" ] && entity="Group"
        echo  "${entity} \"${2}\" does not exist on this system, it will be created by the installer"
    fi
}

checkEtcHosts(){
    [ "${DEBUG}" == "TRUE" ] && echo checkEtcHosts : $*
    if [ -n "$1" ]; then
        fqdn=$1;
    else
        fqdn=$(hostname -f)
    fi
    if [ -n "$2" ]; then
        shortName=$2
    else
        shortName=$(hostname -s)
    fi
    if [ -n "$3" ]; then
        ipAddress=$3
    else
        ipAddress=$(gethostip -d ${fqdn})
    fi
    properFormatLineCount=`grep -v "^#" /etc/hosts | grep ${ipAddress}.*${fqdn}.*${shortName}.* | wc -l`
    if [ ${properFormatLineCount} -ne 1 ] ; then
        setFuncErrorMessage $'\n'"/etc/hosts missing or bad formatted line ${ipAddress} ${fqdn} ${shortName}"
        return 1
    fi
    properFormatLineCount=`grep -v "^#" /etc/hosts | grep ${ipAddress} | wc -l`
    if [ ${properFormatLineCount} -ne 1 ] ; then
        setFuncErrorMessage $'\n'"IP Address ${ipAddress} appears in /etc/hosts more than once "
        return 1
    fi
    properFormatLineCount=`grep -v "^#" /etc/hosts | grep ${fqdn} | wc -l`
    if [ ${properFormatLineCount} -ne 1 ] ; then
        setFuncErrorMessage $'\n'"Fully qualified domain name ${fqdn} appears in /etc/hosts more than once "
        return 1
    fi
    properFormatLineCount=`grep -v "^#" /etc/hosts | grep ${shortName} | wc -l`
    if [ ${properFormatLineCount} -ne 1 ] ; then
        setFuncErrorMessage $'\n'"Short hostname ${shortName} appears in /etc/hosts more than once "
        return 1
    fi
}

checkDNSResolution(){
    [ "${DEBUG}" == "TRUE" ] && echo checkDNSResolution : $*
    if [ -n "$1" ]; then
        fqdn=$1;
    else
        fqdn=$(hostname -f)
    fi
    if [ -n "$2" ]; then
        ipAddress=$2;
    else
        ipAddress=$(gethostip -d ${fqdn})
    fi
    if [ -n "$3" ]; then
        shortHostName=$3;
    else
        shortHostName=$(hostname -s)
    fi
    [ "${DEBUG}" == "TRUE" ] && echo "fqdn=${fqdn}     ipAddress=${ipAddress}     nodeName=${shortHostName}"
    nslookup ${fqdn} | grep ${ipAddress} > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        setFuncErrorMessage $'\n'"Forward (A record) DNS record is not correct or non-existent ; $(nslookup ${fqdn} | sed -n '5 p')"
        return 1
    fi
    nslookup ${ipAddress} | grep -i ${fqdn} > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        setFuncErrorMessage $'\n'"Reverse (PTR record) DNS record is not correct  or non-existent ; $(nslookup ${ipAddress} | sed -n '4 p')"
        return 1
    fi
    nslookup ${shortHostName} | grep ${ipAddress} > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        setFuncErrorMessage $'\n'"Check for integrity of file /etc/resolv.conf failed ; $(nslookup ${shortHostName} | sed -n '4 p')"
        return 1
    fi
}

checkFqdnHasDomainFormat(){
    [ "${DEBUG}" == "TRUE" ] && echo checkFqdnHasDomainFormat : $*
    if [ -n "$1" ]; then
        fqdn=$1;
    else
        fqdn=$(hostname -f)
    fi
    Valid952HostnameRegex='(?=^.{1,254}$)(^(?>(?!\d+\.)[a-zA-Z0-9\-]{1,63}\.?)+(?:[a-zA-Z]{2,})$)'
    echo ${fqdn} | grep -P ${Valid952HostnameRegex} > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        setFuncErrorMessage $'\n'"This systems fully qualified domain name ${fqdn} is not valid"
        return 1
    fi
}

getOS(){
    #identify and return OS
    osType=""
    if [ -f /etc/redhat-release ]; then
        grep -q "Red Hat Enterprise Linux Server release 8" /etc/redhat-release
        if [ $? -eq 0 ]; then
            osType="RHEL8"
        fi
        grep -q "Red Hat Enterprise Linux Server release 7" /etc/redhat-release
        if [ $? -eq 0 ]; then
            osType="RHEL7"
        fi
        grep -q "Red Hat Enterprise Linux Server release 6" /etc/redhat-release
        if [ $? -eq 0 ]; then
            osType="RHEL6"
        fi
    elif [ -f /etc/SuSE-release ]; then
            grep -q "^VERSION *= *\<12\>" /etc/SuSE-release
            if [ $? -eq 0 ] ; then
                osType="SuSE12"
            fi
            grep -q "^VERSION *= *\<11\>" /etc/SuSE-release
            if [ $? -eq 0 ]; then
               osType="SuSE11"
            fi
       fi
    export osType=${osType:=UnsupportedOS}
    logToFile "    osType : ${osType}"
}

checkOracleRPMsPreReqs(){
    [ "${DEBUG}" == "TRUE" ] && echo checkOracleRPMsPreReqs : $*
    if [ "$osType" = "RHEL6" -o "$osType" = "RHEL7" -o "$osType" = "RHEL8" ]; then
	    if rpm -q syslinux > /dev/null; then
		    :
	    else
		    echo "ERROR: The syslinux package must be installed"
		    exit 1
	    fi
    fi
    if [ -n "$1" ]; then
        selPkg=( $1 )
    else
        getOS
        [ "${DEBUG}" == "TRUE" ] && echo osType : ${osType}
        if [ $REMOTE_ORACLE = Y ]; then
             case "$osType" in
                RHEL5)
                    selPkg=("GConf2-2.14.0,GConf2,2.14.0,,x86_64")
                ;;
                RHEL6)
                    selPkg=("GConf2-2.28.0,GConf2,2.28.0,,x86_64")
                ;;
                RHEL7)
                    selPkg=("GConf2-3.2.6,GConf2,3.2.6,,x86_64")
                ;;
                RHEL8)
                    selPkg=("GConf2-3.2.6,GConf2,3.2.6,,x86_64")
                ;;
                SuSE11)
                    selPkg=( )
                ;;
                SuSE12)
                    selPkg=( )
                ;;
                *)
                    setFuncErrorMessage $'\n'"Unsupported Operating System or patch level detected"
                    return 1
                    ;;
             esac
        else
            case "$osType" in
                RHEL5)
                    selPkg=( "binutils-2.17.50.0.6,binutils,2.17.50.0.6,,x86_64"
                             "compat-libstdc++-33-3.2.3,compat-libstdc++-33,3.2.3,,x86_64"
                             "compat-libstdc++-33-3.2.3 (32 bit),compat-libstdc++-33,3.2.3,,i386"
                             "gcc-4.1.2,gcc,4.1.2,,x86_64"
                             "gcc-c++-4.1.2,gcc-c++,4.1.2,,x86_64"
                             "glibc-2.5-58,glibc,2.5,58,x86_64"
                             "glibc-devel-2.5-58,glibc-devel,2.5,58,x86_64"
                             "glibc-devel-2.5-58 (32 bit),glibc-devel,2.5,58,i386"
                             "ksh,ksh,,,x86_64"
                             "libaio-0.3.106,libaio,0.3.106,,x86_64"
                             "libaio-0.3.106 (32 bit),libaio,0.3.106,,i386"
                             "libaio-devel-0.3.106,libaio-devel,0.3.106,,x86_64"
                             "libgcc-4.1.2,libgcc,4.1.2,,x86_64"
                             "libgcc-4.1.2 (32 bit),libgcc,4.1.2,,i386"
                             "libstdc++-4.1.2,libstdc++,4.1.2,,x86_64"
                             "libstdc++-4.1.2 (32 bit),libstdc++,4.1.2,,i386"
                             "libstdc++-devel 4.1.2,libstdc++-devel,4.1.2,,x86_64"
                             "libXext-1.0.1,libXext,1.0.1,,x86_64"
                             "libXext-1.0.1 (32 bit),libXext,1.0.1,,i386"
                             "libXtst-1.0.1,libXtst,1.0.1,,x86_64"
                             "libXtst-1.0.1 (32 bit),libXtst,1.0.1,,i386"
                             "libX11-1.0.3,libX11,1.0.3,,x86_64"
                             "libX11-1.0.3 (32 bit),libX11,1.0.3,,i386"
                             "libXau-1.0.1,libXau,1.0.1,,x86_64"
                             "libXau-1.0.1 (32 bit),libXau,1.0.1,,i386"
                             "libXi-1.0.1,libXi,1.0.1,,x86_64"
                             "libXi-1.0.1 (32 bit),libXi,1.0.1,,i386"
                             "make-3.81,make,3.81,,x86_64"
                             "sysstat-7.0.2,sysstat,7.0.2,,x86_64"
                             "nfs-utils-1.0.9-60.0.2,nfs-utils,1.0.9,60.0.2,x86_64"
                             "coreutils-5.97-23.el5_4.1,coreutils,5.97,23.el5_4.1,"
                             "syslinux-1.54-1.el5,syslinux,1.54,1.el5,x86_64"
                             "GConf2-2.14.0,GConf2,2.14.0,,x86_64")
                    ;;
                RHEL6)
                    selPkg=( "binutils-2.20.51.0.2-5.11.el6 (x86_64),binutils,2.20.51.0.2,5.11,x86_64"
                             "compat-libcap1-1.10-1 (x86_64),compat-libcap1,1.1,1,x86_64"
                             "compat-libstdc++-33-3.2.3-69.el6 (x86_64),compat-libstdc++-33,3.2.3,69,x86_64"
                             "gcc-4.4.4-13.el6 (x86_64),gcc,4.4.4,13,x86_64"
                             "gcc-c++-4.4.4-13.el6 (x86_64),gcc-c++,4.4.4,13,x86_64"
                             "glibc-2.12-1.7.el6 (x86_64),glibc,2.12,1.7,x86_64"
                             "glibc-devel-2.12-1.7.el6 (x86_64),glibc-devel,2.12,1.7,x86_64"
                             "ksh,ksh,,,"
                             "libgcc-4.4.4-13.el6 (x86_64),libgcc,4.4.4,13,x86_64"
                             "libstdc++-4.4.4-13.el6 (x86_64),libstdc++,4.4.4,13,x86_64"
                             "libstdc++-devel-4.4.4-13.el6 (x86_64),libstdc++-devel,4.4.4,13,x86_64"
                             "libaio-0.3.107-10.el6 (x86_64),libaio,0.3.107,10,x86_64"
                             "libaio-devel-0.3.107-10.el6 (x86_64),libaio-devel,0.3.107,10,x86_64"
                             "libXext-1.1 (x86_64),libXext,1.1,,x86_64"
                             "libXtst-1.0.99.2 (x86_64),libXtst,1.0.99.2,,x86_64"
                             "libX11-1.3 (x86_64),libX11,1.3,,x86_64"
                             "libXau-1.0.5 (x86_64),libXau,1.0.5,,x86_64"
                             "libxcb-1.5 (x86_64),libxcb,1.5,,x86_64"
                             "libXi-1.3 (x86_64),libXi,1.3,,x86_64"
                             "make-3.81-19.el6,make,3.81,19,"
                             "sysstat-9.0.4-11.el6 (x86_64),sysstat,9.0.4,11,x86_64"
                             "nfs-utils-1.2.3-15.0.1,nfs-utils,1.2.3,15.0.1,"
                             "syslinux,syslinux,,,x86_64"
                             "GConf2-2.28.0,GConf2,2.28.0,,x86_64")
                    ;;
                RHEL7)
                    selPkg=( "binutils-2.27-27.base.el7.x86_64,binutils,2.27,27,x86_64"
                             "compat-libcap1-1.10-7.el7.x86_64,compat-libcap1,1.10,7,x86_64"
                             "compat-libstdc++-33-3.2.3-72.el7.x86_64,compat-libstdc++-33,3.2.3,72,x86_64"
                             "gcc-4.8.5-28.el7.x86_64,gcc,4.8.5,28,x86_64"
                             "gcc-c++-4.8.5-28.el7.x86_64,gcc-c++,4.8.5,28,x86_64"
                             "glibc-2.17-222.el7.x86_64,glibc,2.17,222,x86_64"
                             "glibc-devel-2.17-222.el7.x86_64,glibc-devel,2.17,222,x86_64"
                             "ksh,ksh,,,"
                             "libaio-0.3.109-13.el7.x86_64,libaio,0.3.109,13,x86_64"
                             "libaio-devel-0.3.109-13.el7.x86_64,libaio-devel,0.3.109,13,x86_64"
                             "libgcc-4.8.5-28.el7.x86_64,libgcc,4.8.5,28,x86_64"
                             "libstdc++-4.8.5-28.el7.x86_64,libstdc++,4.8.5,28,x86_64"
                             "libstdc++-devel-4.8.5-28.el7.x86_64,libstdc++-devel,4.8.5,28,x86_64"
                             "libXi-1.7.9-1.el7.x86_64,libXi,1.7.9,1,x86_64"
                             "libXtst-1.2.3-1.el7.x86_64,libXtst,1.2.3,1,x86_64"
                             "make-3.82-23.el7.x86_64,make,3.82,23,x86_64"
                             "sysstat-10.1.5-13.el7.x86_64,sysstat,10.1.5,13,x86_64"
                             "javapackages-tools,javapackages-tools,,,"
                             "lcms2,lcms2,,,"
                             "bea-stax-api,bea-stax-api,,,"
                             "rhino,rhino,,,")
                    ;;
                 RHEL8)
                    selPkg=( "binutils-2.30-49.base.el8.x86_64,binutils,2.30,49,x86_64"
                            "libaio-0.3.110-12.el8.x86_64,libaio,0.3.110,12,x86_64"
                             "libgcc-8.2.1-3.5.el8.x86_64,libgcc,8.2.1,3.5,x86_64"
                             "libgcc-8.2.1-3.5.el8.x86_64,libgcc,8.2.1,3.5,x86_64"
                             "libstdc++-8.2.1-3.5.el8.x86_64,libstdc++,8.2.1,3.5,x86_64"
                             "libXi-1.7.9-7.el8.x86_64,libXi,1.7.9,7,x86_64"
                             "libXtst-1.2.3-7.el8.x86_64,libXtst,1.2.3,7,x86_64"
                             "javapackages-tools,javapackages-tools,,,"
                             "lcms2,lcms2,,,"
                             "bea-stax-api,bea-stax-api,,,")
                    ;;
                SuSE11)
                    selPkg=( "binutils-2.21.1-0.7.25,binutils,2.21.1,0.7.25,"
                             "gcc-4.3-62.198,gcc,4.3,62.198,"
                             "gcc-c++-4.3-62.198 ,gcc-c++,4.3,62.198,"
                             "glibc-2.11.3-17.31.1,glibc,2.11.3,17.31.1,"
                             "glibc-devel-2.11.3-17.31.1,glibc-devel,2.11.3,17.31.1,"
                             "ksh-93u-0.6.1,ksh,93u,0.6.1,"
                             "libaio-0.3.109-0.1.46,libaio,0.3.109,0.1.46,"
                             "libaio-devel-0.3.109-0.1.46,libaio-devel,0.3.109,0.1.46,"
                             "libcap1-1.10-6.10,libcap1,1.1,6.1,"
                             "libstdc++33-3.3.3-11.9,libstdc++33,3.3.3,11.9,"
                             "libstdc++33-32bit-3.3.3-11.9,libstdc++33-32bit,3.3.3,11.9,"
                             "libstdc++43-devel-4.3.4_20091019-0.22.17,libstdc++43-devel,4.3.4_20091019,0.22.17,"
                             "libstdc++46-4.6.1_20110701-0.13.9,libstdc++46,4.6.1_20110701,0.13.9,"
                             "libgcc46-4.6.1_20110701-0.13.9,libgcc46,4.6.1_20110701,0.13.9,"
                             "make-3.81,make,3.81,,"
                             "sysstat-8.1.5-7.32.1,sysstat,8.1.5,7.32.1,"
                             "xorg-x11-libs-32bit-7.4,xorg-x11-libs-32bit,7.4,,"
                             "xorg-x11-libs-7.4,xorg-x11-libs,7.4,,"
                             "xorg-x11-libX11-32bit-7.4,xorg-x11-libX11-32bit,7.4,,"
                             "xorg-x11-libX11-7.4,xorg-x11-libX11,7.4,,"
                             "xorg-x11-libXau-32bit-7.4,xorg-x11-libXau-32bit,7.4,,"
                             "xorg-x11-libXau-7.4,xorg-x11-libXau,7.4,,"
                             "xorg-x11-libxcb-32bit-7.4,xorg-x11-libxcb-32bit,7.4,,"
                             "xorg-x11-libxcb-7.4,xorg-x11-libxcb,7.4,,"
                             "xorg-x11-libXext-32bit-7.4,xorg-x11-libXext-32bit,7.4,,"
                             "xorg-x11-libXext-7.4,xorg-x11-libXext,7.4,,"
                             "nfs-kernel-server-1.2.1-2.24.1.x86_64,nfs-kernel-server,1.2.1,2.24.1,x86_64"
                             "syslinux-1.54.x86_64,syslinux,1.54,,x86_64" )
                    ;;
                SuSE12)
                    selPkg=( "binutils-2.25.0-13.1.x86_64,binutils,2.25.0,13.1,x86_64"
                             "gcc-4.8-6.189.x86_64,gcc,4.8,6.189,x86_64"
                             "gcc48-4.8.5-24.1.x86_64,gcc48,4.8.5,24.1,x86_64"
                             "glibc-2.19-31.9.x86_64,glibc,2.19,31.9,x86_64"
                             "glibc-devel-2.19-31.9.x86_64,glibc-devel,2.19,31.9,x86_64"
                             "mksh-50-2.13.x86_64,mksh,50,2.13,x86_64"
                             "libaio1-0.3.109-17.15.x86_64,libaio1,0.3.109,17.15,x86_64"
                             "libaio-devel-0.3.109-17.15.x86_64,libaio-devel,0.3.109,17.15,x86_64"
                             "libcap1-1.10-59.61.x86_64,libcap1,1.10,59.61,x86_64"
                             "libstdc++48-devel-4.8.5-24.1.x86_64,libstdc++48-devel,4.8.5,24.1,x86_64"
                             "libstdc++6-5.2.1+r226025-4.1.x86_64,libstdc++6,5.2.1+r226025,4.1,x86_64"
                             "libstdc++-devel-4.8-6.189.x86_64,libstdc++-devel,4.8,6.189,x86_64"
                             "libgcc_s1-5.2.1+r226025-4.1.x86_64,libgcc_s1,5.2.1+r226025,4.1,x86_64"
                             "make-4.0-4.1.x86_64,make,4.0,4.1,x86_64"
                             "sysstat-10.2.1-3.1.x86_64,sysstat,10.2.1,3.1,x86_64"
                             "xorg-x11-driver-video-7.6_1-14.30.x86_64,xorg-x11-driver-video,7.6_1,14.30,x86_64"
                             "xorg-x11-server-7.6_1.15.2-36.21.x86_64,xorg-x11-server,1.15.2,36.21,x86_64"
                             "xorg-x11-essentials-7.6_1-14.17.noarch,xorg-x11-essentials,7.6_1,14.17,noarch"
                             "xorg-x11-Xvnc-1.4.3-7.2.x86_64,xorg-x11-Xvnc,1.4.3,7.2,x86_64"
                             "xorg-x11-fonts-core-7.6-29.45.noarch,xorg-x11-fonts-core,7.6,29.45,noarch"
                             "xorg-x11-7.6_1-14.17.noarch,xorg-x11,7.6_1,14.17,noarch"
                             "xorg-x11-server-extra-7.6_1.15.2-36.21.x86_64,xorg-x11-server-extra,1.15.2,36.21,x86_64"
                             "xorg-x11-libs-7.6-45.14.noarch,xorg-x11-libs,7.6,45.14,noarch"
                             "xorg-x11-fonts-7.6-29.45.noarch,xorg-x11-fonts,7.6,29.45,noarch"
                             "libcap2-2.22-13.1.x86_64,libcap2,2.22,13.1,x86_64"
                             "oracleasm-kmp-default-2.0.8_k4.4.21_69-6.101.x86_64,oracleasm-kmp-default,2.0.8_k4.4.21_69,6.101,x86_64"
                             "oracleasm-support-2.1.8-1.x86_64,oracleasm-support,2.1.8,1,x86_64"
                             "oracleasmlib-2.0.12-1.x86_64,oracleasmlib,2.0.12,1,x86_64"
                             "javapackages-tools-2.0.1-6.10.x86_64,javapackages-tools,2.0.1,6.10,x86_64"
                             "lcms2-2.7-7.2.x86_64,lcms2,2.7,7.2,x86_64"
                             "bea-stax-api-1.2.0-5.25.2.noarch,bea-stax-api,1.2.0,5.25.2,noarch"
                             "rhino-1.7-6.25.noarch,rhino,1.7,6.25,noarch"
                             "xmlbeans-2.1.0-2.27.noarch,xmlbeans,2.1.0,2.27,noarch" )
                    ;;
                *)
                    setFuncErrorMessage $'\n'"Unsupported Operating System or patch level detected"
                    return 1
                    ;;
            esac
        fi
    fi
    missingPkgArr=()
    for i in "${selPkg[@]}" ;  do
        IFS=, read neededPkgDesc neededPkgName neededPkgVersion neededPkgRelease neededArch neededExtra <<< "$i"
        neededPkgVersion=$(echo "$neededPkgVersion" | tr '_' '.')

        logToFile "    testing for requirement : ${neededPkgDesc}"
        [ "${DEBUG}" == "TRUE" ] && echo neededPkgName : ${neededPkgName}
        [ "${DEBUG}" == "TRUE" ] && echo neededPkgVersion : ${neededPkgVersion}
        [ "${DEBUG}" == "TRUE" ] && echo neededPkgRelease : ${neededPkgRelease}
        [ "${DEBUG}" == "TRUE" ] && echo neededArch : $neededArch

        case "$neededArch" in
            i386 | i686 | x86_64 | noarch)
                neededArchString=".$neededArch"
                ;;
            *)
                neededArchString=""
                ;;
        esac
        [ "${DEBUG}" == "TRUE" ] && echo neededArchString : ${neededArchString}

        rpm -q --queryformat "%{version}\n" ${neededPkgName}${neededArchString} > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            skipReleaseTest="FALSE"
            continueCompare="TRUE"
            installedPkgVersion=`rpm -q --queryformat "%{version}\n" ${neededPkgName}${neededArchString}| tr "_" "."`
            [ "${DEBUG}" == "TRUE" ] && echo installedPkgVersion : ${installedPkgVersion}
            installedPkgRelease=`rpm -q --queryformat "%{release}.%{arch}\n" ${neededPkgName}${neededArchString}`
            [ "${DEBUG}" == "TRUE" ] && echo installedPkgRelease : ${installedPkgRelease}
            declare -a installed
            declare -a needed
            IFS='.' read -r -a installed <<< "$installedPkgVersion"
            IFS='.' read -r -a needed <<< "$neededPkgVersion"
            for index in "${!needed[@]}" ; do
                if [ "${continueCompare}" == "TRUE" ]; then
                    if [ ${installed[index]} ]; then
                        if [[ ${needed[index]} = *[^0-9]* ]] || [[ ${installed[index]} = *[^0-9]* ]]; then
                            [ "${DEBUG}" == "TRUE" ] && echo "TESTING :: {needed[index]} is equal to or greater than {installed[index]} : ${needed[index]} is equal to or greater than ${installed[index]} - version contains character"
                            needverNum=$(echo ${needed[index]}| grep -o -E '[0-9]*')
                            [ "${DEBUG}" == "TRUE" ] && echo "neededverNUM : $needverNum"
                            neededverletter=$(echo ${needed[index]}| grep -o -E '[A-Za-z]*')
                            [ "${DEBUG}" == "TRUE" ] && echo "neededverletter : $neededverletter"
                            installedverNum=$(echo ${installed[index]}| grep -o -E '[0-9]*')
                            [ "${DEBUG}" == "TRUE" ] && echo "installedverNUM : $installedverNum"
                            installedverletter=$(echo ${installed[index]}| grep -o -E '[A-Za-z]*')
                            [ "${DEBUG}" == "TRUE" ] && echo "installedverletter : $installedverletter"
                            if [ ${needverNum} -lt ${installedverNum} ]; then
			                    skipReleaseTest="TRUE"
			                    continueCompare="FALSE"
                            elif [ ${needverNum} -eq ${installedverNum} ]; then
                                neededArr=( $(echo ${neededverletter} | sed "s/\(.\)/'\1' /g") )
                                installedArr=( $(echo ${installedverletter} | sed "s/\(.\)/'\1' /g") )
                                continueVerCompare="TRUE"
                                for i in ${!neededArr[*]} ; do
                                [ "${DEBUG}" == "TRUE" ] && echo "neededArr[$i] : ${neededArr[$i]} and installedArr[$i] : ${installedArr[$i]}"
                                if [ "${continueVerCompare}" == "TRUE" ]; then
                                    if [ "${neededArr[$i]}" == "${installedArr[$i]}" ] || [ "${neededArr[$i]}" \< "${installedArr[$i]}" ]; then
                                        [ "${DEBUG}" == "TRUE" ] && echo "needed version ${needed[index]} is less than or equal to ${installed[index]}"
                                        continueVerCompare=FALSE
                                    else
                                        missingPkgArr+="Older version ${installedPkgVersion}-${installedPkgRelease} of ${neededPkgName} is installed, ${neededPkgVersion}-${neededPkgRelease} or higher is required"$'\n'$'\n'
                                    fi
                                fi
                                done
                            else
                                if [ ${needverNum} -gt ${installedverNum} ]; then
                                    [ "${DEBUG}" == "TRUE" ] && echo "${needed[index]} -gt ${installed[index]} :: true"
                                    missingPkgArr+="Older version ${installedPkgVersion}-${installedPkgRelease} of ${neededPkgName} is installed, ${neededPkgVersion}-${neededPkgRelease} or higher is required"$'\n'$'\n'
                                fi
                            fi
                        else
                            [ "${DEBUG}" == "TRUE" ] && echo "TESTING :: {needed[index]} -gt {installed[index]} : ${needed[index]} -gt ${installed[index]} - only numeric version"
                            if [ ${needed[index]} -gt ${installed[index]} ]; then
                                [ "${DEBUG}" == "TRUE" ] && echo "${needed[index]} -gt ${installed[index]} :: true"
                                missingPkgArr+="Older version ${installedPkgVersion}-${installedPkgRelease} of ${neededPkgName} is installed, ${neededPkgVersion}-${neededPkgRelease} or higher is required"$'\n'$'\n'
                            else
                                if [ ${needed[index]} -lt ${installed[index]} ]; then
                                    skipReleaseTest="TRUE"
                                    continueCompare="FALSE"
                                fi
                            fi
                        fi
                    else
                        missingPkgArr+="Older version ${installedPkgVersion}-${installedPkgRelease} of ${neededPkgName} is installed, ${neededPkgVersion}-${neededPkgRelease} or higher is required"$'\n'$'\n'
                    fi
                fi
            done
            [ "${DEBUG}" == "TRUE" ] && echo "Finished version test"
            [ "${DEBUG}" == "TRUE" ] && echo "skipReleaseTest=${skipReleaseTest}"
            if [ "${skipReleaseTest}" != "TRUE" ]; then
                continueCompare="TRUE"
                declare -a installed
                declare -a needed
                IFS='.' read -r -a installed <<< "$installedPkgRelease"
                IFS='.' read -r -a needed <<< "$neededPkgRelease"
                for index in "${!needed[@]}" ; do
                    if [ "${continueCompare}" == "TRUE" ]; then
                        if [ ${installed[index]} ]; then
                            if [[ ${needed[index]} = *[^0-9]* ]] || [[ ${installed[index]} = *[^0-9]* ]]; then
                                [ "${DEBUG}" == "TRUE" ] && echo "TESTING :: {needed[index]} is equal to or greater than {installed[index]} : ${needed[index]} is equal to or greater than ${installed[index]} - release contains character"
                                needRelNum=$(echo ${needed[index]}| grep -o -E '[0-9]*')
                                [ "${DEBUG}" == "TRUE" ] && echo "needRelNum : $needRelNum"
                                neededRelLetter=$(echo ${needed[index]}| grep -o -E '[A-Za-z]*')
                                [ "${DEBUG}" == "TRUE" ] && echo "neededRelLetter : $neededRelLetter"
                                installedRelNum=$(echo ${installed[index]}| grep -o -E '[0-9]*')
                                [ "${DEBUG}" == "TRUE" ] && echo "installedRelNum : $installedRelNum"
                                installedRelLetter=$(echo ${installed[index]}| grep -o -E '[A-Za-z]*')
                                [ "${DEBUG}" == "TRUE" ] && echo "installedRelLetter : $installedRelLetter"
                                if ! [ -z ${installedRelNum} ]; then
					if [ ${needRelNum} -lt ${installedRelNum} ]; then
							continueCompare="FALSE"
					elif [ ${needRelNum} -eq ${installedRelNum} ]; then
					    neededArr=( $(echo ${neededRelLetter} | sed "s/\(.\)/'\1' /g") )
					    installedArr=( $(echo ${installedRelLetter} | sed "s/\(.\)/'\1' /g") )
					    continueRelCompare="TRUE"
					    for i in ${!neededArr[*]} ; do
					    [ "${DEBUG}" == "TRUE" ] && echo "neededArr[$i] : ${neededArr[$i]} and installedArr[$i] : ${installedArr[$i]}"
					    if [ "${continueRelCompare}" == "TRUE" ]; then
						if [ "${neededArr[$i]}" == "${installedArr[$i]}" ] || [ "${neededArr[$i]}" \< "${installedArr[$i]}" ]; then
						    [ "${DEBUG}" == "TRUE" ] && echo "needed release ${needed[index]} is less than or equal to ${installed[index]}"
						    continueRelCompare=FALSE
						    continueCompare="FALSE"
						else
						    missingPkgArr+="Older release \"${installedPkgVersion}-${installedPkgRelease}\" of \"${neededPkgName}\" is installed, \"${neededPkgVersion}-${neededPkgRelease}\" or higher is required"$'\n'$'\n'
						fi
					    fi
					    done
					else
					    if [ ${needRelNum} -gt ${installedRelNum} ]; then
						[ "${DEBUG}" == "TRUE" ] && echo "${needed[index]} -gt ${installed[index]} :: true"
						missingPkgArr+="Older version \"${installedPkgVersion}-${installedPkgRelease}\" of \"${neededPkgName}\" is installed, \"${neededPkgVersion}-${neededPkgRelease}\" or higher is required"$'\n'$'\n'
					    fi
					fi
			        else
                            		continueCompare="FALSE"
					missingPkgArr+="Older version \"${installedPkgVersion}-${installedPkgRelease}\" of \"${neededPkgName}\" is installed, \"${neededPkgVersion}-${neededPkgRelease}\" or higher is required"$'\n'$'\n'
                        	fi
                            else
                                [ "${DEBUG}" == "TRUE" ] && echo "TESTING :: needed -gt installed : ${needed[index]} -gt ${installed[index]}"
                                if [ ${needed[index]} -gt ${installed[index]} ]; then
                                    [ "${DEBUG}" == "TRUE" ] && echo "${needed[index]} -gt ${installed[index]} :: true"
                                    missingPkgArr+="Older version \"${installedPkgVersion}-${installedPkgRelease}\" of \"${neededPkgName}\" is installed, \"${neededPkgVersion}-${neededPkgRelease}\" or higher is required"$'\n'$'\n'

                                else
                                    if [ ${needed[index]} -lt ${installed[index]} ]; then
                                        continueCompare="FALSE"
                                    fi
                            fi
                        fi
                        else
                            missingPkgArr+="Older version \"${installedPkgVersion}-${installedPkgRelease}\" of \"${neededPkgName}\" is installed, \"${neededPkgVersion}-${neededPkgRelease}\" or higher is required"$'\n'$'\n'
                        fi
                    fi
                done
            fi
            [ "${DEBUG}" == "TRUE" ] && echo "Finished release test"
        else
            missingPkgArr+="Needed package \"${neededPkgDesc}\" (or higher) is not installed on system"$'\n'$'\n'
        fi
        [ "${DEBUG}" == "TRUE" ] && echo " "
    done
    if [ ${#missingPkgArr[@]} -gt 0 ]; then
        for index in "${!missingPkgArr[@]}" ; do
            errStr+=${missingPkgArr[index]}
        done

        setFuncErrorMessage "${errStr%??}"
        return 1
    fi
    return 0
}

checkInstallPackagesPreReqs(){
    [ "${DEBUG}" == "TRUE" ] && echo checkOracleInstallPreReqs : $*

    PACKAGES_FILE=packages64.txt

    if [ "$REMOTE_ORACLE" = "Y" ]; then
        PACKAGES_FILE=acmpackages64.txt
    fi

    if [ "$OPT_DBONLY" = "Y" ]; then
        PACKAGES_FILE=dbpackages64.txt
    fi

    if [ -f  ${PACKAGES_FILE} ]; then
        for f in $(cat ${PACKAGES_FILE}); do
            logToFile "    testing for requirement : $f"
            if [ ! -f "${PACKAGES_DIR}/$f" ]; then
                setFuncErrorMessage $'\n'"Could not find necessary package $f in ${PACKAGES_DIR}"
                return 1
            fi
		done
    else
        setFuncErrorMessage $'\n'"Installation package is missing one or more required files: ${PACKAGES_FILE}"
        setFuncErrorMessage $'\n' "Make sure that all files from installer package have been extracted and copied; then run the installer again."
        return 1
    fi
    return 0
}

checkMinDiskSizes(){
    [ "${DEBUG}" == "TRUE" ] && echo checkMinDiskSizes : $*
    partitionsToCheck=( "$AVEKSA_HOME" "/home/admin" "/home" "/root" )
    minSizes=( "5452596" "1048576" "1048576" "5347738" )
    fileSystems=()
    availableSpace=()
    if [ "${REMOTE_ORACLE}" = "N" ]; then
        partitionsToCheck+=( "/u01" )
        minSizes+=( "6815744" )
    fi
    for i in "${!partitionsToCheck[@]}"
    do
        while [ ! -d "${partitionsToCheck[i]}" ]
        do
                partitionsToCheck[i]=$(dirname "${partitionsToCheck[i]}")
        done
        read fileSystems[i] availableSpace[i] < <(df -P "${partitionsToCheck[i]}" | tail -1| awk '{print $1, $4}')
    done
    aggregateSpace=("${minSizes[@]}")
    for i in "${!partitionsToCheck[@]}"
    do
        for j in "${!partitionsToCheck[@]}"
        do
                if [ "${fileSystems[i]}" = "${fileSystems[j]}" -a "$i" -ne "$j" ]; then
                        aggregateSpace[i]=$((${aggregateSpace[i]}+${minSizes[j]}))
                fi
        done
    done
    for i in "${!partitionsToCheck[@]}"
    do
        if [ "${availableSpace[i]}" -lt "${aggregateSpace[i]}" ]; then
                setFuncErrorMessage $'\n'"File system \"${fileSystems[i]}\" does not meet the  minimum size requirement : $(echo "scale=2; ${aggregateSpace[i]}" / 1024 / 1024 | bc -l ) GB"
                return 1
        fi
    done
}

checkASMKernelDriver(){
    [ "${DEBUG}" == "TRUE" ] && echo checkASMKernelDriver : $*
    getOS
    asmcheckRequired="$(checkSupportedASMOS; echo $?)";
    [ "${DEBUG}" == "TRUE" ] && echo "asmcheckRequired: $asmcheckRequired"
    if [[ "${osType}" == "RHEL5" && $asmcheckRequired == 0 ]]; then
        if [ -n "$1" ]; then
            additionalAsmPath=${1}
        else
            additionalAsmPath="/dev/null"
        fi
        if [ -n "$2" ]; then
            kernelversion=${2}
        else
            kernelversion=$(uname -r)
        fi
        if [ -n "$3" ]; then
            ASMLIB_PACKAGE_PATH=${3}
        else
            ASMLIB_PACKAGE_PATH=${PACKAGES_DIR}/${ASMLIB_PACKAGE}
        fi

        if [ ! -f ${ASMLIB_PACKAGE_PATH} ]; then
            setFuncErrorMessage $'\n'"Could not find necessary file ${ASMLIB_PACKAGE_PATH}"
            return 1
        fi
        driverFilePrefix="oracleasm-$(uname -r)"
        driverFileSuffix="x86_64.rpm"
        if [ ! "$(tar -jtvf  ${ASMLIB_PACKAGE_PATH} | grep -P "${driverFilePrefix}".*."${driverFileSuffix}")" ]; then
            if [ -f ${additionalAsmPath}/${driverFilePrefix}*${driverFileSuffix} ] ; then
                return 0
            else
                setFuncErrorMessage $'\n'"Could not find ASM driver for kernel: $(uname -r) in ${ASMLIB_PACKAGE_PATH} or ${additionalAsmPath}"
                return 1
            fi
        fi
    fi
}

checkTotalMemory(){
    [ "${DEBUG}" == "TRUE" ] && echo checkTotalMemory : $*
    if [ -n "$1" ]; then
        reqMem=${1}
    else
        reqMem="4194304"
    fi
    if [ -n "$2" ]; then
        freeMem=${2}
    else
        freeMem="51200"
    fi
    totalkb=$(awk '/^MemTotal:/{print $2}' /proc/meminfo) ;
    if [ ${totalkb} -le ${reqMem} ]; then
        setFuncErrorMessage $'\n'"Total memory is less than ${reqMem}"$'\n'
        return 1
    fi
    freekb=$(awk '/^MemFree:/{print $2}' /proc/meminfo) ;
     if [ ${freekb} -le ${freeMem} ]; then
        setFuncErrorMessage $'\n'"Free memory is less than ${freeMem}"$'\n'
        return 1
	fi
}

checkNtp() {
    if [ -f /etc/ntp.conf ]; then
        [ "${DEBUG}" == "TRUE" ] && echo checkNtp : $*
        if [ -n "$1" ]; then
            allowedOffset=$1
        else
            allowedOffset=100.00
        fi
        [ "${DEBUG}" == "TRUE" ] && echo allowedOffset : $allowedOffset
        if [ -n "$2" ]; then
            currentNtpSserver=$2
        else
            currentNtpSserver=`grep ^server /etc/ntp.conf | head -n1 | awk -F" " '{print $2}'`
        fi
        [ "${DEBUG}" == "TRUE" ] && echo currentNtpSserver : $currentNtpSserver

        if [ -f /etc/SuSE-release ] ; then
            ntpServiceName=$(getNTPServiceName)

            if type -P sntp > /dev/null; then
                ntpHostCheckCmd="sntp ${currentNtpSserver}"
            else
                ### Skip the check due to deprecation of ntp
                return 0
            fi
        else
            ntpServiceName="ntpd"
            ntpHostCheckCmd="ntpdate ${currentNtpSserver}"
        fi

        service ${ntpServiceName} restart > /dev/null 2>&1
        sleep 2
        foundOffset=`ntpq -np | grep ${currentNtpSserver} | awk -F" " '{print $9}' |awk ' { if($1>=0) { print $1} else {print $1*-1 }}'`
        [ "${DEBUG}" == "TRUE" ] && echo foundOffset : $foundOffset
        service ${ntpServiceName} stop > /dev/null 2>&1
        ntpErrorMessage=`${ntpHostCheckCmd} 2>&1`
        if [ $? -ne 0 ] ; then
            service ${ntpServiceName} start > /dev/null 2>&1
            setFuncErrorMessage $'\n'"Issue communicating to NTP server \"${currentNtpSserver}\" :: ${ntpErrorMessage}"
            return 1
        fi
        service ${ntpServiceName} start > /dev/null 2>&1
        if (( $(bc <<< "${foundOffset} > ${allowedOffset}") )) ; then
            setFuncErrorMessage $'\n'"NTP offset value \"${foundOffset}\" to NTP server \"${currentNtpSserver}\" is outside allowed offset range \"0\" to \"${allowedOffset}\" "
            return 1
        fi
    fi
}

checkRunLevel(){
    [ "${DEBUG}" == "TRUE" ] && echo checkRunLevel : $*
    if [ -n "$1" ]; then
        local reqRunLevel=("${!1}")
    else
        local reqRunLevel=("3" "5")
    fi

    # Wait up to 2 minutes for the system to reach required run level:
    local TRIES=24
    local n=0

    local rlevel=$(runlevel | cut -d ' ' -f2)
    until [[ ${reqRunLevel[*]} =~ "$rlevel" || $(( n++ )) -ge $TRIES ]]
    do
        sleep 5
        rlevel=$(runlevel | cut -d ' ' -f2)
    done

    if ! [[ ${reqRunLevel[*]} =~ "$rlevel" ]]; then
        setFuncErrorMessage $'\n'"system is not at allowed run levels ${reqRunLevel[*]}"
        return 1
    fi
}

checkUserInGroups(){
    [ "${DEBUG}" == "TRUE" ] && echo checkUserInGroups : $*
    userName=${1}
    if [ -n "$2" ]; then
        groupsToCheck=("${!2}")
    fi
    expectedPrimaryGroup=${groupsToCheck[1]}
    checkEntitlementStatus passwd ${userName}
    if [ $? -eq 0 ] ; then
        for i in "${!groupsToCheck[@]}" ; do
            [ "${DEBUG}" == "TRUE" ] && echo groupsToCheck : ${groupsToCheck[i]}
            checkEntitlementStatus group ${groupsToCheck[i]}
            if [ $? -eq 0 ] ; then
                groupUID=`getent group ${groupsToCheck[i]} | awk -F':' '{print $3}'`
                [ "${DEBUG}" == "TRUE" ] && echo groupUID : ${groupUID}
                id ${userName} -G | tr " " "\n" | grep -qe "^${groupUID}$"
                if [ $? -ne 0 ] ; then
                    setFuncErrorMessage $'\n'"User \"${userName}\" is not in group \"${groupsToCheck[i]}\""
                    return 1
                fi
            else
                echo  $'\n'"     Group \"${groupsToCheck[i]}\" does not exist for user \"${userName}\" to be member of"
                return 0
            fi
        done
    else
        echo  $'\n'"     User \"${userName}\" does not exist on this system ... skipping test"
        return 0
    fi
    expectedPrimaryGroupID=$(getent group ${groupsToCheck[0]} | awk -F':' '{print $3}')
    foundPrimaryGroupID=$(id -g ${userName})
    if [ ${expectedPrimaryGroupID} -ne ${foundPrimaryGroupID} ] ; then
        setFuncErrorMessage $'\n'"User \"${userName}\" does not have effective group set to \"${groupsToCheck[0]}\""
        return 1
    fi
}

checkEtcSecurityLimits() {
    [ "${DEBUG}" == "TRUE" ] && echo checkEtcSecurityLimits : $*
    [ "${DEBUG}" == "TRUE" ] && grep -v "^#" /etc/security/limits.conf
    local domain=$1
    local type=$2
    local item=$3
    local lowerLimit=$4

    local limitsFile=/etc/security/limits.conf
    local pattern="^${domain}[[:space:]]+${type}[[:space:]]+${item}\>"
    local matches=$(grep -Eic "$pattern" "$limitsFile")

    # Check if Oracle installer and Kickstart added duplicate entries:
    if [ $matches -gt 1 ]; then
        # Remove all but the first entry of the pattern, but make sure to keep the original permissions untouched:
        awk "/${pattern}/ && c++ > 0 {next} 1" "$limitsFile" > "${limitsFile}.tmp" && \
            cat "${limitsFile}.tmp" > "$limitsFile" && \
            rm -f "${limitsFile}.tmp"

    elif [ $matches -eq 0 ] ; then
        # Test global limits:
        pattern="^[*][[:space:]]+${type}[[:space:]]+${item}\>"
        matches=$(grep -Eic "$pattern" "$limitsFile")

        if [ $matches -eq 0 ]; then
            echo "Writing the missing configuration entry - \"${domain} ${type} ${item} ${lowerLimit}\" to $limitsFile"
            echo -e "\n${domain} ${type} ${item} ${lowerLimit}" >> "$limitsFile"
            return 0

        elif [ $matches -gt 1 ]; then
            # Remove all but the first entry of the pattern, but make sure to keep the original permissions untouched:
            awk "/${pattern}/ && c++ > 0 {next} 1" "$limitsFile" > "${limitsFile}.tmp" && \
                cat "${limitsFile}.tmp" > "$limitsFile" && \
                rm -f "${limitsFile}.tmp"
        fi
    fi

    local currentLimit=$(grep -Ei "$pattern" "$limitsFile" | awk '{print $4}')
    [ "${DEBUG}" == "TRUE" ] && echo currentLimit : $currentLimit

    if [ "${currentLimit:=0}" = "-1" -o "${currentLimit:=0}" = "unlimited" -o "${currentLimit:=0}" = "infinity" ]; then
        echo "Value for \"${domain} ${type} ${item}\" line in "$limitsFile" is already configured above the required value of ${lowerLimit}"
        return 0

    # Make sure it is a valid number:
    elif [[ $currentLimit =~ ^[0-9]+$ ]]; then
        if [ $currentLimit -ge $lowerLimit ]; then
            echo "Value for \"${domain} ${type} ${item}\" line in "$limitsFile" is already configured equal or above the required value of ${lowerLimit}"
            return 0
        fi
    fi

    # If we reached this far, we need to put the updated limit in:
    echo "Setting the configuration entry - \"${domain} ${type} ${item}\" to $lowerLimit ..."
    sed -ri "s/(${pattern}).*/\1 ${lowerLimit}/" "$limitsFile"
}

checkSwapSpace(){
    [ "${DEBUG}" == "TRUE" ] && echo checkSwapSpace : $*
    # Check for sufficient swap space (sizes in kb)
    MEM_TOTAL=$(grep MemTotal /proc/meminfo|grep -o -E '[0-9]+')
    SWAP_SIZE=$(grep SwapTotal /proc/meminfo|grep -o -E '[0-9]+')
    if [ ${MEM_TOTAL} -le 2097152 ]; then
        # 1G-2G, then 1.5x mem size
        SWAP_MIN=$(expr ${MEM_TOTAL} '*' 3 '/' 2)
    elif [ ${MEM_TOTAL} -le 16777216 ]; then
        # 2G-16G, then 1x mem size
        SWAP_MIN=${MEM_TOTAL}
    else
        # >16G, then 16G
        SWAP_MIN=16777216
    fi
    if [ ${SWAP_SIZE} -lt ${SWAP_MIN} ]; then
        setFuncErrorMessage $'\n'"Current swap size of \"${SWAP_SIZE} KB\" is less then needed minimum value of \"${SWAP_MIN} KB\""
        return 1
    fi
}

checkUserNotInGroup(){
    [ "${DEBUG}" == "TRUE" ] && echo checkUserNotInGroup : $*

    # check the user "userNam" is not part of "groupName" group
    userName=$1
    groupName=$2
    checkEntitlementStatus passwd $userName
    if [ $? -eq 0 ]; then
        id ${userName} | grep \(${groupName}\) > /dev/null 2>&1
        if [ $? -eq 0 ] ; then
            setFuncErrorMessage $'\n'"User \"${userName}\" is part of group \"${groupName}\""
            return 1
        fi
    else
        echo $'\n'"    User \"${userName}\" does not exist on this system yet "
        return 0
    fi
}

checkUMASK(){
    [ "${DEBUG}" == "TRUE" ] && echo checkUmask : $*

    expectedUmask=$1
    # check the user "oracle" is not part of "root" group
    currentUMASK=`umask`
    [ "${DEBUG}" == "TRUE" ] && echo -----------------------------------
    [ "${DEBUG}" == "TRUE" ] && echo "currentUmask : $currentUMASK"
    if [ "${currentUMASK}" != "${expectedUmask}" ]; then
        setFuncErrorMessage $'\n'"UMASK is not set to expected umask \"${expectedUmask}\""
        return 1
    else
        return 0
    fi
}

checkShmMount(){
    [ "${DEBUG}" == "TRUE" ] && echo checkShmMount : $*
    echo "echo hello" > /dev/shm/rsalngtest.sh
    if [ $? -ne 0 ]; then
        setFuncErrorMessage $'\n'"/dev/shm/ is not mounted in read-write mode"
        return 1

    fi

    rm -f /dev/shm/rsalngtest.sh
    return 0
}

checkBootMount(){
    [ "${DEBUG}" == "TRUE" ] && echo checkBootMount : $*
    bootMnt=`mount |awk '{print $3}'| grep -w /boot`
    [ "${DEBUG}" == "TRUE" ] && echo "bootMnt : $bootMnt"
    if [ "$bootMnt" == "/boot" ]; then
        return 0
    else
        setFuncErrorMessage $'\n'"/boot is not mounted correctly"
        return 1
    fi
}

checkAFXPermissions(){
    [ "${DEBUG}" == "TRUE" ] && echo checkAFXPermissions : $*
    if [ -n "$1" ]; then
        afxOwner="${1}"
    else
        afxOwner="oracle"
    fi
    if [ -n "$2" ]; then
        afxHome="${2}"
    else
        afxHome="$AVEKSA_HOME/AFX"
    fi
    if [[ $FRESH_INSTALL != Y && -d "${afxHome}" ]] ; then
        su - ${afxOwner} -c "test -w '${afxHome}'"
        if [ $? -eq 0 ]; then
	            return 0
	    else
	        setFuncErrorMessage $'\n'"AFX install directory ${afxHome} does not have write permissions for ${afxOwner}."
	        return 1
	    fi
    else
        return 0
    fi
}

checkIntelCPUBug() {
    [ "${DEBUG}" == "TRUE" ] && echo checkIntelCPUBug : $*
    if [ -d /lib64/noelision -a -f /etc/ld.so.conf ] && \
        grep -q '^flags.*\<hle\>' /proc/cpuinfo && \
        ! grep -q '/lib64/noelision' /etc/ld.so.conf; then
        setFuncErrorMessage $'\n''The noelision library path needs to be added to the beginning of the library load path.'
        setFuncErrorMessage $'\n''Refer to RSA Identity G&L Customer Support Knowledgebase (https://rsaportal.force.com/customer/_ui/knowledge/ui/KnowledgeHome) for details.'
        return 1
    else
        return 0
    fi
}

runUserSpaceTests(){
    missingReqArr=()
    getOS

    if ! isVapp; then
        if [ $REMOTE_ORACLE = N ]; then
            # Purpose : check if installed RAM is minimally 4GB and minimally 50MB is free
            runtest checkTotalMemory
        fi

        # Purpose : test whether the expected packages are available on the system
        runtest checkOracleRPMsPreReqs
        runtest checkInstallPackagesPreReqs


        # Purpose : check system has line with "IP FQDN Shortname" syntax line and
        # no other misconfigured lines
        runtest checkEtcHosts
        # Purpose : positive test that a properly configured should pick up FQDN with domain
        # for OS and test successfully
        runtest checkFqdnHasDomainFormat

        # Purpose : check disk/partitions for RSA recommended space availability
        runtest checkMinDiskSizes
    fi

    # Purpose : check to see if oracle user exists
    if [ "$FRESH_INSTALL" = Y ]; then
        runtest checkEntitlementPrereqs passwd "${AVEKSA_OWNER}"
    else
        skiptest checkEntitlementPrereqs passwd "${AVEKSA_OWNER}"
    fi
    # Purpose : check to see if ${AVEKSA_GROUP} group exists
    if [ "$FRESH_INSTALL" = Y ]; then
        runtest checkEntitlementPrereqs group "${AVEKSA_GROUP}"
    else
        skiptest checkEntitlementPrereqs group "${AVEKSA_GROUP}"
    fi
    # Purpose : check to see if oinstall group exists
    if [ "$FRESH_INSTALL" = Y ]; then
        runtest checkEntitlementPrereqs group "${DBA_GROUP}"
    else
        skiptest checkEntitlementPrereqs group "${DBA_GROUP}"
    fi

    if [ $REMOTE_ORACLE = N ]; then
        # Purpose : check to see if ASMKernelDriver is available
        runtest checkASMKernelDriver /opt/appliancePatches/asmlib
        # Purpose : check to see if that user 'oracle' is in groups '${AVEKSA_GROUP}' and '${DBA_GROUP}'
        # and '${AVEKSA_GROUP}' is it's primary group
        groupArray=( "${AVEKSA_GROUP}" "${DBA_GROUP}" )
        runtest checkUserInGroups oracle groupArray[@]
        # Purpose : test whether the system is running at a proper run level - Expected Value:3 or 5
        expectedRunlevels=( "3" "5" )
        runtest checkRunLevel expectedRunlevels[@]
    fi

    # Purpose : test whether the hard limit for "maximum open file descriptors" is set correctly - Expected Value:65536
    runtest checkEtcSecurityLimits oracle hard nofile 65536
    # Purpose : test whether the soft limit for "maximum open file descriptors" is set correctly - Expected Value:1024
    runtest checkEtcSecurityLimits oracle soft nofile 1024
    # Purpose : test whether the hard limit for "maximum user processes" is set correctly - Expected Value:16384
    runtest checkEtcSecurityLimits oracle hard nproc 16384

    # Purpose : test test whether the soft limit for "maximum user processes" is set correctly - Expected Value:16384
    # This limit was raised in 7.1 release from 2047 due to higher thread allocation by WildFly10 and ActiveMQ.
    runtest checkEtcSecurityLimits oracle soft nproc 16384

    # Perform check NTP only for remote Oracle setup
    if ! isVapp && [ $REMOTE_ORACLE = Y ]; then
        # Purpose : test cluster time synchronization on clusters that use Network Time Protocol (NTP)
        runtest checkNtp
    fi


    # Purpose : test the user "oracle" is not part of "root" group
    runtest checkUserNotInGroup ${AVEKSA_OWNER} root
    # Purpose : test the user file creation mask (umask) is "0022"
    runtest checkUMASK "0022"

    if ! isVapp; then
        # Purpose : test consistency of file /etc/resolv.conf file across nodes
        # and
        # Purpose : test the Name Service lookups for the Distributed Name Server (DNS) and the Network Information Service (NIS) match for the SCAN name entries
        runtest checkDNSResolution
    fi

    # Purpose : test the "avahi-daemon" daemon is not configured and running on the cluster nodes
    # not going to check for this
    # Purpose : test /dev/shm is mounted correctly as temporary file system
    runtest checkShmMount
    # Purpose : test /boot is mounted - Expected Value:true (must be skipped on SuSE 12)
    if isSLES12; then
        echo "Skipped running checkBootMount on SuSE 12"
    else
        runtest checkBootMount
    fi
    # Purpose : test OS network parameter NOZEROCONF is set to yes or the parameter LINKLOCAL_INTERFACES is not set in case of SUSE Linux - Expected Value:Parameter LINKLOCAL_INTERFACES is not set
    # Done by runSysctlIndividualTests's call of checkLinkLocalInterfaces
    #Purpose : test if the AFX install directory ${AFX_HOME} has write permissions for ${AFX_OWNER}
    runtest checkAFXPermissions "${AFX_OWNER}" "'${AFX_HOME}'"

    # Purpose : for SLES12, some Intel CPUs can fail due to Intel bug (see https://www.suse.com/support/kb/doc/?id=7022289),
    # so to prevent Oracle Installer failures, we need to use "noelision" libraries:
    if isSLES12; then
        runtest checkIntelCPUBug
    fi

    if [ ${#missingReqArr[@]} -gt 0 ]; then
        echo "-------------------------------------------------------------"
        echo $'\n'"Pre-Requisites Test(s) failed with the following message(s) : "$'\n'
        echo "${funcErrorMessage[*]}"
        echo "-------------------------------------------------------------"
        echo "Quitting installation due to system does not meet requirements"
        if [ -z ${TEST_MODE_ON+x} ]; then TEST_MODE_ON="FALSE"; fi
        if [ ${TEST_MODE_ON} == "TRUE" ]; then
            return 1
        else
            exit 1
        fi
    else
        return 0
    fi
}



case "$1" in
    sysctl)
        runSysctlTests
    ;;
    other)
        runUserSpaceTests
    ;;
    *)
        runSysctlTests
        runUserSpaceTests

    ;;
esac