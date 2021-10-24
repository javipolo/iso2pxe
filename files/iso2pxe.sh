#!/bin/bash

set -e

if [ -z ${hypervisor} ]; then
  echo \$hypervisor ip address needs to be set
  echo preferrably this ends is in .1
  exit
fi

webserver=${hypervisor}:8000
pxe_mount=/tmp/mnt
tftp_path=/tftpboot
iso_paths=/data/iso
mkdir -p ${tftp_path}/pxelinux.cfg
cp /data/pxelinux.cfg ${tftp_path}/pxelinux.cfg/default
for iso in $(find ${iso_paths} -name '*.iso'); do
  isoname=$(basename $iso | sed -e 's/.iso//g')
  mkdir -p ${tftp_path}/${isoname}
  7z e ${iso} -o${tftp_path}/${isoname} images/pxeboot/vmlinuz
  7z e ${iso} -o${tftp_path}/${isoname} images/pxeboot/initrd.img
  7z e ${iso} -o${tftp_path}/${isoname} images/pxeboot/rootfs.img
  7z e ${iso} -o${tftp_path}/${isoname} images/ignition.img
  cat ${tftp_path}/${isoname}/ignition.img | gunzip | \
    sed "s/.*config.ign.*/{/" | sed "s/.*TRAILER.*/}/" > ${tftp_path}/${isoname}/ignition.ign
  echo "LABEL ${isoname}" >> ${tftp_path}/pxelinux.cfg/default
  echo "  KERNEL ${isoname}/vmlinuz" >> ${tftp_path}/pxelinux.cfg/default
  echo "  APPEND initrd=${isoname}/initrd.img,${isoname}/rootfs.img ignition.config.url=http://${webserver}/${isoname}/ignition.ign ignition.firstboot ignition.platform.id=metal" >> ${tftp_path}/pxelinux.cfg/default
done

start_dhcp=$(echo ${hypervisor} | awk -F. '{print $1"."$2"."$3}').$(($(echo ${hypervisor} | awk -F. '{print $4}') + 1))
end_dhcp=$(echo ${hypervisor} | awk -F. '{print $1"."$2"."$3}').$(($(echo ${hypervisor} | awk -F. '{print $4}') + 200))

/usr/sbin/dnsmasq -k -d \
  --enable-tftp --tftp-root=/tftpboot --tftp-lowercase \
  --dhcp-range=${start_dhcp},${end_dhcp},255.255.255.0 \
  --dhcp-option=3,${hypervisor} \
  --dhcp-option=option:router,${hypervisor} \
  --dhcp-no-override \
  --dhcp-boot=pxelinux.0 \
  --conf-dir=/etc/dnsmasq.d,.rpmnew,.rpmsave,.rpmorig \
  --log-dhcp &
/usr/bin/python3 -m http.server --directory ${tftp_path} 8000 &

while true; do
  pgrep dnsmasq > /dev/null
  pgrep python3 > /dev/null
  sleep 3
done
