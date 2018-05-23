#!/bin/bash


#set -x
############################# PREPARE #######################################
source $(dirname $0)/config
mkdir -p networks /var/lib/libvirt/images/$VM1_NAME /var/lib/libvirt/images/$VM2_NAME config-drives/$VM1_NAME-config/docker/certs config-drives/$VM2_NAME-config/docker docker/certs docker/etc 
echo 1 > /proc/sys/net/ipv4/ip_forward
echo "$VM1_MANAGEMENT_IP $VM1_NAME
$VM2_MANAGEMENT_IP $VM2_NAME" >> /etc/hosts
VM1_MAC=52:54:00:`(date; cat /proc/interrupts) | md5sum | sed -r 's/^(.{6}).*$/\1/; s/([0-9a-f]{2})/\1:/g; s/:$//;'`

########################### GEN ID_RSA ####################
mkdir -p $(dirname $SSH_PUB_KEY)
yes "y" | ssh-keygen -t rsa -N "" -f $(echo $SSH_PUB_KEY | rev | cut -c5- | rev)

####################### GEN OPENSSL-SAN.CNF ##########################
cat << EOF > /usr/lib/ssl/openssl-san.cnf 
[ req ]
default_bits                = 4096
default_keyfile             = privkey.pem
distinguished_name          = req_distinguished_name
req_extensions              = v3_req
 
[ req_distinguished_name ]
countryName                 = Country Name (2 letter code)
countryName_default         = UK
stateOrProvinceName         = State or Province Name (full name)
stateOrProvinceName_default = Wales
localityName                = Locality Name (eg, city)
localityName_default        = Cardiff
organizationName            = Organization Name (eg, company)
organizationName_default    = Example UK
commonName                  = Common Name (eg, YOUR name)
commonName_default          = one.test.app.example.net
commonName_max              = 64
 
[ v3_req ]
basicConstraints            = CA:FALSE
keyUsage                    = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName              = @alt_names
 
[alt_names]
IP.1   = $VM1_EXTERNAL_IP
DNS.1  = $VM1_NAME
EOF

########################## GEN WEB.CRT ###########################
openssl genrsa -out docker/certs/root-ca.key 4096
openssl req -x509 -new -key docker/certs/root-ca.key -days 365 -out docker/certs/root-ca.crt -subj "/C=UA/L=Kharkov/O=DLNet/OU=NOC/CN=dlnet.kharkov.com"
openssl genrsa -out docker/certs/web.key 4096
openssl req -new -key docker/certs/web.key -out docker/certs/web.csr -config /usr/lib/ssl/openssl-san.cnf -subj "/C=UA/L=Kharkov/O=DLNet/OU=NOC/CN=$VM1_NAME"
openssl x509 -req -in docker/certs/web.csr -CA docker/certs/root-ca.crt  -CAkey docker/certs/root-ca.key -CAcreateserial -out docker/certs/web.crt -days 365 -extensions v3_req -extfile /usr/lib/ssl/openssl-san.cnf
cat docker/certs/root-ca.crt >> docker/certs/web.crt

######################## GEN NGINX.CONF #############################
cat << EOF > docker/etc/nginx.conf
server {
        listen $NGINX_PORT;
        ssl on;
        ssl_certificate /etc/ssl/certs/nginx/web.crt;
        ssl_certificate_key /etc/ssl/certs/nginx/web.key;
	location / {
                proxy_pass         http://$VM2_VXLAN_IP:$APACHE_PORT;
                proxy_redirect     off;
                proxy_set_header   Host \$host;
                proxy_set_header   X-Real-IP \$remote_addr;
                proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
                proxy_set_header   X-Forwarded-Host \$server_name;
        }
}
EOF

################ GEN VM1 DOCKER-COMPOSE.YML ######################
cat << EOF > docker/$VM1_NAME-docker-compose.yml
version: '2'
services:
  nginx:
    image: $NGINX_IMAGE
    ports:
      - '$VM1_EXTERNAL_IP:$NGINX_PORT:$NGINX_PORT'
    volumes:
      - /srv/etc/nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - $NGINX_LOG_DIR:/var/log/nginx
      - /srv/certs:/etc/ssl/certs/nginx
EOF

############### GEN VM2 DOCKER-COMPOSE.YML ########################
cat << EOF > docker/$VM2_NAME-docker-compose.yml
version: '2'
services:
  apache:
    image: $APACHE_IMAGE
    ports:
      - '$VM2_VXLAN_IP:$APACHE_PORT:80'
EOF

####################### GEN VM1 USER-DATA #########################################
cat << EOF > config-drives/$VM1_NAME-config/user-data
#cloud-config
ssh_authorized_keys:
  - $(cat  $SSH_PUB_KEY)
apt_update: true
apt_sources:
packages:
  - apt-transport-https
  - ca-certificates
  - curl
  - software-properties-common 
  - bridge-utils
runcmd:
  - echo 1 > /proc/sys/net/ipv4/ip_forward
  - iptables -A INPUT -i lo -j ACCEPT
  - iptables -A FORWARD -i $VM1_EXTERNAL_IF -o $VM1_INTERNAL_IF -j ACCEPT
  - iptables -t nat -A POSTROUTING -o $VM1_EXTERNAL_IF -j MASQUERADE
  - iptables -A FORWARD -i $VM1_EXTERNAL_IF -m state --state ESTABLISHED,RELATED -j ACCEPT
  - iptables -A FORWARD -i $VM1_EXTERNAL_IF -o $VM1_INTERNAL_IF -j REJECT
  - ip link add $VXLAN_IF type vxlan id $VID remote $VM2_INTERNAL_IP local $VM1_INTERNAL_IP dstport 4789
  - ip link set vxlan0 up
  - ip addr add $VM1_VXLAN_IP/24 dev vxlan0
  - curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
  - add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
  - apt update
  - apt install docker-ce docker-compose -y
  - mkdir -p $NGINX_LOG_DIR /srv/etc/ /srv/docker-compose /srv/certs
  - mount -t iso9660 -o ro /dev/sr0 /mnt
  - cp /mnt/docker/certs/* /srv/certs
  - cp /mnt/docker/etc/* /srv/etc/
  - cp /mnt/docker/docker-compose.yml /srv/docker-compose/
  - umount /mnt
  - cd /srv/docker-compose &&  docker-compose up -d
EOF

####################### GEN VM2 USER-DATA #########################################
cat << EOF > config-drives/$VM2_NAME-config/user-data
#cloud-config
ssh_authorized_keys: 
  - $(cat  $SSH_PUB_KEY)
apt_update: true
apt_sources:
packages:
  - apt-transport-https
  - ca-certificates
  - curl
  - software-properties-common 
  - bridge-utils
runcmd:
  - ip link add $VXLAN_IF type vxlan id $VID remote $VM1_INTERNAL_IP local $VM2_INTERNAL_IP dstport 4789
  - ip link set vxlan0 up
  - ip addr add $VM2_VXLAN_IP/24 dev vxlan0
  - curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
  - add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
  - apt update
  - apt install docker-ce docker-compose -y
  - mkdir -p /srv/docker-compose
  - mount -t iso9660 -o ro /dev/sr0 /mnt
  - cp /mnt/docker/docker-compose.yml /srv/docker-compose/
  - umount /mnt
  - cd /srv/docker-compose &&  docker-compose up -d
EOF

####################### GEN VM1 META-DATA #########################################
cat << EOF > config-drives/$VM1_NAME-config/meta-data
hostname: $VM1_NAME
local-hostname: $VM1_NAME
network-interfaces: |
  auto $VM1_EXTERNAL_IF
  iface $VM1_EXTERNAL_IF inet dhcp
  dns-nameservers $VM_DNS
  auto $VM1_INTERNAL_IF
  iface $VM1_INTERNAL_IF inet static
  address $VM1_INTERNAL_IP
  netmask $INTERNAL_NET_MASK
  auto $VM1_MANAGEMENT_IF
  iface $VM1_MANAGEMENT_IF inet static
  address $VM1_MANAGEMENT_IP
  netmask $MANAGEMENT_NET_MASK
EOF

####################### GEN VM2 META-DATA #########################################
cat << EOF > config-drives/$VM2_NAME-config/meta-data
hostname: $VM2_NAME
local-hostname: $VM2_NAME
network-interfaces: |
  auto $VM2_INTERNAL_IF
  iface $VM2_INTERNAL_IF inet static
  address $VM2_INTERNAL_IP
  netmask $INTERNAL_NET_MASK
  gateway $VM1_INTERNAL_IP
  dns-nameservers $EXTERNAL_NET_HOST_IP $VM_DNS
  auto $VM2_MANAGEMENT_IF
  iface $VM2_MANAGEMENT_IF inet static
  address $VM2_MANAGEMENT_IP
  netmask $MANAGEMENT_NET_MASK
EOF

########################## CP FILES & MAKE ISO ##################################################
cp -r docker/etc  config-drives/$VM1_NAME-config/docker/
cp -r docker/certs/web.*  config-drives/$VM1_NAME-config/docker/certs
cp -r docker/$VM1_NAME-docker-compose.yml config-drives/$VM1_NAME-config/docker/docker-compose.yml
cp -r docker/$VM2_NAME-docker-compose.yml config-drives/$VM2_NAME-config/docker/docker-compose.yml
mkisofs -o $VM1_CONFIG_ISO -V cidata -r -J --quiet config-drives/$VM1_NAME-config
mkisofs -o $VM2_CONFIG_ISO -V cidata -r -J --quiet config-drives/$VM2_NAME-config

############################ CONF  NETWORK ##############################################

###### EXTERNAL ######
echo "
<network>
  <name>$EXTERNAL_NET_NAME</name>
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <ip address='$EXTERNAL_NET_HOST_IP' netmask='$EXTERNAL_NET_MASK'>
    <dhcp>
      <range start='$EXTERNAL_NET.2' end='$EXTERNAL_NET.254'/>
      <host mac='$VM1_MAC' name='vm1' ip='$VM1_EXTERNAL_IP'/>
    </dhcp>
  </ip>
</network>" > networks/$EXTERNAL_NET_NAME.xml

###### INTERNAL ######
echo "
<network>
  <name>$INTERNAL_NET_NAME</name>
</network>" > networks/$INTERNAL_NET_NAME.xml

###### MANAGEMENT ######
echo "
<network>
  <name>$MANAGEMENT_NET_NAME</name>
  <ip address='$MANAGEMENT_HOST_IP' netmask='$MANAGEMENT_NET_MASK'/>
</network>" > networks/$MANAGEMENT_NET_NAME.xml

###### APPLY XML ######
virsh net-destroy default
virsh net-undefine default
virsh net-define networks/$EXTERNAL_NET_NAME.xml
virsh net-start $EXTERNAL_NET_NAME
virsh net-autostart $EXTERNAL_NET_NAME
virsh net-define networks/$INTERNAL_NET_NAME.xml
virsh net-start $INTERNAL_NET_NAME
virsh net-autostart $INTERNAL_NET_NAME
virsh net-define networks/$MANAGEMENT_NET_NAME.xml
virsh net-start $MANAGEMENT_NET_NAME
virsh net-autostart $MANAGEMENT_NET_NAME

####################################### VIRT INSTALL ##################################################
wget -O /var/lib/libvirt/images/ubunut-server-16.04.qcow2 $VM_BASE_IMAGE

###### VM1 CREATE ######
cp /var/lib/libvirt/images/ubunut-server-16.04.qcow2  /var/lib/libvirt/images/$VM1_NAME/$VM1_NAME.qcow2
qemu-img resize /var/lib/libvirt/images/$VM1_NAME/$VM1_NAME.qcow2 +3GB
virt-install \
 --name $VM1_NAME\
 --ram $VM1_MB_RAM \
 --vcpus=$VM1_NUM_CPU \
 --$VM_TYPE \
 --os-type=linux \
 --os-variant=ubuntu16.04 \
 --disk path=$VM1_HDD,format=qcow2,bus=virtio,cache=none \
 --disk path=$VM1_CONFIG_ISO,device=cdrom \
 --graphics vnc,port=-1 \
 --network network=$EXTERNAL_NET_NAME,mac=\'$VM1_MAC\' \
 --network network=$INTERNAL_NET_NAME \
 --network network=$MANAGEMENT_NET_NAME \
 --noautoconsole \
 --quiet \
 --virt-type $VM_VIRT_TYPE \
 --import
virsh autostart $VM1_NAME

echo wait 5 min...
sleep 300

###### VM2 CREATE ######
cp /var/lib/libvirt/images/ubunut-server-16.04.qcow2  /var/lib/libvirt/images/$VM2_NAME/$VM2_NAME.qcow2
qemu-img resize /var/lib/libvirt/images/$VM2_NAME/$VM2_NAME.qcow2 +3GB
virt-install \
 --name $VM2_NAME\
 --ram $VM2_MB_RAM \
 --vcpus=$VM2_NUM_CPU \
 --$VM_TYPE \
 --os-type=linux \
 --os-variant=ubuntu16.04 \
 --disk path=$VM2_HDD,format=qcow2,bus=virtio,cache=none \
 --disk path=$VM2_CONFIG_ISO,device=cdrom \
 --graphics vnc,port=-1 \
 --network network=$INTERNAL_NET_NAME \
 --network network=$MANAGEMENT_NET_NAME \
 --noautoconsole \
 --quiet \
 --virt-type $VM_VIRT_TYPE \
 --import
virsh autostart $VM2_NAME
virsh list

echo '###### ALL DONE ######'
exit

