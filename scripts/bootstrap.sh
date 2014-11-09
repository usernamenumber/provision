#!/bin/bash

PROVREPO=https://github.com/usernamenumber/provision 

# Get the absolute path of the script
cd `dirname $0` > /dev/null
SCRIPTDIR=$(pwd)
SCRIPTNAME="$(basename $0)"
SCRIPTFULLNAME="${SCRIPTDIR}/${SCRIPTNAME}"

# Work backward from the script's location to find
# the git repository root
while [ ! -e "$BASEDIR/.git" ] ; 
do
        BASEDIR="$BASEDIR/.." 
done
cd $BASEDIR 
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
		ping -c1 www.google.com &> /dev/null
		HAS_INTERNET=$?
	fi
	return $HAS_INTERNET
}


function is_installed() {
	[ $# -eq 0 ] && return 2
	which $1 &> /dev/null
	return $?
}

has_internet || note "No net connection found. Some actions will be skipped..." 

is_installed git || apt-get install -y git
if [ ! -e $BASEDIR/provisioning ]
then
	step "Getting provisioning data"
	has_internet || die "Provisioning not installend, and no Internet connection found. Can't do anything"
	git clone $PROVREPO $BASEDIR/provisioning
else
	step "Updating existing provisioning data"
	if ! has_internet
	then 
		note "No Internet connection, skipping update of provisioning data"
	else
		pushd $BASEDIR/provisioning
		git pull	
		popd
	fi
fi 

if [ ! -L $0 ]
	note "Swapping this script for the version in the provisioning repo. The script will now restart."
	ln -sf provisioning/scripts/$SCRIPTNAME $0
	exec $0
fi

if ! grep $SCRIPTFULLNAME /etc/rc.local &>/dev/null 
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

if dpkg -l language-pack-en-base &> /dev/null
then
	step "Installing missing language pack"
	has_internet && apt-get install -y language-pack-en-base
fi

if ! is_installed ansible
then
	step "Getting Ansible"
	has_internet || die "Ansible not installed and no Internet connection found. Can't do anything."

	if [ ! -f /etc/apt/sources.list.d/wheezy-backports.list ] 
	then
		step "Configuring backports repo"
		cat > /etc/apt/sources.list.d/wheezy-backports.list <<EOF
deb http://ftp.debian.org/debian/ wheezy-backports main contrib non-free
deb-src http://ftp.debian.org/debian/ wheezy-backports main contrib non-free
EOF
		apt-get update
	fi

	step "Installing Ansible package"
	apt-get install -y ansible

	step "Setting up a basic Ansible hosts inventory"
	cat >> /etc/ansible/hosts <<EOF
[local]
127.0.0.1
EOF
fi

is_installed ansible || die "Looks like we were unable to install ansible. Maybe a networking problem?"

if [ ! -f ~/.ssh/provisioning ]
then
	step "Generating SSH keys for provisioning"

	# Fun fact: apparently you can't generate a new passwordless key, but you can make
	# it passwordless after creating it.
	# Note the 'from=127.0.0.1' in authorized_keys2. The key can only be used locally.
	ssh-keygen -f ~/.ssh/provisioning -N 1234567890 -q
	ssh-keygen -f ~/.ssh/provisioning -p -P 1234567890 -N '' -q
	echo $(cat ~/.ssh/provisioning.pub) from=127.0.0.1 >> ~/.ssh/authorized_keys2
	chmod go-rwx ~/.ssh/authorized_keys2
fi

step "Loading SSH keys"
eval `ssh-agent -s`
ssh-add ~/.ssh/provisioning
ssh -o StrictHostKeyChecking=no localhost echo 'User key works, host key added!'

[ ! -d $BASEDIR/provisioning ] && die 'Looks like we were unable to check out the provisioning data. Nothing to do now!'

step "Testing Ansible"
export ANSIBLE_HOST_KEY_CHECKING=False
ansible local -m ping

echo ""
echo '*** ALL DONE! ***'
echo ""
