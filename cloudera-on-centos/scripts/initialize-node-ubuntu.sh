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

LOG_FILE="/tmp/diagnostics.out"
HOSTNAME_LOG_FILE="/tmp/hostnames.out"
echo "initializing nodes..." >> ${LOG_FILE}

#TODO: Remove unused arguments and re-architect calling script to not supply them
IPPREFIX=$1
NAMEPREFIX=$2
NAMESUFFIX=$3
MASTERNODES=$4
DATANODES=$5
ADMINUSER=$6
NODETYPE=$7

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
echo "NODETYPE" >> ${LOG_FILE}
echo "$NODETYPE" >> ${LOG_FILE}

TESTUSER="jenkins"
TESTUSER_HOME=/var/lib/${TESTUSER}

# Disable the need for a tty when running sudo and allow passwordless sudo for the admin user
sed -i '/Defaults[[:space:]]\+!*requiretty/s/^/#/' /etc/sudoers
echo "${ADMINUSER} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
echo "${TESTUSER} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# For testing purposes, we will also have a user called 'Jenkins'.
# This is done for compatibility with existing Cloud providers in our testing.
# Make a home directory for this user

useradd -m -d ${TESTUSER_HOME} ${TESTUSER}
chown ${TESTUSER} ${TESTUSER_HOME}
chmod 755 ${TESTUSER_HOME}

# Need to adjust the systest user's id higher b/c of security on YARN
#not needed does not work
usermod -u 2345 "${ADMINUSER}"

# not needed does not work
{
  id ${ADMINUSER};
  echo "Running as $(whoami) in $(pwd)";
  echo "Perms on this directory are $(ls -la .)";
} >> ${LOG_FILE}

# Verify that the directory necessary for the private key is available
ls -la ~/.ssh
if [[ "$?" != "0" ]]; then

  echo "${HOME}/.ssh does not exist. We are right in making this folder" >> ${LOG_FILE}
else
  echo "${HOME}/.ssh already exists. We should not be re-making this folder" >> ${LOG_FILE}
fi

sudo mkdir -p ~/.ssh
echo "status of making home dir was was $?" >> ${LOG_FILE}
sudo chown "$(whoami)" ~/.ssh
sudo chmod 700 ~/.ssh

cp /etc/resolv.conf /tmp/old_resolv.conf
echo "nameserver 172.18.64.15" > /etc/resolvconf/resolv.conf.d/head
resolvconf -u
sleep 30s
cat /etc/resolv.conf >> ${LOG_FILE}

# set the configuration to not reset /etc/resolv.conf when we restart networking
# not needed for ubuntu
#sed -i "s^PEERDNS=yes^PEERDNS=no^g" /etc/sysconfig/network-scripts/ifcfg-eth0
#sudo service network-manager restart
sleep 100s
wget --no-dns-cache http://github.mtv.cloudera.com/raw/QE/smokes/cdh5/common/src/main/resources/systest/id_rsa
statusCode=$?
if [[ "${statusCode}" != "0" ]]; then
  echo "pulling down file failed with code ${statusCode}" >> ${LOG_FILE}
  wget --no-dns-cache http://github.mtv.cloudera.com/raw/QE/smokes/cdh5/common/src/main/resources/systest/id_rsa >> ${LOG_FILE}
  wget --no-dns-cache http://github.mtv.cloudera.com/raw/QE/smokes/cdh5/common/src/main/resources/systest/id_rsa 2>> ${LOG_FILE}

  # let's diagnose if it's a resolution issue
  host -v github.mtv.cloudera.com
  if [[ "$?" != "0" ]]; then
    echo "We could not resolve the host"  >> ${LOG_FILE}
  else
    echo "Host resolution was fine, actually"  >> ${LOG_FILE}
  fi

  # The code is dependent upon this file, so if it cannot be pulled down, we should fail
  set -e
  wget --no-dns-cache http://github.mtv.cloudera.com/raw/QE/smokes/cdh5/common/src/main/resources/systest/id_rsa
  wget --no-dns-cache http://github.mtv.cloudera.com/Kitchen/sshkeys/raw/master/_jenkins.pub
  cp _jenkins.pub /tmp/
  ls -la >> ${LOG_FILE}
  set +e
else

  # Also pull down the test user public key
  set -e
  wget --no-dns-cache http://github.mtv.cloudera.com/Kitchen/sshkeys/raw/master/_jenkins.pub
  cp _jenkins.pub /tmp/
  ls -la >> ${LOG_FILE}
  set +e
fi

chmod 600 ./id_rsa
cp ./id_rsa /tmp/systest_key
cp ./id_rsa ~/.ssh/
cp /tmp/old_resolv.conf /etc/resolv.conf

# Set the hostname
hostname=$(hostname)
instancename=$(echo "${hostname}" | awk -F"." '{print $1}')
subdomain="${NAMESUFFIX}"

instanceHostname="${instancename}.${subdomain}"
echo "instanceHostname is:" >> ${HOSTNAME_LOG_FILE}
echo $instanceHostname >> ${HOSTNAME_LOG_FILE}
hostnamectl set-hostname $instanceHostname
echo "127.0.0.1  $instanceHostname" >> /etc/hosts
hostname >> ${HOSTNAME_LOG_FILE}

{
  echo "here is the ~/.ssh/ directory";
  ls -la ~/.ssh/;
  echo "done listing the ~/.ssh/ directory";
} >> ${LOG_FILE}

# Mount and format the attached disks base on node type
if [ "$NODETYPE" == "masternode" ]
then
  echo "preparing master node" >> ${LOG_FILE}
  bash ./prepare-masternode-disks.sh
  echo "preparing master node exited with code $?" >> ${LOG_FILE}

elif [ "$NODETYPE" == "datanode" ]
then
  echo "preparing data node" >> ${LOG_FILE}
  bash ./prepare-datanode-disks.sh
  echo "preparing data node exited with code $?" >> ${LOG_FILE}
else
  echo "#unknown type, default to datanode" >> ${LOG_FILE}
  bash ./prepare-datanode-disks.sh
fi

echo "Done preparing disks.  Now ls -la looks like this:" >> ${LOG_FILE}
ls -la / >> ${LOG_FILE}
# Create Impala scratch directory
numDataDirs=$(ls -la / | grep data | wc -l)
echo "numDataDirs: ${numDataDirs}" >> ${LOG_FILE}
let endLoopIter="(numDataDirs - 1)"
for x in $(seq 0 $endLoopIter)
do 
  mkdir -p /data${x}/impala/scratch
  chmod 777 /data${x}/impala/scratch
done

apt-get install selinux-utils -y
setenforce 0 >> /tmp/setenforce.out

#selinux is disabled by default on ubuntu

sudo ufw disable

if which yum; then
 yum clean all
fi
if which apt-get; then
 apt-get update
fi
if which zypper; then
 zypp clean all
fi

sudo ntpdate pool.ntp.org
sudo apt-get install ntp -y

apt-get install --install-recommends linux-virtual-lts-wily -y
apt-get install --install-recommends linux-tools-virtual-lts-wily linux-cloud-tools-virtual-lts-wily -y

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

# Set up private key for $ADMINUSER and $TESTUSER
useradd -m -d "/home/${ADMINUSER}" ${ADMINUSER}
mkdir /home/${ADMINUSER}
mkdir /home/${ADMINUSER}/.ssh
chown ${ADMINUSER} /home/${ADMINUSER}/.ssh
chmod 700 /home/${ADMINUSER}/.ssh

mkdir ${TESTUSER_HOME}/.ssh
chown ${TESTUSER} ${TESTUSER_HOME}/.ssh
chmod 700 ${TESTUSER_HOME}/.ssh

ssh-keygen -y -f /var/lib/waagent/*.prv > /home/${ADMINUSER}/.ssh/authorized_keys
chown ${ADMINUSER} /home/${ADMINUSER}/.ssh/authorized_keys
chmod 600 /home/${ADMINUSER}/.ssh/authorized_keys

chown ${TESTUSER} ${TESTUSER_HOME}/.ssh/authorized_keys
chmod 600 ${TESTUSER_HOME}/.ssh/authorized_keys

cp /tmp/systest_key /home/${ADMINUSER}/.ssh/id_rsa
echo "copy operation had result $?" >> ${LOG_FILE}
chown ${ADMINUSER} /home/${ADMINUSER}/.ssh/id_rsa
echo "adjust perms operation had result $?" >> ${LOG_FILE}
sudo chmod 600 /home/${ADMINUSER}/.ssh/id_rsa

cp /tmp/systest_key ${TESTUSER_HOME}/.ssh/id_rsa
echo "copy operation had result $?" >> ${LOG_FILE}
chown ${TESTUSER} ${TESTUSER_HOME}/.ssh/id_rsa
echo "adjust perms operation had result $?" >> ${LOG_FILE}
sudo chmod 600 ${TESTUSER_HOME}/.ssh/id_rsa

# Add systest credential to authorized hosts list. The problem is that all hosts need to run this before any single host 
echo 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC5Zx7QmkQF+YIYxZ3z7KeD/CJAkzijm49QHQDIA0AnY2rLqFj09ZvKKFPVh+wnEU4PhKMVAGlBBjlItumxwx90BTstgnQqXK09GR4KBQAq2vpwUz4prkllj84wMrBlIAWcWXSJxO5zI4atcIDBnUw+W0dfgjMzgKAfnrg45xT+rMzQw41t1rtcURO3VgmvDHt1xAAZ/Zo5XjguOhIhdR9IOyTwyowHHcm2IGeuLuOeupAhcQc+7tEX+Jj8fxs9+0tbV4HYG3kM1Xe2r4kq5OPtM4YVOHRvqwmjmClR+i21iAs3EUWVRHI1KYywrULak7u01Y6PnI3pJ7pcO4HchgSR' >> /home/$ADMINUSER/.ssh/authorized_keys

# Add jenkins credential to authorized hosts list. The problem is that all hosts need to run this before any single host 
echo "About to publish /tmp/_jenkins.pub into authorized keys for the test user"
cat /tmp/_jenkins.pub >> ${TESTUSER_HOME}/.ssh/authorized_keys
chown ${TESTUSER} ${TESTUSER_HOME}/.ssh/authorized_keys
chmod 600 ${TESTUSER_HOME}/.ssh/authorized_keys
ls -la ${TESTUSER_HOME}/.ssh >> ${LOG_FILE}

sudo reboot

# TODO - Find out if this is useful?
#myhostname=$(hostname)
#fqdnstring=$(python -c "import socket; print socket.getfqdn('$myhostname')")
#sed -i "s/.*HOSTNAME.*/HOSTNAME=${fqdnstring}/g" /etc/sysconfig/network
#/etc/init.d/network restart
