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

echo "initializing nodes..."
IPPREFIX=$1
NAMEPREFIX=$2
NAMESUFFIX=$3
MASTERNODES=$4
DATANODES=$5
ADMINUSER=$6
NODETYPE=$7


#ADJUSTED_NAME_SUFFIX=`echo $NAMESUFFIX | sed 's/^[^.]*\.//'`
#echo "ADJUSTED_NAME_SUFFIX is ${ADJUSTED_NAME_SUFFIX}" >> /tmp/initlog.out

##Generate IP Addresses for the cloudera setup
#NODES=()

#let "NAMEEND=MASTERNODES-1" || true
#for i in $(seq 0 $NAMEEND)
#do
#  x=${NAMEPREFIX}-mn$i.${ADJUSTED_NAME_SUFFIX}
#  echo "x is: $x" >> /tmp/masternodes
#  privateIp=$(ssh -i ./id_rsa -o "StrictHostKeyChecking=false" systest@${x} -x 'sudo ifconfig | grep inet | cut -d" " -f 12 | grep "addr:1" | grep -v "127.0.0.1" | sed "s^addr:^^g"')
#  echo "$x : ${privateIp}" >> /tmp/privateMasterIps
#  echo "Adding to nodes: "${privateIp}:${NAMEPREFIX}-mn${i}.${ADJUSTED_NAME_SUFFIX}:${NAMEPREFIX}-mn${i} " >> /tmp/initlog.out"

#  NODES+=("${privateIp}:${NAMEPREFIX}-mn$i.${ADJUSTED_NAME_SUFFIX}:${NAMEPREFIX}-mn$i")
#done

#echo "finished nn private ip discovery >> /tmp/initlog.out"

#let "DATAEND=DATANODES-1" || true
#for i in $(seq 0 $DATAEND)
#do
#  x=${NAMEPREFIX}-dn$i.${ADJUSTED_NAME_SUFFIX}
#  echo "x is: $x" >> /tmp/datanodes
#  privateIp=$(ssh -o "StrictHostKeyChecking=false" systest@$x -x 'ifconfig | grep inet | cut -d" " -f 12 | grep "addr:1" | grep -v "127.0.0.1" | sed "s^addr:^^g"')
#  echo $privateIp >> /tmp/privateDataIps
#  echo "Adding to nodes: "${privateIp}:${NAMEPREFIX}-dn$i.${ADJUSTED_NAME_SUFFIX}:${NAMEPREFIX}-dn$i " >> /tmp/initlog.out"
#  NODES+=("${privateIp}:${NAMEPREFIX}-dn$i.${ADJUSTED_NAME_SUFFIX}:${NAMEPREFIX}-dn$i")
#done

#echo "finished dn private ip discovery >> /tmp/initlog.out"

## Converts a domain like machine.domain.com to domain.com by removing the machine name
#NAMESUFFIX=`echo $NAMESUFFIX | sed 's/^[^.]*\.//'`

#OIFS=$IFS
#IFS=',';NODE_IPS="${NODES[*]}";IFS=$' \t\n'

#IFS=','
#for x in $NODE_IPS
#do
#  echo "x as member of NODE_IPS is: $x" >> /tmp/initlog.out
#  line=$(echo "$x" | sed 's/:/ /' | sed 's/:/ /')
#  echo "$line" >> /etc/hosts
#done
#IFS=${OIFS}

# Disable the need for a tty when running sudo and allow passwordless sudo for the admin user
sed -i '/Defaults[[:space:]]\+!*requiretty/s/^/#/' /etc/sudoers
echo "$ADMINUSER ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# we are going to do something heinous here to pull down the key
# we are going to swap out the /etc/resolv.conf file

echo "Running as `whoami` in `pwd`" >> /tmp/diagnostics.out
echo "Perms on this directory are `ls -la .`" >> /tmp/diagnostics.out

ls -la ~/.ssh
if [[ "$?" != "0" ]]; then

  echo "~/.ssh does not exist. We are right in making this folder" >> /tmp/diagnostics.out
else
  echo "~/.ssh already exists. We should not be re-making this folder" >> /tmp/diagnostics.out
fi

sudo mkdir -p ~/.ssh
echo "status of making home dir was was $?" >> /tmp/diagnostics.out
sudo chown $(whomai) ~/.ssh
sudo chmod 700 ~/.ssh

cp /etc/resolv.conf /tmp/old_resolv.conf
sudo echo "nameserver 172.18.64.15" > /etc/resolv.conf
sleep 10s
cat /etc/resolv.conf >> /tmp/diagnostics.out

# set the configuration to not reset /etc/resolv.conf when we restart networking
sed -i "s^PEERDNS=yes^PEERDNS=no^g" /etc/sysconfig/network-scripts/ifcfg-eth0
service network restart
sleep 25s
wget --no-dns-cache http://github.mtv.cloudera.com/raw/QE/smokes/cdh5/common/src/main/resources/systest/id_rsa
statusCode=$?
if [[ "statusCode?" != 0 ]]; then
  echo "pulling down file failed with code $statusCode" >> /tmp/diagnostics.out
  wget --no-dns-cache http://github.mtv.cloudera.com/raw/QE/smokes/cdh5/common/src/main/resources/systest/id_rsa >> /tmp/diagnostics.out
  wget --no-dns-cache http://github.mtv.cloudera.com/raw/QE/smokes/cdh5/common/src/main/resources/systest/id_rsa 2>> /tmp/diagnostics.out

  # let's diagnose if it's a resolution issue
  host -v github.mtv.cloudera.com
  if [[ "$?" != "0" ]]; then
    echo "We could not resolve the host"  >> /tmp/diagnostics.out
  else
    echo "Host resolution was fine, actually"  >> /tmp/diagnostics.out
  fi
  
  wget --no-dns-cache http://github.mtv.cloudera.com/raw/QE/smokes/cdh5/common/src/main/resources/systest/id_rsa
fi

chmod 600 ./id_rsa
cp ./id_rsa /tmp/systest_key
cp ./id_rsa ~/.ssh/

cp /tmp/old_resolv.conf /etc/resolv.conf
sed -i "s^PEERDNS=no^PEERDNS=yes^g" /etc/sysconfig/network-scripts/ifcfg-eth0
service network restart
sleep 25s

## end of hack

echo "here is the ~/.ssh/ directory" >> /tmp/ssh_diagnosis.out
ls -la ~/.ssh/ >> /tmp/ssh_diagnosis.out
echo "done listing the ~/.ssh/ directory" >> /tmp/ssh_diagnosis.out

# Mount and format the attached disks base on node type
if [ "$NODETYPE" == "masternode" ]
then
  echo "preparing master node" >> /tmp/ssh_diagnosis.out
  bash ./prepare-masternode-disks.sh
  echo "preparing master node exited with code $?" >> /tmp/ssh_diagnosis.out
  
elif [ "$NODETYPE" == "datanode" ]
then
  echo "preparing data node" >> /tmp/ssh_diagnosis.out
  bash ./prepare-datanode-disks.sh
  echo "preparing data node exited with code $?" >> /tmp/ssh_diagnosis.out
else
  echo "#unknown type, default to datanode"
  bash ./prepare-datanode-disks.sh
fi

echo "Done preparing disks.  Now ls -la looks like this:" >> /tmp/ssh_diagnosis.out
ls -la / >> /tmp/ssh_diagnosis.out
# Create Impala scratch directory
numDataDirs=$(ls -la / | grep data | wc -l)
echo "numDataDirs:" $numDataDirs >> /tmp/ssh_diagnosis.out
let endLoopIter=(numDataDirs - 1)
for x in $(seq 0 $endLoopIter)
do 
  echo mkdir -p /data${x}/impala/scratch 
  mkdir -p /data${x}/impala/scratch
  chmod 777 /data${x}/impala/scratch
done

setenforce 0 >> /tmp/setenforce.out
cat /etc/selinux/config > /tmp/beforeSelinux.out
sed -i 's^SELINUX=enforcing^SELINUX=disabled^g' /etc/selinux/config || true
cat /etc/selinux/config > /tmp/afterSeLinux.out

/etc/init.d/iptables save
/etc/init.d/iptables stop
chkconfig iptables off

yum install -y ntp
service ntpd start
service ntpd status
chkconfig ntpd on

yum install -y microsoft-hyper-v

echo never | tee -a /sys/kernel/mm/transparent_hugepage/enabled
echo "echo never | tee -a /sys/kernel/mm/transparent_hugepage/enabled" | tee -a /etc/rc.local
echo vm.swappiness=1 | tee -a /etc/sysctl.conf
echo 1 | tee /proc/sys/vm/swappiness
ifconfig -a >> initialIfconfig.out; who -b >> initialRestart.out

echo net.ipv4.tcp_timestamps=0 >> /etc/sysctl.conf
echo net.ipv4.tcp_sack=1 >> /etc/sysctl.conf
echo net.core.rmem_max=4194304 >> /etc/sysctl.conf
echo net.core.wmem_max=4194304 >> /etc/sysctl.conf
echo net.core.rmem_default=4194304 >> /etc/sysctl.conf
echo net.core.wmem_default=4194304 >> /etc/sysctl.conf
echo net.core.optmem_max=4194304 >> /etc/sysctl.conf
echo net.ipv4.tcp_rmem="4096 87380 4194304" >> /etc/sysctl.conf
echo net.ipv4.tcp_wmem="4096 65536 4194304" >> /etc/sysctl.conf
echo net.ipv4.tcp_low_latency=1 >> /etc/sysctl.conf
sed -i "s/defaults        1 1/defaults,noatime        0 0/" /etc/fstab

#use the key from the key vault as the SSH authorized key
mkdir /home/${ADMINUSER}/.ssh
chown ${ADMINUSER} /home/${ADMINUSER}/.ssh
chmod 700 /home/${ADMINUSER}/.ssh

ssh-keygen -y -f /var/lib/waagent/*.prv > /home/${ADMINUSER}/.ssh/authorized_keys
chown ${ADMINUSER} /home/${ADMINUSER}/.ssh/authorized_keys
chmod 600 /home/${ADMINUSER}/.ssh/authorized_keys

cp /tmp/systest_key /home/${ADMINUSER}/.ssh/id_rsa
echo "copy operation had result $?" >> /tmp/diagnostics.out
chown ${ADMINUSER} /home/${ADMINUSER}/.ssh/id_rsa
echo "adjust perms operation had result $?" >> /tmp/diagnostics.out
sudo chmod 600 /home/${ADMINUSER}/.ssh/id_rsa

# Add systest credential to authorized hosts list. The problem is that all hosts need to run this before any single host 
echo 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC5Zx7QmkQF+YIYxZ3z7KeD/CJAkzijm49QHQDIA0AnY2rLqFj09ZvKKFPVh+wnEU4PhKMVAGlBBjlItumxwx90BTstgnQqXK09GR4KBQAq2vpwUz4prkllj84wMrBlIAWcWXSJxO5zI4atcIDBnUw+W0dfgjMzgKAfnrg45xT+rMzQw41t1rtcURO3VgmvDHt1xAAZ/Zo5XjguOhIhdR9IOyTwyowHHcm2IGeuLuOeupAhcQc+7tEX+Jj8fxs9+0tbV4HYG3kM1Xe2r4kq5OPtM4YVOHRvqwmjmClR+i21iAs3EUWVRHI1KYywrULak7u01Y6PnI3pJ7pcO4HchgSR' >> /home/$ADMINUSER/.ssh/authorized_keys

myhostname=`hostname`
fqdnstring=`python -c "import socket; print socket.getfqdn('$myhostname')"`
sed -i "s/.*HOSTNAME.*/HOSTNAME=${fqdnstring}/g" /etc/sysconfig/network
/etc/init.d/network restart

#disable password authentication in ssh
#sed -i "s/UsePAM\s*yes/UsePAM no/" /etc/ssh/sshd_config
#sed -i "s/PasswordAuthentication\s*yes/PasswordAuthentication no/" /etc/ssh/sshd_config
#/etc/init.d/sshd restart
