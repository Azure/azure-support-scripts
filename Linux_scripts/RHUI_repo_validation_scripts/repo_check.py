import os
import subprocess
import platform
from threading import Timer
import socket
import time
from scenarios import *

########### Function for RHEL VMs ##############
def redhat():
      ##### checking connectivity of RHEL Repo server IPs #####

   def ip_tables_check():
      reject_rule = subprocess.Popen("iptables -L OUTPUT -v -n | grep -i reject", stdout=subprocess.PIPE, shell=True)
      rej_rule = str(reject_rule.communicate()[0])
      if "tcp dpt:443 reject-with icmp-port-unreachable" in rej_rule or "tcp dpt:https reject-with icmp-port-unreachable" in rej_rule or "   reject-with icmp-port-unreachable" in rej_rule:
         print(rej_rule)
         msg_ip_tables_check()

   def isOpen(ip,port):
      s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
      try:
         s.settimeout(2)
         s.connect((ip, int(port)))
         s.shutdown(2)
      except:
         msg_rhui_ip_connectivity_error(ip)
         ip_tables_check()
         msg_virtual_appliance()

   ##### rhui-ip connectivity check ########

   def rhui_ip_conn_check():
      print ("\nchecking connectivity of RHUI repo server IPs")
      ip = ["13.91.47.76", "40.85.190.91", "52.187.75.218", "52.174.163.213", "52.237.203.198"]
      port = "443"
      for var in ip:
         isOpen(var,port)
      msg_rhui_ip_connectivity_success()
   rhui_ip_conn_check()

   ##### rhui-package validation check ########

   def rhui_package_check():
      rpm_check = subprocess.Popen("rpm -qa | grep -w rhui-azure", stdout=subprocess.PIPE, shell=True)
      rhui_check = str(rpm_check.communicate()[0])
      if "rhui-azure" in rhui_check:
         if "eus" in rhui_check:
             repo_type = "eus"
             return(repo_type)
         else:
             repo_type = "non-eus"
             return(repo_type)
      else:
         msg_rhui_package_check_error()
   rhui_package_check()

   ##### executes "yum cleanall" and also checks whether any other app is holding yum lock########

   def yum_clean_up():
     cmd = ['yum', 'clean', 'all']
     yum_clean = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
     kill = lambda process: process.kill()
     my_timer = Timer(1, kill, [yum_clean])
     try:
        my_timer.start()
        stdout, stderr = yum_clean.communicate()
        if "Another app is currently holding the yum lock" in stderr.decode() or "Waiting for process with" in stderr.decode():
           msg_multiple_yum_process()
     finally:
        my_timer.cancel()


   ##### executes "yum check-update" command and gathers the ouput and error ########
  

   def yum_repo_check():
      print ("\nCleaning up yum")
      yum_clean_up()
      time.sleep(5)
      print  ("yum check-update is being executed at the backend. This might take around 30 - 180 seconds to complete. Please wait .......")
      cmd = ['yum', 'check-update']
      yum = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
      kill = lambda process: process.kill()
      my_timer = Timer(125, kill, [yum])
      try:
         my_timer.start()
         stdout, stderr = yum.communicate()
         return stderr
      finally:
         my_timer.cancel()


   ###### Provides recommendation for the fix after validating the errors. #######
   
   def error_check():
      status = str(yum_repo_check())

      if "".__eq__(status) or "b''" in status:
         msg_yum_repolist_success()

      elif "HTTPS Error 404" in status and rhui_package_check() is not "eus":
         msg_https_404_error_non_eus()
      
      elif "HTTPS Error 404" in status and rhui_package_check() is "eus":
         msg_https_404_error_eus()

      elif "Connection timed out after 30001 milliseconds" in status or "Connection timed out after 30000 milliseconds" in status:
         msg_virtual_appliance()

      elif "HTTPS Error 403 - Forbidden" in status:
         msg_https_403_error()

      elif "SSL peer rejected your certificate as expired" in status or "Certificate has expired" in status:
         msg_cert_expiry_error()

      elif "Could not resolve host" in status:
         msg_dns_resolution_error()
      
      elif "Error: Failed to synchronize cache for repo" in status:  
         msg_rhel8_possible_causes()

      elif "Failed to download metadata for repo" in status: 
         msg_rhel8_possible_causes()
   
      elif "except KeyboardInterrupt" in status:
         msg_python_config_issue()
        
     
      else:
         msg_new_scenario()
   error_check() 

def os_distro():
  os_distro = platform.linux_distribution()
  os_ver = (os_distro[0])
  if "Red Hat Enterprise Linux" in os_ver:
     redhat()
  else:
     msg_os_dist_error()

def main():
   uid = int(os.getuid())
   if uid == 0:
      os_distro()
   else:
     msg_uid_error()

if __name__=="__main__":
    main()
