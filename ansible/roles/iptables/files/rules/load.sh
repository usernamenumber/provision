#!/bin/bash

cd `dirname $0` > /dev/null
SCRIPTDIR=$(pwd)
SCRIPTNAME="$(basename $0)"
SCRIPTFULLNAME="${SCRIPTDIR}/${SCRIPTNAME}"
RULESDIR="${SCRIPTDIR}/rules.d"

export IPTABLES="/sbin/iptables"
[ -e $RULESDIR ] || mkdir $RULESDIR
cd $RULESDIR
for s in $(ls)
do
    source $s
done
cd -
