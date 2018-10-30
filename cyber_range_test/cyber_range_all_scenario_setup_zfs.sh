#!/bin/bash
# create cyber_range environment
# - clone type : zfs
# - scenario 1 : Ransomeware
# - scenario 2 : Dos Attack

tool_dir=/root/github/cyber_range/server/tools/proxmox

# TODO: Now, template vms number are fixed
WEB_TEMP=0    # initial web server template vm number. RANGE: 100~999
CLIENT_TEMP=0 # initial client pc template vm number. RANGE: 100~999
VYOS_TEMP=900 # initial vyos(software router os) template vm number. RANGE: 100~999
PROXMOX_MAX_NUM=9      # Promox server upper limit
GROUP_MAX_NUM=7        # group upper limit per Proxmox server
TARGET_STRAGE='local-zfs' # full clone target strage
VG_NAME='VolGroup'     # Volume Group name
LOG_FILE="./setup.log" # log file name

# Get JSON data
json_vm_data=`cat vm_info.json`
json_scenario_data=`cat scenario_info.json`
day=`echo $json_scenario_data | jq '.day'`
group_num=`echo $json_scenario_data | jq '.group_num'`
student_per_group=`echo $json_scenario_data | jq '.student_per_group'`
scenario_nums=`echo $json_scenario_data | jq ".days[$((day - 1))].scenario_nums[].scenario_num"`

# bridge number of connecting each group network(=Proxmox number)
# if proxmox number is 1. network address is 192.168.1.0/24
VYOS_NETWORK_BRIDGE=$PROXMOX_NUM

# TODO: Decide to WEB_NUMS and CLIENT_NUMS setting rules
serial_num=0 # 0から始まる通し番号
for _ in $scenario_nums; do
    for g_num in `seq 1 $group_num`; do
        VYOS_NUMS+=("${g_num}${serial_num}1") # vyos number is *01
        WEB_NUMS+=("${g_num}${serial_num}2")  # web server number is *02
        for i in `seq 3 $((2 + $student_per_group))`; do
            CLIENT_NUMS+=("${g_num}${serial_num}${i}") # client pc number are *03 ~ *09
        done
    done
    let "serial_num=serial_num+1" # increment
done

# TODO: Choise each scenario num. Now, create same scenario's environments
read -p "scenario number(1 or 2): " scenario_num
if [ $scenario_num -eq 1 ]; then
    # scenario 1
    WEB_TEMP=902     # template web server vm number
    CLIENT_TEMP=901  # template client pc vm number
elif [ $scenario_num -eq 2 ]; then
    # scenario 2
    WEB_TEMP=902     # template web server vm number
    CLIENT_TEMP=955  # template client pc vm number
else
    echo 'invalid'
    exit 1
fi

start_time=`date +%s`

pc_type='vyos'
for num in ${VYOS_NUMS[@]}; do
    # bridge rules https://sites.google.com/a/cysec.cs.ritsumei.ac.jp/local/shareddevices/proxmox/network
    group_network_bridge="1${PROXMOX_NUM}${num:0:1}" # decide group netwrok bridge number
    snapshot_name="vm${num}_cloned_snapshot"
    #$tool_dir/clone_vm.sh $num $VYOS_TEMP $pc_type $TARGET_STRAGE $VYOS_NETWORK_BRIDGE $group_network_bridge
    #$tool_dir/vyos_config_setup.sh $num $VYOS_NETWORK_BRIDGE $group_network_bridge            # change cloned vm's config files
    $tool_dir/zfs_clone_vm.sh $num $VYOS_TEMP $pc_type $VYOS_NETWORK_BRIDGE $group_network_bridge # clone vm by zfs clone
    $tool_dir/zfs_vyos_config_setup.sh $num $VYOS_NETWORK_BRIDGE $group_network_bridge            # change cloned vm's config files
    $tool_dir/create_snapshot.vm $num $snapshot_name # create snapshot

    # first scenario's vm starts
    if [ ${num:1:1} -eq '0' ]; then
        qm start $num &
    fi
done

pc_type='web'
for num in ${WEB_NUMS[@]}; do
    # bridge rules https://sites.google.com/a/cysec.cs.ritsumei.ac.jp/local/shareddevices/proxmox/network
    group_network_bridge="1${PROXMOX_NUM}${num:0:1}" # decide group network bridge number
    ip_address="192.168.${group_network_bridge}.${num:2:1}" # new vm's ip address
    snapshot_name="vm${num}_cloned_snapshot"
    $tool_dir/zfs_clone_vm.sh $num $WEB_TEMP $pc_type $group_network_bridge # clone vm by zfs clone
    $tool_dir/zfs_centos_config_setup.sh $num $ip_address $pc_type $VG_NAME # change cloned vm's config files
    $tool_dir/create_snapshot.vm $num $snapshot_name # create snapshot

    # first scenario's vm starts
    if [ ${num:1:1} -eq '0' ]; then
        qm start $num &
    fi
done

pc_type='client'
for num in ${CLIENT_NUMS[@]}; do
    # bridge rules https://sites.google.com/a/cysec.cs.ritsumei.ac.jp/local/shareddevices/proxmox/network
    group_network_bridge="1${PROXMOX_NUM}${num:0:1}" # decide group network bridge number
    ip_address="192.168.${group_network_bridge}.${num:2:1}" # new vm's ip address
    snapshot_name="vm${num}_cloned_snapshot"
    if [ $scenario_num -eq 3 ]; then
        mul_num=${num:0:1}
        mul_num=$((mul_num - 1))
        add_num=${num:2:1}
        add_num=$((add_num - 3))
        client_num=$((CLIENT_TEMP + STUDENTS_PER_GROUP * mul_num + add_num))
    	$tool_dir/zfs_clone_vm.sh $num $client_num $pc_type $group_network_bridge
    else
    	$tool_dir/zfs_clone_vm.sh $num $CLIENT_TEMP $pc_type $group_network_bridge
    fi
    if [ $scenario_num -eq 1 ]; then
        $tool_dir/zfs_centos_config_setup.sh $num $ip_address $pc_type $VG_NAME #change cloned vm's config file
    fi
    $tool_dir/create_snapshot.vm $num $snapshot_name # create snapshot

    # first scenario's vm starts
    if [ ${num:1:1} -eq '0' ]; then
        qm start $num &
    fi
done

end_time=`date +%s`

time=$((end_time - start_time))
echo $time

# output logs
echo "[`date "+%Y/%m/%d %H:%M:%S"`] $0 $*" >> $LOG_FILE
echo " time              : $time [s]" >> $LOG_FILE
echo " scenario          : $scenario_num" >> $LOG_FILE
echo " group_num         : $group_num" >> $LOG_FILE
echo " router_template_vm: $VYOS_TEMP" >> $LOG_FILE
echo " router_vms:       : ${VYOS_NUMS[@]}" >> $LOG_FILE
echo " server_template_vm: $WEB_TEMP" >> $LOG_FILE
echo " server_vms:       : ${WEB_NUMS[@]}" >> $LOG_FILE
echo " client_template_vm: $CLIENT_TEMP" >> $LOG_FILE
echo " client_vms:       : ${CLIENT_NUMS[@]}" >> $LOG_FILE
echo >> $LOG_FILE
