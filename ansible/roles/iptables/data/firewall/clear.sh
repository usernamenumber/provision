#!/bin/bash

IPTABLES=/sbin/iptables

for chain in PREROUTING POSTROUTING INPUT OUTPUT FORWARD
do
	iptables -P $chain ACCEPT 
done

iptables -F
