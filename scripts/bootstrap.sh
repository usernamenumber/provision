#!/bin/bash -x

# Configs
## TODO: Change usernamenumber URLs back to tunapanda
BASE_DIR="/usr/local/tunapanda"
PROVISION_REPO="http://github.com/usernamenumber/provision"
PROVISION_VERSION="bootstrap"
PROVISION_DIR="${BASE_DIR}/provision"
INVENTORY="${PROVISION_DIR}/scripts/bootstrap_inventory.py"
BOOTSTRAP_PLAYBOOK="${PROVISION_DIR}/ansible/bootstrap.yml"
BOOTSTRAP_PLAYBOOK_URL="https://raw.githubusercontent.com/usernamenumber/provision/${PROVISION_VERSION}/ansible/bootstrap.yml"
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
		    ping -c1 -w5 www.google.com #&> /dev/null
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

# Update packages if the haven't been updated in the last 12 hours
if has_internet && [ $[ $(date +%s) - $(date -r /var/lib/apt/lists/ +%s) ] -gt $[ 60 * 60 * 12 ] ] 
then
	step "Updating package list"
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

if ! is_installed sshd 
then
	step "Installing ssh server"
	has_internet || die "An ssh server is required, but we can't install it without a net connection"	
	apt-get install -y openssh-server 
	is_installed sshd || die "Something when wrong installing the ssh server. Cannot continue."
fi

if ! is_installed ansible 
then
	step "Installing Ansible"
	has_internet || die "Ansible is required, but we can't install it without a net connection"	
	apt-get install -y python-dev
	pip install --upgrade 'ansible>=1.6'
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
	BOOTSTRAP_DIR="/tmp/${RAND}"
	BOOTSTRAP_PLAYBOOK="bootstrap.yml"
	BOOTSTRAP_INVENTORY="inventory.ini"
	step "Provisioning repo not found. Downloading bootstrap playbook"
	get_url $BOOTSTRAP_PLAYBOOK_URL > $BOOTSTRAP_PLAYBOOK
	cat > $BOOTSTRAP_INVENTORY <<EOF
[localhost]
127.0.0.1
EOF
else
	BOOTSTRAP_DIR="${PROVISION_DIR}/ansible"
	BOOTSTRAP_PLAYBOOK="bootstrap.yml"
	BOOTSTRAP_INVENTORY=$INVENTORY
fi

export ANSIBLE_HOST_KEY_CHECKING=False
# Clone/update the other repos
step "Running bootstrap playbook"
pushd ${BOOTSTRAP_DIR} > /dev/null
ansible-playbook -vvvv -i $BOOTSTRAP_INVENTORY $BOOTSTRAP_PLAYBOOK || die "Could not run bootstrap playbook"
popd > /dev/null

step "Running edX playbook"
pushd ${EDX_DIR}/playbooks/ > /dev/null
#ansible-playbook -vvv -i $EDX_DIR/scripts/bootstrap_inventory.py edx_sandbox.yml || die "Could not run edx playbook"
popd > /dev/null

step "Running core playbook"
pushd ${PROVISION_DIR}/ansible/ > /dev/null
ansible-playbook -vvv -i $PROVISION_DIR/scripts/bootstrap_inventory.py main.yml || die "Could not run core playbook"
popd > /dev/null

echo ""
echo '*** ALL DONE! ***'
echo ""

