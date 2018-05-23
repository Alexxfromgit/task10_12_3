#!/bin/bash

virsh destroy vm1
virsh destroy vm2
virsh undefine vm1
virsh undefine vm2
virsh net-destroy external
virsh net-destroy internal
virsh net-destroy management
virsh net-undefine external
virsh net-undefine internal
virsh net-undefine management

