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

LOG_FILE="/tmp/bootstrap-cloudera1.out"

echo "arguments values passed..." >> ${LOG_FILE}
echo "IPPREFIX" >> ${LOG_FILE}
echo "$IPPREFIX" >> ${LOG_FILE}
echo "NAMEPREFIX" >> ${LOG_FILE}
echo "$NAMEPREFIX" >> ${LOG_FILE}
echo "NAMESUFFIX" >> ${LOG_FILE}
echo "$NAMESUFFIX" >> ${LOG_FILE}
echo "MASTERNODES" >> ${LOG_FILE}
echo "$MASTERNODES" >> ${LOG_FILE}
echo "DATANODES" >> ${LOG_FILE}
echo "$DATANODES" >> ${LOG_FILE}
echo "ADMINUSER" >> ${LOG_FILE}
echo "$ADMINUSER" >> ${LOG_FILE}
echo "HA" >> ${LOG_FILE}
echo "$HA" >> ${LOG_FILE}
echo "PASSWORD" >> ${LOG_FILE}
echo "$PASSWORD" >> ${LOG_FILE}
echo "CMUSER" >> ${LOG_FILE}
echo "$CMUSER" >> ${LOG_FILE}
echo "CMPASSWORD" >> ${LOG_FILE}
echo "$CMPASSWORD" >> ${LOG_FILE}
echo "INSTALLCDH" >> ${LOG_FILE}
echo "$INSTALLCDH" >> ${LOG_FILE}

echo "dash dash/sh boolean false" | debconf-set-selections
DEBIAN_FRONTEND=noninteractive dpkg-reconfigure dash
cat /etc/resolv.conf >> ${LOG_FILE}
debconf-show dash >> ${LOG_FILE}

CLUSTERNAME=${NAMEPREFIX}
NAMESUFFIX=$(echo $NAMESUFFIX | sed "s/^[^.]*\.//")

# Necessary for adding these hosts to Cloudera's internal DNS
CLOUDERA_DNS_IP="10.17.181.104"
CLOUDERA_DOMAIN="azure.cloudera.com"

BOOTSTRAP_LOG="/tmp/bootstrap.out"

execname=$0
log() {
  echo "$(date): [${execname}] $@" 
}

addPrivateIpToNodes() {

  sleep 45s
  publicHostname=${1}
  isMasterNode=${2}
  echo "in addprivate IP Publichostname" >> ${LOG_FILE}
  echo "$publicHostname" >> ${LOG_FILE}
  echo "content of ifconfig for this machine" >> ${LOG_FILE}
  ifconfig >> ${LOG_FILE}

  if [[ "${2}" = "true" ]]; then
    ext="mn"
  else
    ext="dn"
  fi

  echo "ifconfig details:" >> ${LOG_FILE}
  s=$(ssh -o "StrictHostKeyChecking=false" -i /home/systest/.ssh/id_rsa systest@"${publicHostname}" -x 'ls -al')
  echo "$s"  >> ${LOG_FILE}
  privateIp=$(ssh -o "StrictHostKeyChecking=false" -i /home/systest/.ssh/id_rsa systest@"${publicHostname}" -x 'sudo ifconfig | grep inet | awk "{ print \$2 }" | grep "addr:1" | grep -v "127.0.0.1" | sed "s^addr:^^g"')
  echo "PrivateIP" >> ${LOG_FILE}
  echo "$privateIp" >> ${LOG_FILE}
  echo "${publicHostname} : ${privateIp}" >> /tmp/privateIps
  if [[ "${privateIp}" = "" ]]; then
    echo "Could not get a privateIp from one of the master nodes. Waiting and then trying" >> ${BOOTSTRAP_LOG}
    sleep 25s
    privateIp=$(ssh -o "StrictHostKeyChecking=false" -i /home/systest/.ssh/id_rsa systest@"${publicHostname}" -x 'sudo ifconfig | grep inet | cut -d" " -f 12 | grep "addr:1" | grep -v "127.0.0.1" | sed "s^addr:^^g"')
    echo "Second attempt at private ip for ${publicHostname} produced: ${privateIp}" >> ${BOOTSTRAP_LOG}
  fi
  echo "Adding to nodes: \"${privateIp}:${NAMEPREFIX}-${ext}${i}.${CLOUDERA_DOMAIN}:${NAMEPREFIX}-${ext}${i} \" >> ${BOOTSTRAP_LOG}"
  NODES+=("${privateIp}:${NAMEPREFIX}-${ext}$i.${CLOUDERA_DOMAIN}:${NAMEPREFIX}-${ext}$i")
}

#Generate IP Addresses for the cloudera setup
NODES=()

# Go to each node, get the private ip, and save it locally
let "NAMEEND=MASTERNODES-1" || true
for i in $(seq 0 $NAMEEND)
do
  publicHostname=${NAMEPREFIX}-mn$i.${NAMESUFFIX}
  echo "PublicHostName" >> ${LOG_FILE}
  echo "$publicHostname" >> ${LOG_FILE}
  echo "publicHostname is: ${publicHostname}" >> /tmp/publicHostNames
  addPrivateIpToNodes "${publicHostname}" true
done

let "DATAEND=DATANODES-1" || true
for i in $(seq 0 $DATAEND)
do
  publicHostname=${NAMEPREFIX}-dn$i.${NAMESUFFIX}
  echo "PublicHostName" >> ${LOG_FILE}
  echo "$publicHostname" >> ${LOG_FILE}
  echo "publicHostname is: ${publicHostname}" >> /tmp/publicHostNames
  addPrivateIpToNodes "${publicHostname}" false
done

# Take the value from NODES and put it into /etc/hosts
OIFS=$IFS
IFS=',';NODE_IPS="${NODES[*]}";IFS=$' \t\n'

IFS=','
for x in $NODE_IPS
do
  echo "x as member of NODE_IPS is: $x" >> ${BOOTSTRAP_LOG}
  line=$(echo "$x" | sed 's/:/ /' | sed 's/:/ /')
  echo "${line} as member of NODE_IPS is: $x" >> ${BOOTSTRAP_LOG}
  echo "${line}" >> /etc/hosts
done
IFS=${OIFS}

# As a final act, we're going to go to each node in /etc/hosts and adjust /etc/hosts and the /etc/resolv.conf
echo "About to adjust /etc/resolv.conf on all hosts, including this one" >> ${BOOTSTRAP_LOG}
# not needed for ubuntu
#sed -i "s^PEERDNS=yes^PEERDNS=no^g" /etc/sysconfig/network-scripts/ifcfg-eth0

# First do it on the local machine
#sudo echo 'nameserver 172.18.64.15' > /etc/resolv.conf
#sudo service network restart
#sleep 25

# Then set resolv.conf on the others
while read p;
do
  host=$(echo "${p}" | grep "azure" | grep -v 'localhost' | grep -v "mn0" | cut -d' ' -f 1)

  if [[ "${host}" = "" ]]; then
    echo "host empty for line $p. continuing" >> ${BOOTSTRAP_LOG}
    continue
  fi

  echo "host: ${host}" >> ${BOOTSTRAP_LOG}
  scp -o "StrictHostKeyChecking=false" -i .ssh/id_rsa /etc/hosts "${ADMINUSER}@${host}":"/home/${ADMINUSER}/hosts"
  echo "done scping to host: ${host}" >> ${BOOTSTRAP_LOG}

  ssh -n -o "StrictHostKeyChecking=false" -i .ssh/id_rsa systest@"${host}" -x "sudo cp /home/${ADMINUSER}/hosts /etc/hosts; sudo chown root /etc/hosts; sudo chmod 644 /etc/hosts"
  echo "done setting /etc/hosts on host: ${host}" >> ${BOOTSTRAP_LOG}

  # set /etc/resolv.conf
  # ssh -n -o "StrictHostKeyChecking=false" -i .ssh/id_rsa systest@"${host}" -x "sudo echo 'nameserver 172.18.64.15' | sudo tee /etc/resolv.conf; sudo sed -i 's^PEERDNS=yes^PEERDNS=no^g' /etc/sysconfig/network-scripts/ifcfg-eth0; sudo service network restart;"
  # echo "done with long command on /etc/hosts on host: ${host}" >> ${BOOTSTRAP_LOG}

done < /etc/hosts
sleep 30s
echo "Done adjusting /etc/resolv.conf on all hosts" >> ${BOOTSTRAP_LOG}

while read p;
do
  # establish properties necessary to register with DNS
  ip=$(echo "${p}" | grep "azure" | grep -v 'localhost' | cut -d' ' -f 1)
  fqdn=$(echo "${p}" | grep "azure" | grep -v 'localhost' | cut -d' ' -f 2)
  shortname=$(echo "${p}" | grep "azure" | grep -v 'localhost' | cut -d' ' -f 3)

  if [[ "${fqdn}" = "" ]]; then
    echo "host empty for line $p. continuing" >> /tmp/settingPrivateHostnames.out
    continue
  fi

  echo "About to associate ${shortname}.${NAMESUFFIX} to ip ${ip} on domain ${CLOUDERA_DOMAIN}."
  ssh -n -o "StrictHostKeyChecking=no" -i .ssh/id_rsa systest@"${CLOUDERA_DNS_IP}" -x "./bin/update_dns_multi ${shortname}.${CLOUDERA_DOMAIN} ${ip} ${CLOUDERA_DOMAIN}"
done < /etc/hosts

if [ "${INSTALLCDH}" == "True" ]
then

  # This key should have been set by initialize-node.sh
  key="/home/${ADMINUSER}/.ssh/id_rsa"

  ### Assume /etc/hosts is correct and set
  # Get management node
  mip=$(while read p; do echo "${p}" | grep "azure" | grep -v local | grep "\-mn0" | cut -d' ' -f 1 ; done < /etc/hosts)

  # Get non-CM nodes
  wip_string=''
  while read p; do
    if [[ "$wip_string" != "" ]]; then
      wip_string+=','
    fi
    wip_string+=$(echo "${p}" | grep "azure" | grep -v local | grep -v "\-mn0" | cut -d' ' -f 1 );
  done < /etc/hosts

  sh initialize-cloudera-server.sh "${CLUSTERNAME}" "${key}" "${mip}" "${wip_string}" "${HA}" "${ADMINUSER}" "${PASSWORD}" "${CMUSER}" "${CMPASSWORD}" "${EMAILADDRESS}" "${BUSINESSPHONE}" "${FIRSTNAME}" "${LASTNAME}" "${JOBROLE}" "${JOBFUNCTION}" "${COMPANY}" >/dev/null 2>&1
fi
log "END: Detached script to finalize initialization running. PID: $!"
