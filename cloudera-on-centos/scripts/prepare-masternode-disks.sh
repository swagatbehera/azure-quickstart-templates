#!/bin/bash

cat > inputs2.sh << 'END'

printFstab() 
{
  echo "Here is the fstab from $(hostname)"
  cat /etc/fstab
  echo "Now sudo print fstab from $(hostname)"
  sudo cat /etc/fstab
}

mountDrive() 
{
  driveName="${1}"
  driveId="${2}"
  mount -o noatime,barrier=0 -t ext4 "${driveName}" /data${driveId}
  UUID=$(sudo lsblk -no UUID $driveName)
  echo "UUID=${UUID}  /data${driveId}    ext4   defaults,noatime,discard,barrier=0 0 0" | sudo tee -a /etc/fstab
}

unmountDrive() 
{
  driveName=$1
  umount ${driveName}
  sudo umount ${driveName}
}

formatAndMountDrive() 
{
  drive=$1
  index=$2
  mke2fs -F -t ext4 -b 4096 -E lazy_itable_init=1 -O sparse_super,dir_index,extent,has_journal,uninit_bg -m1 ${drive}

  rm -rf /data${index} || true
  mkdir -p /data${index}
  chmod 777 /data${index}

  mount -o noatime,barrier=0 -t ext4 ${drive} /data${index}
  UUID=$(sudo lsblk -no UUID $drive)
  echo "UUID=${UUID}   /data${index}    ext4   defaults,noatime,discard,barrier=0 0 0" | sudo tee -a /etc/fstab
}

mountAllDrives() 
{
  let i=0 || true
  for x in $(sfdisk -l 2>/dev/null | cut -d' ' -f 2 | grep /dev | grep -v "/dev/sda" | grep -v "/dev/sdb" | sed "s^:^^");
  do
    mountDrive $x $i
    let i=(i+1) || true
  done
}

unmountAllDrives() 
{
  let i=0 || true
  for x in $(sfdisk -l 2>/dev/null | cut -d' ' -f 2 | grep /dev | grep -v "/dev/sda" | grep -v "/dev/sdb" | sed "s^:^^");
  do
    unmountDrive $x $i  0</dev/null &
    let i=(i + 1) || true
  done
  wait
}

formatAndMountAllDrives() 
{
  let i=0 || true
  for x in $(sfdisk -l 2>/dev/null | cut -d' ' -f 2 | grep /dev | grep -v "/dev/sda" | grep -v "/dev/sdb" | grep -v "/dev/sdc" | grep -v "/dev/sdd" | grep -v "/dev/sde" | grep -v "/dev/sdf" | sed "s^:^^");
  do
    formatAndMountDrive $x $i  0</dev/null &
    let i=(i + 1) || true
  done
  wait
}

mountDriveForLogCloudera()
{
  dirname="/log"
  drivename="/dev/sdc"
  mke2fs -F -t ext4 -b 4096 -E lazy_itable_init=1 -O sparse_super,dir_index,extent,has_journal,uninit_bg -m1 "${drivename}"
  mkdir "${dirname}"
  mount -o noatime,barrier=1 -t ext4 $drivename "${dirname}"
  UUID=$(sudo lsblk -no UUID ${drivename})
  echo "UUID=${UUID}   ${dirname}    ext4   defaults,noatime,barrier=0 0 1" | sudo tee -a /etc/fstab
  mkdir ${dirname}/cloudera
  ln -s  ${dirname}/cloudera /opt/cloudera
}

mountDriveForZookeeper()
{
	dirname="/log/cloudera/zookeeper"
	drivename="/dev/sdd"
	mke2fs -F -t ext4 -b 4096 -E lazy_itable_init=1 -O sparse_super,dir_index,extent,has_journal,uninit_bg -m1 ${drivename}
	mkdir $dirname
	mount -o noatime,barrier=1 -t ext4 $drivename $dirname
	UUID=$(sudo lsblk -no UUID ${drivename})
	echo "UUID=${UUID}   ${dirname}    ext4   defaults,noatime,barrier=0 0 1" | sudo tee -a /etc/fstab
}

mountDriveForQJN()
{
	dirname=/data/dfs/
	drivename=/dev/sde
	mke2fs -F -t ext4 -b 4096 -E lazy_itable_init=1 -O sparse_super,dir_index,extent,has_journal,uninit_bg -m1 $drivename
	mkdir /data
	mkdir $dirname
	mount -o noatime,barrier=1 -t ext4 $drivename $dirname
	UUID=$(sudo lsblk -no UUID ${drivename})
	echo "UUID=${UUID}   ${dirname}    ext4   defaults,noatime,barrier=0 0 1" | sudo tee -a /etc/fstab
}

mountDriveForPostgres()
{
	dirname="/var/lib/pgsql"
	drivename="/dev/sdf"
	mke2fs -F -t ext4 -b 4096 -E lazy_itable_init=1 -O sparse_super,dir_index,extent,has_journal,uninit_bg -m1 $drivename
	mkdir ${dirname}
	mount -o noatime,barrier=1 -t ext4 ${drivename} ${dirname}
	UUID=$(sudo lsblk -no UUID $drivename)
	echo "UUID=${UUID}   ${dirname}    ext4   defaults,noatime,barrier=0 0 1" | sudo tee -a /etc/fstab
}

mountMasterBundle()
{
    mountDriveForLogCloudera
    mountDriveForZookeeper
    mountDriveForQJN
    mountDriveForPostgres
}
END

bash -c "source ./inputs2.sh; printFstab; unmountAllDrives; mountMasterBundle;"
exit 0 
