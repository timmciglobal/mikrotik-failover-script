# Failover WAN script by Tim Alexander rev date July 8th 2021
# Requirements: Set PrimaryInterfaceType to static or DHCP with distance 5, FailOverInterface set to static or DHCP with distance of 10.
# Default route on $primary-interface added as distance 5, default route added from $failover-interface as distance 10
# Every 1 minute check to see if $checkhost1 and $checkhost2 are reachable via specific routing mark per interface
# If $FailoverFailPingCount is less then $CheckThreshhold and $PrimaryFailPingCount is over $CheckThreshhold add default route distance 1 of $failover-gateway and clear the current connection. Log and send an e-mail notifying $NotificationEmailAddress
# If LastWANStatus is Failover, check the primary route again and if primary-interface has no packet remove the distance=1 failover route and let distance 5 primary route take over. Clear connections. Log and send an e-mail to NotificationEmailAddress and notify Primary back up.
 
# VARIABLES YOU MUST SET BELOW
# set PrimaryInterface to the primary interface name
:global PrimaryInterface "ether1";
# set PrimaryInterfaceType to the primary interface type
:global PrimaryInterfaceType "dhcp";
# set FailoverInterface to the failover interface name
:global FailoverInterface "ether4";
# set FailoverInterfaceType to the failover interface type.
:global FailoverInterfaceType "dhcp";
# set the ping target hosts below
:global CheckHost1 "8.8.8.8";
:global CheckHost2 "1.1.1.1";
# set FailCheckThreshhold to number of failed pings to trigger a failover situation.
:global FailCheckThreshhold "4";
# Set FailbackPeriodMultiple to # of times the script should run before failing back if primary wan is availible again. Ex: If script runs once per minute, 15 will delay failback for a minimum of 15 minutes of failed state
:global FailbackPeriodMultiple 15;
# set SenderEmailAddress to be the sender e-mail
:global SenderEmailAddress "someone@somewhere.com"
#set NotificationEmailAddress to primary notification e-mail address, must be filled in
:global NotificationEmailAddress "primarynotification@somewhere.com"
# set NotificationCCEmailAddresses to the secondary CC addresses, comma seperated, can be blank
:global NotificationCCEmailAddresses "john@doe.com,jane@doe.com"
# set EmailNotificationPeriodMultiple to number of times script should itterate in same failed state before trigger another alert that it's still in failed mode. If scripts runs once per minute 30 would be 30 minutes on failure to send another e-mail after the first.
:global EmailNotificationPeriodMultiple 30;
 
# VARIABLES DYNAMICALLY SET
:global LastWANStatus;
:global InternetLastChange;
:global RouterIdentify [/system identity get value-name=name];
:global PrimaryInterfaceRunning [/interface ethernet get value-name=running [find where name=$PrimaryInterface]];
:global PrimaryAddress;
:global PrimaryGateway;
:global PrimaryWANStatus;
:global FailoverInterfaceRunning [/interface ethernet get value-name=running [find where name=$FailoverInterface]];
:global FailoverAddress;
:global FailoverGateway;
:global FailoverWANStatus;
:global wanStatus;
:global FailbackPeriodCounter;
:global CurrentDate [/system clock get date];
:global CurrentTime [/system clock get time];
:global standardtime ([:pick $CurrentTime 0 2].[:pick $CurrentTime 3 5].[pick $CurrentTime 6 8])
:global PrimaryFailPingCount;
:global FailoverFailPingCount;
:global EmailNotificationCounter;
 
#Get gateway and IP information for primary and failover
if ($PrimaryInterfaceRunning = true) do={
if ($PrimaryInterfaceType = "dhcp") do={
:set PrimaryAddress [/ip dhcp-client get [find where interface=$PrimaryInterface] value-name=address];
:set PrimaryGateway [/ip dhcp-client get [find where interface=$PrimaryInterface] value-name=gateway];
}
if ($PrimaryInterfaceType = "static") do={
:set PrimaryAddress [/ip address get value-name=address [find where interface=$PrimaryInterface]];
:set PrimaryGateway [/ip route get value-name=gateway [find where distance=5]];
}
#Check if primary gateway exists and add primary and backup routes to dedicated routing marks to test via those interfaces/gateways
if ([:len $PrimaryGateway] != 0 ) do={
/ip route add dst-address=0.0.0.0/0 gateway=$PrimaryGateway routing-mark=PrimaryWAN;
}
}
 
if ($FailoverInterfaceRunning = true) do={
if ($FailoverInterfaceType = "dhcp") do={
:set FailoverAddress [/ip dhcp-client get [find where interface=$FailoverInterface] value-name=address];
:set FailoverGateway [/ip dhcp-client get [find where interface=$FailoverInterface] value-name=gateway];
}
if ($FailoverInterfaceType = "static") do={
:set FailoverAddress [/ip address get value-name=address [find where interface=$FailoverInterface]];
:set FailoverGateway [/ip route get value-name=gateway [find where distance=10]];
}
#Check if failover gateway exists and add primary and backup routes to dedicated routing marks to test via those interfaces/gateways
if ([:len $FailoverGateway] != 0) do={
/ip route add dst-address=0.0.0.0/0 gateway=$FailoverGateway routing-mark=FailoverWAN;
}
}
 
#Verify WAN interfaces working
:for i from=1 to=4 do={
if ([:len $PrimaryGateway] != 0) do={
if ([/ping $CheckHost1 routing-table=PrimaryWAN count=1]=0) do={:set PrimaryFailPingCount ($PrimaryFailPingCount + 1)}
if ([/ping $CheckHost2 routing-table=PrimaryWAN count=1]=0) do={:set PrimaryFailPingCount ($PrimaryFailPingCount + 1)}
} else={
:set PrimaryFailPingCount ($PrimaryFailPingCount + 1)
}
if ([:len $FailoverGateway] != 0) do={
if ([/ping $CheckHost1 routing-table=FailoverWAN count=1]=0) do={:set FailoverFailPingCount ($FailoverFailPingCount + 1)}
if ([/ping $CheckHost2 routing-table=FailoverWAN count=1]=0) do={:set FailoverFailPingCount ($FailoverFailPingCount + 1)}
} else={
:set FailoverFailPingCount ($FailoverFailPingCount + 1)
:delay 2s
}
}
 
#Record results and decide if Primary and Failover Routes are up
if (($PrimaryFailPingCount < $FailCheckThreshhold) && ($PrimaryInterfaceRunning = true) && ([:len $PrimaryGateway] != 0)) do={
:set PrimaryWANStatus "up";
} else={
:set PrimaryWANStatus "down";
}
if (($FailoverFailPingCount < $FailCheckThreshhold) && ($FailoverInterfaceRunning = true) && ([:len $FailoverGateway] != 0)) do={
:set FailoverWANStatus "up";
} else={
:set FailoverWANStatus "down";
}
 
#Check if Last wan status is empty, if it is set it to PrimaryWAN
if ([:len $LastWANStatus] = 0 ) do={
:set LastWANStatus PrimaryWAN;
}
 
# If last status is PrimaryWAN
if ($LastWANStatus = "PrimaryWAN") do={
 
# if both primary and failover wan up when last on primary wan
if (($PrimaryWANStatus = "up") && ($FailoverWANStatus = "up")) do={
:set wanStatus "Primary WAN Active Failover WAN Available";
}
 
# if primary wan up failover down when last on primary wan
if (($PrimaryWANStatus = "up") && ($FailoverWANStatus = "down")) do={
:set wanStatus "Primary Wan Up Failover WAN Down";
:log error ($RouterIdentify . " Primary WAN UP but Failover Connection failed at " . $CurrentDate . $CurrentTime);
if (($EmailNotificationCounter = $EmailNotificationPeriodMultiple) or ($EmailNotificationCounter = 0) or ([:len $EmailNotificationCounter] = 0)) do={
/tool e-mail send subject="$RouterIdentify Primary WAN Up but Failover Connection failed at $CurrentDate $CurrentTime" from="$SenderEmailAddress" to="$NotificationEmailAddress" cc="$NotificationCCEmailAddresses" body="$RouterIdentify up on $PrimaryAddress but Failover WAN down $FailoverInterface running is $FailoverInterfaceRunning $FailoverAddress";
:set $EmailNotificationCounter 1;
} else={
:set $EmailNotificationCounter ($EmailNotificationCounter+1);
}
}
 
# if Primary wan down and failover up when last on primary wan
if (($PrimaryWANStatus = "down") && ($FailoverWANStatus = "up")) do={
:set InternetLastChange "$CurrentDate $CurrentTime"
:set wanStatus "Primary WAN Down Failover Wan Active";
/ip route add dst-address=0.0.0.0/0 distance=1 gateway=$FailoverGateway comment="failover-wan-route-distance-1";
/ip firewall connection {:foreach r in=[find] do={remove $r}};
:set LastWANStatus FailoverWAN;
:log warning ($RouterIdentify . " on Failover Connection at " . $FailoverAddress . $CurrentDate . $CurrentTime);
/tool e-mail send subject="$RouterIdentify on Failover Connection at $CurrentDate $CurrentTime" from="$SenderEmailAddress" to="$NotificationEmailAddress" cc="$NotificationCCEmailAddresses" body="$RouterIdentify on Failover connection $FailoverInterface $FailoverAddress since $InternetLastChange";
}
 
# if primary wan down and failover wan down when last on primary wan
if (($PrimaryWANStatus = "down") && ($FailoverWANStatus = "down")) do={
:set wanStatus "Primary WAN Down Failover Wan Down";
:log warning ($RouterIdentify . " Primary and Failover connection down at " . $CurrentDate . $CurrentTime . " unable to failover");
}
}
 
# Last Status FailoverWan
if ($LastWANStatus = "FailoverWAN") do={
 
# if both primary and failover wan up when last on failover wan
if (($PrimaryWANStatus = "up") && ($FailoverWANStatus = "up") && ($FailbackPeriodCounter >= $FailbackPeriodMultiple)) do={
:set InternetLastChange "$CurrentDate $CurrentTime"
:set wanStatus "Primary WAN Active Failover Available";
/ip route remove [find where comment="failover-wan-route-distance-1"];
/ip firewall connection {:foreach r in=[find] do={remove $r}};
:set LastWANStatus PrimaryWAN;
:set FailbackPeriodCounter 0;
:log warning ($RouterIdentify . " on Primary WAN Restored Failover Wan Available at " . $CurrentDate . $CurrentTime);
/tool e-mail send subject="$RouterIdentify restored Primary WAN Connection at $CurrentDate $CurrentTime" from="$SenderEmailAddress" to="$NotificationEmailAddress" cc="$NotificationCCEmailAddresses" body="$RouterIdentify restored Primary WAN $PrimaryInterface $PrimaryAddress since $InternetLastChange";
} else={
set $FailbackPeriodCounter ($FailbackPeriodCounter+1);
}
 
# if primary wan up failover down when last on failover wan
if (($PrimaryWANStatus = "up") && ($FailoverWANStatus = "down")) do={
:set InternetLastChange "$CurrentDate $CurrentTime"
:set wanStatus "Primary Up Failover Down";
/ip route remove [find where comment="failover-wan-route-distance-1"];
/ip firewall connection {:foreach r in=[find] do={remove $r}};
:set LastWANStatus PrimaryWAN;
:set FailbackPeriodCounter 0;
:log error ($RouterIdentify , " Primary WAN restored but Failover Connection failed at " . $CurrentDate . $CurrentTime " failover interface info " . $FailoverInterface . $FailoverInterfaceRunning . $FailoverAddress . $FailoverGateway);
/tool e-mail send subject="$RouterIdentify ' Primary WAN restored but Failover Connection failed at ' $CurrentDate $CurrentTime" from="$SenderEmailAddress" to="$NotificationEmailAddress" cc="$NotificationCCEmailAddresses" body="$RouterIdentify $PrimaryAddress restored on $InternetLastChange but failover wan down $FailOverInterface $FailoverInterfaceRunning $FailoverGateway";
}
 
# if Primary wan down and failover up when last on failover wan
if (($PrimaryWANStatus = "down") && ($FailoverWANStatus = "up")) do={
:set wanStatus "Primary WAN Down On Failover still active";
:set FailbackPeriodCounter ($FailbackPeriodCounter +1);
:log warning ($RouterIdentify . " still on Failover Connection " . $FailoverAddress . " since " . $InternetLastChange);
}
 
# if primary wan down and failover wan down when last on failover wan
if (($PrimaryWANStatus = "down") && ($FailoverWANStatus = "down")) do={
:set InternetLastChange "$CurrentDate $CurrentTime"
:set wanStatus "Primary WAN Down Failover Wan Down";
:set FailbackPeriodCounter ($FailbackPeriodCounter+1)
:log error ($RouterIdentify . " Primary and Failover connection down at " . $CurrentDate . $CurrentTime . " I'm so alone");
}
}
 
#cleanup temporary routes and variables used during script execution
/ip route remove [find where routing-mark=PrimaryWAN];
/ip route remove [find where routing-mark=FailoverWAN];
set PrimaryFailPingCount "0";
set FailoverFailPingCount "0";
