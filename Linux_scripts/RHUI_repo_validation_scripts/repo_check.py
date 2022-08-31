import os
import sys
import logging
from logging.handlers import RotatingFileHandler
from logging import handlers
import subprocess
import platform
from threading import Timer
import socket
import time
from scenarios import *

VERSION = "1.0.0"
SCRIPT_NAME = "repo_check.py"


########### Function for RHEL VMs ##############
def redhat():
      ##### checking connectivity of RHEL Repo server IPs #####

   def ip_tables_check():
      reject_rule = subprocess.Popen("iptables -L OUTPUT -v -n | egrep -i 'reject|drop'", stdout=subprocess.PIPE, shell=True)
      rej_rule = str(reject_rule.communicate()[0])
      error_list = ["tcp dpt:443 reject-with icmp-port-unreachable", "tcp dpt:https reject-with icmp-port-unreachable", "   reject-with icmp-port-unreachable", "tcp dpt:443"]
      for error in error_list:
         if error in rej_rule:
            logging.info(rej_rule)
            msg_ip_tables_check()

   def isOpen(servers,port):
      s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
      try:
         s.settimeout(2)
         s.connect((servers, int(port)))
         s.shutdown(2)
      except:
         msg_rhui_ip_connectivity_error(servers)
         ip_tables_check()
         msg_virtual_appliance()
 
   def isresolving(servers):
      resolution_check = subprocess.Popen("dig servers", stdout=subprocess.PIPE, shell=True)
      reslov_check = str(resolution_check.communicate()[0])
      if "connection timed out; no servers could be reached" in reslov_check:
         msg_dns_resolution_error()
           

   ##### rhui connectivity check ########

   def rhui_ip_conn_check():
      logging.info("checking connectivity of RHUI repo server IPs \n")
      servers = ["rhui-1.microsoft.com", "rhui-2.microsoft.com", "rhui-3.microsoft.com"]
      port = "443"
      for server in servers:
         isresolving(server)
         isOpen(server,port)
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
     except:
         logging.error("Issue happened while executing yum clean all command or while gathering yum processes list. Fix the issue and rerun the script")
     finally:
        my_timer.cancel()


   ##### executes "yum check-update" command and gathers the ouput and error ########
  

   def yum_repo_check():
      logging.info("Cleaning up yum")
      yum_clean_up()
      time.sleep(5)
      logging.info("yum check-update is being executed at the backend. This might take around 30 - 180 seconds to complete. Please wait .......")
      cmd = ['yum', 'check-update']
      yum = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
      kill = lambda process: process.kill()
      my_timer = Timer(125, kill, [yum])
      try:
         my_timer.start()
         stdout, stderr = yum.communicate()
         return stderr
      except:
         logging.error("There seems to be some issue while processing yum check-update command output, rerun the script after fixing the issue")
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

      elif "Error: Failed to synchronize cache for repo" in status:  
         msg_rhel8_possible_causes()

      elif "Failed to download metadata for repo" in status: 
         msg_rhel8_possible_causes()
   
      elif "except KeyboardInterrupt" in status:
         msg_python_config_issue()
        
     
      else:
         msg_new_scenario()
   error_check() 


def disclaimer():
   logging.info("\n\n Disclaimer : This script helps in detecting RHUI server connectivity issues only for Redhat-6,7 and 8 Pay as you go images deployed from Azure market place. Upon execution this script does not modify anything on the VM instead it will provide suggestion for fix based on the error. Always, download the latest version of the script from git hub url 'https://github.com/Azure/azure-support-scripts/tree/master/Linux_scripts/RHUI_repo_validation_scripts' which will help in effective troubleshooting and also have bugs addressed.\n")
   logging.info("\n Please record your consent for script execution (yes/no):")
   val=sys.stdin.readline()
   option=val.rstrip()
   logging.debug(option)
   if ( option == "no" ):
      logging.info("Aborting the execution")
      exit()
   elif ( option == "yes" ):
      logging.info("consent recorded,starting the execution ...")
   else:
      logging.error("invalid input, Please try again")
      exit()


def log_func():
   LOGFILE = "/var/log/azure/rhui_script.log"
   log = logging.getLogger('')
   log.setLevel(logging.DEBUG)
   format = logging.Formatter("%(asctime)s - %(levelname)s - %(message)s")
   ch = logging.StreamHandler(sys.stdout)
   ch.setFormatter(format)
   log.addHandler(ch)
   fh = logging.FileHandler(LOGFILE)
   fh.setFormatter(format)
   log.addHandler(fh)

def script_version():
   logging.info(SCRIPT_NAME + " " + VERSION)

def os_distro():
  os_distro = platform.linux_distribution()
  os_ver = (os_distro[0])
  if "Red Hat Enterprise Linux" in os_ver:
     redhat()
  else:
     msg_os_dist_error()

def __init__():
   uid = int(os.getuid())
   if uid == 0:
      log_func()
      script_version()
      disclaimer()
      os_distro()
   else:
     msg_uid_error()

__init__()
