#!/bin/bash -x

# Configs
BASE_DIR="/usr/local/tunapanda"
PROVISION_REPO="http://github.com/tunapanda/provision"
PROVISION_VERSION="bootstrap"
PROVISION_DIR="${BASE_DIR}/provision"
INVENTORY="${PROVISION_DIR}/scripts/bootstrap_inventory.py"
BOOTSTRAP_PLAYBOOK="${PROVISION_DIR}/ansible/bootstrap.yml"
BOOTSTRAP_PLAYBOOK_URL="https://raw.githubusercontent.com/tunapanda/provision/master/ansible/bootstrap.yml"
EDX_REPO="https://github.com/edx/configuration"
EDX_VERSION="aspen.1"
EDX_DIR="${BASE_DIR}/edx/configuration"

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
        if [ -f $PROVISION_DIR/scripts/has_internet ] 
        then
            $PROVISION_DIR/scripts/has_internet
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

function get_url() {
	if is_installed curl
	then
		curl -o - "$1" 
	elif is_installed wget
	then
		wget -O - "$1"
	elif is_installed elinks
	then
		elinks -dump "$1"
	else
		die "Cannot retrieve urls. Please install curl, wget, or elinks"
	fi
}

if [ $EUID -ne 0 ]
then
	die 'Must be run as root!'
fi

if has_internet
then
	apt-get update
fi

if ! is_installed pip 
then
	has_internet || die "Pip is required, but we can't install it without a net connection"	
	step "Installing pip dependencies"
	apt-get install -y python-dev 
	step "Getting pip"
	get_url 'https://bootstrap.pypa.io/get-pip.py' | python
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

# Can't find repo. Probably a fresh install, so download the bootstrap playbook
if [ ! -e "$BOOTSTRAP_PLAYBOOK" ]
then
	has_internet || die "Can't find repo, but no net access, so can't retrieve it either"
	RAND=$RANDOM
	BOOTSTRAP_PLAYBOOK="/tmp/${RAND}bootstrap.yml"
	BOOTSTRAP_INVENTORY="/tmp/${RAND}inventory.ini"
	step "Provisioning repo not found. Downloading bootstrap playbook"
	get_url $BOOTSTRAP_PLAYBOOK_URL > $BOOSTRAP_PLAYBOOK
	cat > $BOOTSTRAP_INVENTORY <<EOF
[localhost]
127.0.0.1
EOF
else
	BOOTSTRAP_INVENTORY=$INVENTORY
fi

export ANSIBLE_HOST_KEY_CHECKING=False
# Clone/update the other repos
step "Running bootstrap playbook"
ansible-playbook -vvvv -i $BOOTSTRAP_INVENTORY $BOOTSTRAP_PLAYBOOK | die "Could not retrieve provisioning repos"

step "Running edX playbook"
pushd ${EDX_DIR}/playbooks/ > /dev/null
ansible-playbook -vvv -i $REPODIR/scripts/bootstrap_inventory.py edx_sandbox.yml
popd > /dev/null

step "Running core playbook"
pushd ${PROVISION_DIR}/ansible/ > /dev/null
#ansible-playbook -vvv -i $REPODIR/scripts/bootstrap_inventory.py $REPODIR/ansible/main.yml
popd > /dev/null

echo ""
echo '*** ALL DONE! ***'
echo ""

