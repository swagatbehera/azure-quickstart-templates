#!/bin/bash
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#   http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# 
# See the License for the specific language governing permissions and
# limitations under the License.
# Usage: bootstrap-cloudera-1.0.sh {clusterName} {managment_node} {cluster_nodes} {isHA} {sshUserName} [{sshPassword}]

# Put the command line parameters into named variables
IPPREFIX=$1
NAMEPREFIX=$2
NAMESUFFIX=$3
MASTERNODES=$4
DATANODES=$5
ADMINUSER=$6
HA=$7
PASSWORD=$8
CMUSER=$9
CMPASSWORD=${10}
EMAILADDRESS=${11}
BUSINESSPHONE=${12}
FIRSTNAME=${13}
LASTNAME=${14}
JOBROLE=${15}
JOBFUNCTION=${16}
COMPANY=${17}
INSTALLCDH=${18}

CLUSTERNAME=$NAMEPREFIX

execname=$0

log() {
  echo "$(date): [${execname}] $@" 
}

# Converts a domain like machine.domain.com to domain.com by removing the machine name
NAMESUFFIX=`echo $NAMESUFFIX | sed 's/^[^.]*\.//'`

### Assume /etc/hosts is correct and set
# Get management node
mip=$(while read p; do echo $p | grep "azure" | grep -v local | grep "\-mn0" | cut -d' ' -f 1 ; done < /etc/hosts)

# Get non-CM nodes
wip_string=''
while read p; do

  if [[ "$wip_string" != "" ]]; then

    wip_string+=','
  fi
  wip_string+=$(echo $p | grep "azure" | grep -v local | grep -v "\-mn0" | cut -d' ' -f 1 );
done < /etc/hosts

log "mip: $mip"
log "wip: $wip_string"

log "set private key"
#use the key from the key vault as the SSH private key
#openssl rsa -in /var/lib/waagent/*.prv -out /home/$ADMINUSER/.ssh/id_rsa
#chmod 600 /home/$ADMINUSER/.ssh/id_rsa
#chown $ADMINUSER /home/$ADMINUSER/.ssh/id_rsa

#file="/home/$ADMINUSER/.ssh/id_rsa"
#key="/tmp/id_rsa.pem"
#openssl rsa -in $file -outform PEM > $key

key="/home/${ADMINUSER}/.ssh/id_rsa"

if [ "$INSTALLCDH" == "True" ]
then
  sh initialize-cloudera-server.sh "$CLUSTERNAME" "$key" "$mip" "$wip_string" $HA $ADMINUSER $PASSWORD $CMUSER $CMPASSWORD $EMAILADDRESS $BUSINESSPHONE $FIRSTNAME $LASTNAME $JOBROLE $JOBFUNCTION $COMPANY>/dev/null 2>&1
fi
log "END: Detached script to finalize initialization running. PID: $!"

