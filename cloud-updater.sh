#!/usr/bin/env bash  
#
# Automatic updater for any client related to both self-provisioned Openshift and Managed Openshift environments
#
# By Marco Placidi mplacidi@redhat.com
#
# 2022/05/05

# OS Type definition
:; if [ -z 0 ]; then
  @echo off
  goto :WINDOWS
fi

MACORLINUX=$(uname -s|grep Darwin;echo $?)
if [ "${MACORLINUX}" == 0 ];
	then ostype=macos
	ARCH=$(uname -m)
	KERNEL=$(uname -s|tr '[:upper:]' '[:lower:]')
else
	ostype=linux
	ARCH=$(uname -m)
	KERNEL=$(uname -s|tr '[:upper:]' '[:lower:]')
fi


# Global Vars section

## check if there's any Package Manager 

declare -A osInfo;
osInfo[/etc/redhat-release]="rpm -q"
osInfo[/etc/SuSE-release]="zypp search -i"
osInfo[/etc/debian_version]="dpkg -l"

for f in ${!osInfo[@]}
do
    if [[ -f $f ]];then
        PKGMGR=${osInfo[$f]}
    fi
done

## ocm requires a latest release idenfity, otherwise curl won't download a frickin' anything

OCM_VERSION=$(curl -s https://github.com/openshift-online/ocm-cli/releases/latest -L|grep -Eo Release\ [0-9].[0-9].[0-9]{2}|sed 's/<[^>]*>//g;s/Release\ /v/g'|uniq)


# Client Array section

declare -A CLIENT_URLS_ARRAY
CLIENT_URLS_ARRAY[oc]="https://mirror.openshift.com/pub/openshift-v4/${ARCH}/clients/ocp/stable/openshift-client-${KERNEL}.tar.gz"
CLIENT_URLS_ARRAY[ocm]="https://github.com/openshift-online/ocm-cli/releases/download/${OCM_VERSION}/ocm-${KERNEL}-amd64"
CLIENT_URLS_ARRAY[tkn]="https://mirror.openshift.com/pub/openshift-v4/clients/pipelines/latest/tkn-${KERNEL}-amd64.tar.gz"
CLIENT_URLS_ARRAY[kn]="https://mirror.openshift.com/pub/openshift-v4/clients/serverless/latest/kn-${KERNEL}-amd64.tar.gz"
CLIENT_URLS_ARRAY[rosa]="https://mirror.openshift.com/pub/openshift-v4/clients/rosa/latest/rosa-${KERNEL}.tar.gz"
CLIENT_URLS_ARRAY[helm]="https://mirror.openshift.com/pub/openshift-v4/clients/helm/latest/helm-${KERNEL}-amd64.tar.gz"
CLIENT_URLS_ARRAY[az]="https://azurecliprod.blob.core.windows.net/install.py"
CLIENT_URLS_ARRAY[aws]="https://awscli.amazonaws.com/awscli-exe-${KERNEL}-${ARCH}.zip"

# Functions definitions
# Cleanup step

clean_up () {

echo -n "cleaning up..." && rm -rf ${TMPDIR} && echo "..done."
echo "Bye!"

}

print_help () {
   # Display Help
   echo "Managed Cloud Client download/update tool"
   echo
   echo "option capability has been implemented for future improvements"
   echo "Syntax: cloud_updater.sh [|-h/--help] -c $client"
   echo "options:"
   echo "-h/--help      Print this Help."
   echo "-d/--debug	Enables set -x, for debug"
   echo "-c $client Updates client at your choice between [rosa|ocm|tkn|kn|helm|oc|az|all]."
   echo "-l/--log	Enables logging so you can check all the details after installation"
   echo
}

print_sudo_disclaimer () {
	while true;
	do
		echo "Please verify that you have write permissions on the destination directory or if you have sudo privileges"
		read -p "$* [y/n]: " yn
		case $yn in
			[Yy]*) return 0 ;;
			[nN]*) echo "Aborted, exiting..." ; exit 1 ;;
		esac
	done
}

linux_client_check_n_update () {
        # Defining client url for download from array
        export CLIENT_URL=${CLIENT_URLS_ARRAY[$client]}
        # Defining client binary filename
        export CLIENT_FILENAME=$(basename $CLIENT_URL)
        # Defines a working directory under /tmp and defines current path
        export TMPDIR=/tmp/${client}_cli_update_$(date +%Y.%m.%d-%H.%M.%S)

        # Define if client already exists, otherwise user choose a destination
        CLIENT_CHECK=$(which ${client} 2>/dev/null)
        if [ -z ${CLIENT_CHECK} ];
                then read -p "Please enter the full path in which you desire to install the ${client} binary: " CLIENT_CHECK
        fi

        # Defines client basepath variable based upon previous cmd
        CLIENT_LOC=$(echo ${CLIENT_CHECK}|sed 's/\/'''${client}'''//g')

        # Determines if curl and/or wget are installed and then downloads the newest $client
        CURL_CHECK=$(curl --help 2>&1 > /dev/null && echo OK || echo NO)

        if [ "$CURL_CHECK" == "OK" ];
                then export URL_TOOL="$(which curl) -sO"
        else
                echo "Curl is needed in order to make this script functioning properly"; exit 1
        fi
        echo -n "Downloading latest $client client...";
        if [ "$client" == "ocm" ];
                then $URL_TOOL $CLIENT_URL -L --create-dirs --output-dir ${TMPDIR} && echo "..done."
        else
                $URL_TOOL $CLIENT_URL -L --create-dirs --output-dir ${TMPDIR} && echo "..done." 
        fi
        if [ "$?" != "0" ];then echo "Cannot download anything, please verify your network configuration.";
        fi

        # If $client already exists, check local version vs. downloaded version, exits and cleans up in case of already downloaded latest version
        echo "Checking if $client already installed"
        CLIENT_EXISTS=$(which $client 2>&1 >/dev/null && echo OK || echo NO)
        # Checking if the user running the script has write permissions on existing client file
        [[ -w "$client" ]] && export SUDO="${SUDO}" || export SUDO=$(which sudo)

        if [ "$CLIENT_EXISTS" == "OK" ];
                then echo "$client already installed in your system" "now checking downloaded version vs. installed version md5 checksums";
                        if [ "$client" == "ocm" ];
                                then export CLIENT_MD5=$(md5sum ${TMPDIR}/${CLIENT_FILENAME} |grep -A1 $client|tail -n1|sed -E 's/\s.+$//g')
                        elif [[ "$client" == "az" || "$client" == "aws" ]];
                                then echo "Check cannot be implemented for azure-cli/aws-cli, the script will invoke an installer that'll lets you install/update the binary"
                        else
                                export CLIENT_MD5=$(tar xvfz ${TMPDIR}/${CLIENT_FILENAME} --to-command=md5sum|grep -A1 $client|tail -n1|sed -E 's/\s.+$//g')
                        fi
        export LOCAL_CLIENT_MD5=$(md5sum $CLIENT_CHECK|sed -E 's/\s.+$//g')
                if [ "${CLIENT_MD5}" == "${LOCAL_CLIENT_MD5}" ];
                        then echo "Already downloaded $client client with md5sum ${LOCAL_CLIENT_MD5}";
                elif [[ "$client" == "az" ]];
                        then echo "Check cannot be implemented for azure-cli, the script will overwrite your current installation most likely"
                                if [[ ! -z "$PKGMGR" ]];
                                        then $PKGMGR azure-cli && sudo dnf update azure-cli || sudo apt-get install --only-upgrade azure-cli || sudo zypper update azure-cli
                                else
                                        PYTHONCMD=$(which python3)||$(which pyhton)
                                        if [ -z $PYTHONCMD ];then echo "Python is required to proceed with azure-cli installation, exiting program..";exit 2;fi
                                                $PYTHONCMD <(curl -s https://azurecliprod.blob.core.windows.net/install.py)
                                        fi
                elif [[ "$client" == "aws" ]];
                        then curl -s "https://awscli.amazonaws.com/awscli-exe-${KERNEL}-${ARCH}.zip" -o "${TMPDIR}/awscliv2.zip" && unzip -qq -o ${TMPDIR}/awscliv2.zip -d ${TMPDIR}
                        [ -z $(which aws) ] && sudo ${TMPDIR}/aws/install || sudo ${TMPDIR}/aws/install --update
                elif [[ "${client}" == "ocm" ]];
                        then cp ${TMPDIR}/$CLIENT_FILENAME $CLIENT_LOC/$client
                else
                    # Untar and copy/overwrite to CLIENT_LOC
                        [[ "$CLIENT_FILENAME" == \.gz$ && "$client" != "az" && "$client" != "aws" && -w "${CLIENT_CHECK}" ]] && echo "Now unTar-ing $client client into $CLIENT_LOC" && $SUDO tar xvzf ${TMPDIR}/${CLIENT_FILENAME} -C $CLIENT_LOC --overwrite && echo "$client client installed/updated in $CLIENT_LOC"
                                fi
                fi
		$LOGENABLED
}

     
macos_client_check_n_update () {
echo NOT YET
}


# Parameters section
for param in "$@"
	do
		if [ "$param" == "--help" ] || [ "$param" == "-h" ];
			then print_help; exit 2
		elif [ "$param" == "--debug" ] || [ "$param" == "-d" ];
			then set -x;
		elif [ "$param" == "--log" ] || [ "$param" == "-l" ];
			export LOGFILE="/tmp/cloud-updater_$(date +%Y.%m.%d-%H.%M.%S).log"
			then export LOGENABLED="2>&1| tee -a ${LOGFILE}"
		fi
done

# Client choice
while getopts c: option
do
	case "${option}"
		in
		c)client=${OPTARG};;
	esac
done

print_sudo_disclaimer

# ALL IN!
#touch ${LOGFILE} 
if [ "$client" == "all" ];
	then declare -a CLIENT_ARRAY=(oc ocm tkn kn helm rosa aws az)
else CLIENT_ARRAY=$client # this makes it working in Singular client update
	declare -a CLIENT_VALUES=(oc ocm tkn kn helm rosa aws az)
	declare -A KEY
	for key in "${!CLIENT_VALUES[@]}"; do KEY[${CLIENT_VALUES[$key]}]="$key";done
	[[ ! -n "${KEY[$client]}" ]] && printf '%s is not a valid client value\n' "$client" && exit 2
fi

for client in "${CLIENT_ARRAY[@]}"
  do
     # Singular client update
     if [ -z "$client" ]
     	then read -p "Please input one of the following [rosa|ocm|tkn|kn|helm|oc|az]: " client	
     fi

     ${ostype}_client_check_n_update 
     # Clean up function call
     clean_up
done
exit
:WINDOWS
