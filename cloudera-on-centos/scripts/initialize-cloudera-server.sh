#!/usr/bin/env bash

execname=$0

log() {
  echo "$(date): [${execname}] $@" >> /tmp/initialize-cloudera-server.log
}

#fail on any error
set -e

ClusterName=$1
key=$2
mip=$3
worker_ip=$4
HA=$5
User=$6
Password=$7

cmUser=$8
cmPassword=$9

EMAILADDRESS=${10}
BUSINESSPHONE=${11}
FIRSTNAME=${12}
LASTNAME=${13}
JOBROLE=${14}
JOBFUNCTION=${15}
COMPANY=${16}

log "BEGIN: master node deployments"
log "Beginning process of disabling SELinux"

log "Running as $(whoami) on $(hostname)"

# Use the Cloudera-documentation-suggested workaround
log "about to set setenforce to 0"
set +e
setenforce 0 >> /tmp/setenforce.out

exitcode=$?
log "Done with settiing enforce. Its exit code was $exitcode"
log "Running setenforce inline as $(setenforce 0)"

sed -i 's^SELINUX=enforcing^SELINUX=disabled^g' /etc/selinux/config || true

set +e

log "Set cloudera-manager.repo to CM v5"
yum clean all >> /tmp/initialize-cloudera-server.log
rpm --import http://archive.cloudera.com/cdh5/redhat/6/x86_64/cdh/RPM-GPG-KEY-cloudera >> /tmp/initialize-cloudera-server.log
wget http://archive.cloudera.com/cm5/redhat/6/x86_64/cm/cloudera-manager.repo -O /etc/yum.repos.d/cloudera-manager.repo >> /tmp/initialize-cloudera-server.log
# this often fails so adding retry logic
n=0
until [ $n -ge 5 ]
do
    yum install -y oracle-j2sdk* cloudera-manager-daemons cloudera-manager-server  >> /tmp/initialize-cloudera-server.log 2>> /tmp/initialize-cloudera-server.err && break
    n=$[$n+1]
    sleep 15s
done
if [ $n -ge 5 ]; then log "scp error $remote, exiting..." & exit 1; fi

#######################################################################################################################
log "installing external DB"
sudo yum install postgresql-server -y

ls -la /usr/share/java >> /tmp/initialize-cloudera-server.log

sudo yum install -y mysql-connector-java
echo "install of mysql-connector-java had status code $?" >> /tmp/initialize-cloudera-server.log

sudo yum instally -y postgresql-jdbc
echo "install of postgresql-jdbc had status code $?" >> /tmp/initialize-cloudera-server.log

ls -la /usr/share/java >> /tmp/initialize-cloudera-server.log

bash install-postgresql.sh >> /tmp/initialize-cloudera-server.log 2>> /tmp/initialize-cloudera-server.err
#restart to make sure all configuration take effects
sudo service postgresql restart

log "finished installing external DB"
#######################################################################################################################

log "start cloudera-scm-server services"
service cloudera-scm-server start >> /tmp/initialize-cloudera-server.log

while ! (exec 6<>/dev/tcp/$(hostname)/7180) ; do log 'Waiting for cloudera-scm-server to start...'; sleep 15; done
log "END: master node deployments"

# Set up python
rpm -ivh http://dl.fedoraproject.org/pub/epel/6/i386/epel-release-6-8.noarch.rpm >> /tmp/initialize-cloudera-server.log 2>> /tmp/initialize-cloudera-server.err
yum -y install python-pip >> /tmp/initialize-cloudera-server.log
pip install cm_api >> /tmp/initialize-cloudera-server.log

log "Finished setting up CM and Python"

# Execute script to deploy Cloudera cluster
log "BEGIN: CM deployment - starting"
logCmd="Command: python cmxDeployOnIbiza.py -n "\""$ClusterName"\"" -u "\""$User"\"" -p "\""$Password"\"" -k "\""$key"\"" -m "\""$mip"\"" -w "\""$worker_ip"\"" -c " \""$cmUser"\"" -s "\""$cmPassword"\"""
if "${HA}"; then
    logCmd="${logCmd} -a"
fi
log "${logCmd}"
if $HA; then
    python cmxDeployOnIbiza.py -n "${ClusterName}" -u "${User}" -p "${Password}"  -m "$mip" -w "$worker_ip" -a -c "${cmUser}" -s "${cmPassword}" -e -r "${EMAILADDRESS}" -b "${BUSINESSPHONE}" -f "${FIRSTNAME}" -t "${LASTNAME}" -o "${JOBROLE}" -i "${JOBFUNCTION}" -y "${COMPANY}">> /tmp/initialize-cloudera-server.log 2>> /tmp/initialize-cloudera-server.err
else
    python cmxDeployOnIbiza.py -n "${ClusterName}" -u "${User}" -p "${Password}"  -m "$mip" -w "$worker_ip" -c "${cmUser}" -s "${cmPassword}" -e -r "${EMAILADDRESS}" -b "${BUSINESSPHONE}" -f "${FIRSTNAME}" -t "${LASTNAME}" -o "${JOBROLE}" -i "${JOBFUNCTION}" -y "${COMPANY}">> /tmp/initialize-cloudera-server.log 2>> /tmp/initialize-cloudera-server.err
fi

log "Installing hive examples"
easy_install requests # necessary for hive examples
sudo chmod u+x ./install-hive-examples.py
./install-hive-examples.py
log "Hive examples install should be complete"
log "END: CM deployment ended"
