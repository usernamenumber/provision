#!/bin/bash -x

(
# Configs
ATBOOT=false
REPOURL=http://github.com/tunapanda/provision
REPODIR=/usr/local/tunapanda/provision

# Get the absolute path of this script
cd `dirname $0` > /dev/null
SCRIPTDIR=$(pwd)
SCRIPTNAME="$(basename $0)"
SCRIPTFULLNAME="${SCRIPTDIR}/${SCRIPTNAME}"

# Base dir is assumed to be the parent of the git repo
cd ..
BASEDIR=$(pwd)

# Fatal errors
function die() {
	echo ""
	echo "FATAL ERROR: $1" >&2
	echo ""
	exit 1
}

# Notifications and warnings
function note() {
	echo ""
	echo "NOTICE: $1" >&2
	echo ""
}

# Action messages
function step() {
	echo ""
	echo "== $1"
}

function has_internet() {
	if [ -z "$HAS_INTERNET" ]
	then
		step "Checking internet access" 
        if [ -f $SCRIPTDIR/has_internet ] 
        then
            $SCRIPTDIR/has_internet
        else
		    ping -c1 -t5 www.google.com #&> /dev/null
        fi
		HAS_INTERNET=$?
	fi
	return $HAS_INTERNET
}

function is_installed() {
	[ $# -eq 0 ] && return 2
	which $1 &> /dev/null
	return $?
}

if [ $EUID -ne 0 ]
then
	die 'Must be run as root!'
fi

if [ ! -e "$REPODIR" ]
then
    has_internet || die "No provisioning repo and no net connection. Cannot proceed."
    step "Cloning provisioning repo"
    git clone --recursive $REPOURL $REPODIR
fi

if ! has_internet
then 
    note "No Internet connection. Skipping update of provisioning data"
else
    step "Updating provisioning data"
    pushd $REPODIR > /dev/null
    git pull
    popd > /dev/null
fi

if $ATBOOT && ! grep $SCRIPTFULLNAME /etc/rc.local &>/dev/null 
then
	step "Setting the script to run at boot time"
	# This gets messy because Debian Wheezy's rc.local
	# has an explicit call to 'exit 0' at the end, so
	# we can't just append in that case
	( 
		if tail -n1 /etc/rc.local | grep '^exit 0'
		then
			head -n -1 /etc/rc.local
			echo ""
			echo "[ -f $SCRIPTFULLNAME ] && $SCRIPTFULLNAME" 
			echo "exit 0"
		else 
			cat /etc/rc.local
			echo ""
			echo "[ -f $SCRIPTFULLNAME ] && $SCRIPTFULLNAME"  
		fi
	)  > /etc/rc.local
fi

#if dpkg -l language-pack-en-base &> /dev/null
#then
#	step "Installing missing language pack"
#	has_internet && apt-get install -y --force-yes language-pack-en-base
#fi


if ! is_installed pip 
then
	has_internet || die "Pip is required, but we can't install it without a net connection"	
	step "Getting pip"
	if is_installed curl
	then
		curl -o - 'https://bootstrap.pypa.io/get-pip.py' | python
	elif is_installed wget
	then
		wget -o - 'https://bootstrap.pypa.io/get-pip.py' | python
	elif is_installed elinks
	then
		elinks -dump 'https://bootstrap.pypa.io/get-pip.py' | python
	fi

	is_installed pip || die "Can't install pip. See: https://pip.pypa.io/en/latest/installing.html"
fi


if ! is_installed ansible 
then
	step "Installing Ansible"
	has_internet || die "Ansible is required, but we can't install it without a net connection"	
	apt-get install -y python-dev
	pip install ansible
	is_installed ansible || die "Something went wrong installing ansible. Cannot continue."
fi

if has_internet
then
	step "Getting required ansible roles"
#	ansible-galaxy install debops.dhcpd
fi
	
if [ ! -f /root/.ssh/provisioning ]
then
	step "Generating SSH keys for provisioning"

	# Fun fact: apparently you can't generate a new passwordless key, but you can make
	# it passwordless after creating it.
	# Note the 'from=127.0.0.1' in authorized_keys2. This key can only be used locally!
	ssh-keygen -f /root/.ssh/provisioning -N 1234567890 -q
	ssh-keygen -f /root/.ssh/provisioning -p -P 1234567890 -N '' -q
	echo $(cat ~/.ssh/provisioning.pub) from=127.0.0.1 >> ~/.ssh/authorized_keys2
	chmod go-rwx /root/.ssh/authorized_keys2
fi

step "Loading SSH keys"
eval `ssh-agent -s`
ssh-add /root/.ssh/provisioning
ssh-add -l
ssh -i /root/.ssh/provisioning -o StrictHostKeyChecking=no localhost echo 'User key works, host key added!'

step "Running Ansible"
pwd
export ANSIBLE_HOST_KEY_CHECKING=False
ansible-playbook -vvv -i $REPODIR/scripts/bootstrap_inventory.py $REPODIR/ansible/main.yml

echo ""
echo '*** ALL DONE! ***'
echo ""
) | tee /var/log/bootstrap.log
