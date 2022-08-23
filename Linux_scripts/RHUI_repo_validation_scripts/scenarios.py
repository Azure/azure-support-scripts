import logging

###### class for colours #########
class colors:
   RED = '\033[1;31;40m'
   GREEN = '\033[1;32;40m'
   YELLOW = '\033[33m'
   ENDC = '\033[0;37;40m'
   BOLD = '\033[1m'

############## Function for printing messages ##############

def msg_uid_error():
   logging.error(colors.RED +"Error: This script has to be executed as root user or with sudo privilge,exiting now.Please try again" + colors.ENDC)
   exit()

def msg_os_dist_error():
   logging.error(colors.RED +"This script currently works only on Redhat Linux distributions" + colors.ENDC)

def msg_rhui_ip_connectivity_error(ip):
   logging.error(colors.RED + "RHEL repo IP %s is not connected. Please make sure connectivity to repo server works and then re run this script"%ip + colors.ENDC)

def msg_rhui_ip_connectivity_success():
   logging.info(colors.GREEN + "Repo server IP connectivity is successful" + colors.ENDC)

def msg_rhui_package_check_success():
   logging.info(colors.GREEN + "rhui-package check is successful" + colors.ENDC)

def msg_rhui_package_check_error():
   logging.error(colors.RED + "rhui-azure package is not available, Install rhui-azure by downloading manually and rerun this script" + colors.ENDC)
   exit()


def msg_ip_tables_check():
   logging.error(colors.RED + "Validate the Reject rules in OUTPUT chain which is listed above and please make sure the connectivity to below mentioned RHUI IPs based on your region over 443 is not blocked\n\n  # Azure Global\n   13.91.47.76\n   40.85.190.91\n   52.187.75.218\n   52.174.163.213\n   52.237.203.198\n\n  # Azure US Government\n   13.72.186.193\n   13.72.14.155\n   52.244.249.194\n" + colors.ENDC)
   exit()

def msg_rhui_ip_connectivity_success():
   logging.info(colors.GREEN + "Repo server IP connectivity is successful" + colors.ENDC)
def msg_multiple_yum_process():
   logging.error(colors.RED + "seems another yum process is running. Please rerun the script once the other yum process completes" + colors.ENDC)
   logging.info(colors.GREEN + "RESOLUTION : if the other yum process was not initiated by you and ifs its not stopping for some reason, you can try killing it using the below commands and then try rerunning the script\n   #ps aux | grep -i yum (prints the process id of all yum running processes) \n   #kill -9 yum_process_id (kills the process based on provided PID)" + colors.ENDC)
   exit()

def msg_yum_repolist_success():
   logging.info(colors.GREEN + "yum check-update is successful. No errors observed" + colors.ENDC)
   exit()

def msg_new_scenario():
   logging.error(colors.RED + "This seems to be a new issue and not the regular one. We suggest you to log a case with Microsoft Support team for further troubleshooting. Thank you!!" + colors.ENDC)

def msg_https_404_error_non_eus():
   logging.error(colors.RED + "It seems repo is NON-EUS and /etc/yum/vars/releasever file is available." + colors.ENDC)
   logging.info(colors.GREEN +  "RESOLUTION : Try removing releasever file using the below command and check whether it fixes the issue\n\n    #rm /etc/yum/vars/releasever" + colors.ENDC)


def msg_https_404_error_eus():
    logging.error(colors.RED + "It seems repo is EUS and file /etc/yum/vars/releasever is either not available or have incorrect content" + colors.ENDC)
    logging.info(colors.GREEN + "RESOLUTION : Try updating releasever file using the below command and check whether it fixes the issue\n\n    #echo $(. /etc/os-release && echo $VERSION_ID) > /etc/yum/vars/releasever" + colors.ENDC)

def msg_https_404_possible_cause():
    logging.info(colors.GREEN + "RESOLUTION : if repo is non-eus try executing #rm /etc/yum/vars/releasever and see whether it fixes the issue. if repo is eus Try executing #echo $(. /etc/os-release && echo $VERSION_ID) > /etc/yum/vars/releasever and see whether it fixes the issue" +colors.ENDC)

def msg_virtual_appliance():
   logging.error(colors.RED + "\nIt seems most likely, the VM is either behind a Firewall or Load Balancer or Proxy enabled which is causing the repo connectivity issue. Kindly go through the below scenarios and take necessary action as suggested to fix the issue" + colors.ENDC)
   logging.info(colors.YELLOW + "\nScenario 1 : VM is behind a Firewall / NVA "+ colors.ENDC)
   logging.info("\nTroubleshooting steps: Validate whether VM is behind firewall / NVA.If yes, try any of the below action items \nEither allow these IPs in Firewall or add UDR for below RHUI IPs with next-hop as internet so that the requests to RHUI IPs from Azure VM directly reaches internet by skipping the firewall \n # Azure Global\n 13.91.47.76\n 40.85.190.91\n 52.187.75.218\n 52.174.163.213\n 52.237.203.198\n\n # Azure US Government\n 13.72.186.193\n 13.72.14.155\n 52.244.249.194\n\n # Azure Germany\n 51.5.243.77\n 51.4.228.145\n\n Reference urls:\n https://docs.microsoft.com/en-us/azure/virtual-machines/workloads/redhat/redhat-rhui \n https://docs.microsoft.com/en-us/azure/virtual-network/virtual-networks-udr-overview")
   logging.info(colors.YELLOW + "\nScenario 2 : VM is behind Standard Internal Load Balancer" + colors.ENDC)
   logging.info("\nTroubleshooting steps: Validate whether VM is behind a STANDARD INTERNAL LOAD BALANCER.If yes, try any of the below solutions \n 1. Assign a Standard SKU public IP address as an Instance-Level Public IP address to the virtual machine resource \n 2. Place the virtual machine resource in the backend pool of a public Standard Load Balancer")
   logging.info(colors.YELLOW + "\nScenario 3 : Proxy enabled at OS level" + colors.ENDC)
   logging.info("Troubleshooting steps: Execute the below command to verify if proxy is enabled\n     #export | grep -i http \n In case if the above command returns output, try disabling the proxy temporarily by running below commands and check whether it resolves the issue \n     #unset http_proxy \n     #unset https_proxy \n If the issue is resolved, you may need to get in touch with in-house network team to whitelist the RHUI IPs or you can try adding the parameter proxy=_none_ in /etc/yum.conf to resolve the issue" )
   exit()

def msg_dns_resolution_error():
   logging.error (colors.RED +"Issue with name resolution."+ colors.ENDC)
   logging.info (colors.GREEN + "RESOLUTION : Please validate your nameserver entries in /etc/resolv.conf file, also make sure that there is no customized entries for RHUI servers in /etc/hosts and then rerun this script" + colors.ENDC)
   exit()

def msg_https_403_error():
   logging.error (colors.RED + "\nSeems to be some internal error which is causing the connectivity issue to RHUI server.Please apply the temporary workaround which is mentioned below and see whether it fixes the issue, till our engineering team provides permanent fix" + colors.ENDC)
   logging.info ("\nWORKAROUND:\n#########For Azure Global add the below entries in /etc/hosts file#######\n 13.91.47.76  rhui-1.micosoft.com rhui-2.micosoft.com rhui-3.micosoft.com\n 40.85.190.91  rhui-1.micosoft.com rhui-2.micosoft.com rhui-3.micosoft.com\n 52.187.75.218  rhui-1.micosoft.com rhui-2.micosoft.com rhui-3.micosoft.com\n 52.174.163.213  rhui-1.micosoft.com rhui-2.micosoft.com rhui-3.micosoft.com\n 52.237.203.198  rhui-1.micosoft.com rhui-2.micosoft.com rhui-3.micosoft.com\n\n######### For Azure Azure US Government add the below entries in /etc/hosts file#######\n 13.72.186.193  rhui-1.micosoft.com rhui-2.micosoft.com rhui-3.micosoft.com\n 13.72.14.155  rhui-1.micosoft.com rhui-2.micosoft.com rhui-3.micosoft.com\n 52.244.249.194  rhui-1.micosoft.com rhui-2.micosoft.com rhui-3.micosoft.com")

def msg_cert_expiry_error():
   logging.error(colors.RED + "\nSeems RHUI client certificate is expired. rhui-azure package requires an update" + colors.ENDC)
   logging.info(colors.GREEN + "Fix : Please execute the below command as mentioned in https://docs.microsoft.com/en-us/azure/virtual-machines/workloads/redhat/redhat-rhui for installing the latest version of rhui-azure package" + colors.ENDC)
   logging.info ("\n #yum update --disablerepo=* --enablerepo='*microsoft*'")

def msg_rhel8_possible_causes():
   logging.error(colors.RED + "Failed to synchronize cache for repo. Possible scenarios are listed below" + colors.ENDC)
   logging.info(colors.YELLOW + "\nscenario 1: Execute '#rpm -qa | grep -i rhui' and checked whether repo is eus or non-eus" + colors.ENDC)
   msg_https_404_possible_cause()
   logging.info(colors.YELLOW + "\nscenario 2: if '#openssl x509 -in /etc/pki/rhui/product/content*.crt -text|grep -E 'Not Before|Not After'' shows 'Not After' date in past then" + colors.ENDC)
   msg_cert_expiry_error()

def msg_python_config_issue():
  logging.error(colors.RED + "seems to be configuration issue with python. Fix python config issues and re-run this script" + colors.ENDC)
