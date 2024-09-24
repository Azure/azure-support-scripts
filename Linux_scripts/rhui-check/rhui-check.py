#!/bin/env bash

import argparse
import logging
import os
import re
import subprocess
import time
import sys
#import urllib.request
eus = 0

######################################################
# logger the output of the script into /var/log/rhuicheck.log file
######################################################
class CustomFormatter(logging.Formatter):

    black =    "\x1b[30;1m"
    grey =     "\x1b[30;0m"
    red =      "\x1b[31;20m"
    green =    "\x1b[32;20m"
    yellow =   "\x1b[33;20m"
    bright_red = "\x1b[91;1m"
    bold_red = "\x1b[31;1m"
    bold_green =    "\x1b[32;1m"
    bold_yellow =   "\x1b[33;1m"
    reset =    "\x1b[0m"


    # format = "%(asctime)s - %(name)s - %(levelname)s - %(message)s (%(filename)s:%(lineno)d)"
    format = "%(asctime)s - %(name)s - %(levelname)s - %(message)s"

    FORMATS = {
        logging.DEBUG: black + format + reset,
        logging.INFO: bold_green + format + reset,
        logging.WARNING: bold_yellow + format + reset,
        logging.ERROR: bright_red + format + reset,
        logging.CRITICAL: bold_red + format + reset
    }

    def format(self, record):
        log_fmt = self.FORMATS.get(record.levelno)
        formatter = logging.Formatter(log_fmt)
        return formatter.format(record)



if os.geteuid() != 0:
   logger.critical('This script needs to execute with root privileges')
   logger.critical('You could leverage the sudo tool to gain administrative privileges')
   exit(1)

def start_logging(debug_level = False):
    """This function sets up the logging configuration for the script and writes the log to /var/log/rhuicheck.log"""

    logger = logging.getLogger(__name__)

    console_handler = logging.StreamHandler()
    color_formatter = CustomFormatter()
    console_handler.setFormatter(color_formatter)    
    logger.addHandler(console_handler)
    console_handler.setLevel(logging.INFO)

    if debug_level:
        console_handler.setLevel(logging.DEBUG)

    try:
        log_filename = '/var/log/rhuicheck.log'
        file_handler = logging.FileHandler(filename=log_filename)
        plain_formatter = logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")
        file_handler.setFormatter(plain_formatter)    
    except:
        logger.critical("Unable to create log file in /var/log/rhuicheck.log, make sure the script is running with root privileges, the filesystem has enough space and it is not in Read-Only mode")
        exit(1)
    else:
        file_handler.setLevel(logging.DEBUG)
        logger.addHandler(file_handler)

    logger.setLevel(logging.DEBUG)
    return logger
       
parser = argparse.ArgumentParser()
parser.add_argument(  '--debug','-d',
                      action='store_true',
                      help='Use DEBUG level')
args = parser.parse_args()
logger = start_logging(args.debug)

try:
    import requests
except ImportError:
    logger.critical("'requests' python module not found but it is required for this test script, review your python instalation")
    exit(1) 

rhui3 = ['13.91.47.76', '40.85.190.91', '52.187.75.218']
rhui4 = ['52.136.197.163', '20.225.226.182', '52.142.4.99', '20.248.180.252', '20.24.186.80']
rhuius = ['13.72.186.193', '13.72.14.155', '52.224.249.194']
system_proxy = dict()
bad_hosts = list()
 
pattern = dict()
pattern['clientcert'] = r'^/[/a-zA-Z0-9_\-]+\.(crt)$'
pattern['clientkey']  = r'^/[/a-zA-Z0-9_\-]+\.(pem)$'
pattern['repofile']    = r'^/[/a-zA-Z0-9_\-\.]+\.(repo)$'


try:
    import configparser
except ImportError:
    import ConfigParser as configparser

class localParser(configparser.ConfigParser):
    def as_dict(self):
        d = dict(self.sections)
        for k in d:
            d[k] = dict(self._defaults, **d[k])
            d[k].pop('__name__', None)
        return d

def get_host(url):
    urlregex = '[^:]*://([^/]*)/.*'
    host_match = re.match(urlregex, url)
    return host_match.group(1)

def validate_ca_certificates():
    """
    Used to verify whether the default certificate database has been modified or not
    """
    logger.debug('Entering validate_ca-certificates()')
    reinstall_ca_bundle_link = 'https://learn.microsoft.com/troubleshoot/azure/virtual-machines/linux/troubleshoot-linux-rhui-certificate-issues?tabs=rhel7-eus%2Crhel7-noneus%2Crhel7-rhel-sap-apps%2Crhel8-rhel-sap-apps%2Crhel9-rhel-sap-apps#solution-4-update-or-reinstall-the-ca-certificates-package'

    try:
        result = subprocess.call('/usr/bin/rpm -V ca-certificates', shell=True)
    except:
        logger.error('Unable to check server side certificates installed on the server')
        logger.error('Use {} to reinstall the ca-certificates'.format(reinstall_ca_bundle_link))
        
        exit(1)
   
    if result:
        logger.error('The ca-certificate package is invalid, you can reinstall follow {} to reinstall it manually'.format(reinstall_ca_bundle_link))
        exit(1)
    else:
        return True

def connect_to_host(url, selection, mysection):

    try:
        uname = os.uname()
    except:
        logger.critical('Unable to identify OS version')
        exit(1)    

    try:
        basearch = uname.machine
    except AttributeError:
        basearch = uname[-1]

    try:
        baserelease = uname.release
    except AttributeError:
        baserelease = uname[2]

    if eus:
        fd = open('/etc/yum/vars/releasever')
        releasever = fd.readline().strip()
    else:
        releasever  = re.sub(r'^.*el([0-9][0-9]*).*',r'\1',baserelease)
        if releasever == '7':
            releasever = '7Server'

    url = url+"/repodata/repomd.xml"
    url = url.replace('$releasever',releasever)
    url = url.replace('$basearch',basearch)
    logger.debug('baseurl for repo {} is {}'.format(mysection, url))

    headers = {'content-type': 'application/json'}
    s = requests.Session()
    local_proxy = get_proxies(selection, mysection)

    cert = ()
    try:
        cert=(selection.get(mysection, 'sslclientcert'), selection.get(mysection, 'sslclientkey'))
    except:
        logger.warning('Client certificate and/or client key attribute not found for {}, testing connectivity w/o certificates'.format(mysection))
        cert=()

    try:
        r = s.get(url, cert=cert, headers=headers, timeout=5, proxies=local_proxy)
    except requests.exceptions.Timeout:
        logger.warning('TIMEOUT: Unable to reach RHUI URI {}'.format(url))
        return False
    except requests.exceptions.SSLError:
        validate_ca_certificates()
        logger.warning('PROBLEM: MITM proxy misconfiguration. Proxy cannot intercept certs for {}'.format(url))
        return 1
    except requests.exceptions.ProxyError:
        logger.warning('PROBLEM: Unable to use the proxy gateway when connecting to RHUI server {}'.format(url))
        return False
    except requests.exceptions.ConnectionError as e:
        logger.warning('PROBLEM: Unable establish connectivity to RHUI server {}'.format(url))
        logger.error('{}'.format(e))
        return False
    except OSError:
        validate_ca_certificates()
        raise()
    except Exception as e:
        logger.warning('PROBLEM: Unknown error, unable to connect to the RHUI server {}'.format(url))
        raise(e)
        return False
    else:
        if r.status_code == 200:
            logger.debug('The RC for this {} link is {}'.format(url, r.status_code))
            return True
        elif r.status_code == 404:
            logger.error("Unable to find the contents for repo {}, make sure to use the correct version lock if you're using EUS repositories".format(mysection))
            logger.error("for more detailed information and valid levels consult: https://access.redhat.com/support/policy/updates/errata#RHEL8_and_9_Life_Cycle")
            return False
        else:
            logger.warning('The RC for this {} link is {}'.format(url, r.status_code))
            return False

def rpm_names():
    """
    Identifies the RHUI repositories installed in the server and returns a list of RHUI rpms installed in the server.
    """
    logger.debug('Entering repo_name()')
    result = subprocess.Popen("rpm -qa 'rhui-*'", shell=True, stdout=subprocess.PIPE)
    rpm_names = result.stdout.readlines()
    rpm_names = [ rpm.decode('utf-8').strip() for rpm in rpm_names ]
    if rpm_names:
        for rpm in rpm_names:
            logger.debug('Server has this RHUI pkg: {}'.format(rpm))
        return(rpm_names)
    else:
        logger.critical('could not find a specific RHUI package installed, please refer to the documentation and install the apropriate one ')
        logger.critical('Consider using the following document to install RHUI support https://learn.microsoft.com/troubleshoot/azure/virtual-machines/troubleshoot-linux-rhui-certificate-issues#cause-3-rhui-package-is-missing')
        exit(1) 

def get_pkg_info(package_name):
    ''' Identifies rhui package name(s)'''
    logger.debug('Entering get_pkg_info()')

    logger.debug('Entering pkg_info function')
    try:
        result = subprocess.Popen(['rpm', '-q', '--list', package_name], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        info = result.stdout.read().decode('utf-8').strip().split('\n')
        
        hash_info = {}
        for key in pattern.keys():
            logger.debug('checking key {}'.format(key))
            for data in info:
                logger.debug('checking key {} and data {}'.format(key, data))
                if re.match(pattern[key], data):
                    hash_info[key] = data
                    break
    except:
        logger.critical('Failed to grab RHUI RPM details, rebuild RPM database')
        exit(1)
    else:
        return hash_info


def verify_pkg_info(package_name, rpm_info):
    ''' verifies basic elements of the RHUI package are present on the server '''

    errors = 0
    for keyname in pattern.keys():
        if keyname not in rpm_info.keys():
            logger.critical('{} file definition not found in RPM metadata, {} rpm needs to be reinstalled'.format(keyname, package_name))
            errors += 1
        else: 
            if not os.path.exists(rpm_info[keyname]):
                logger.critical('{} file not found in server, {} rpm needs to be reinstalled'.format(keyname, package_name))
                errors += 1

    if errors:
        data_link = "https://learn.microsoft.com/troubleshoot/azure/virtual-machines/troubleshoot-linux-rhui-certificate-issues#cause-2-rhui-certificate-is-missing"
        logger.critical('follow {} for information to install the RHUI package'.format(data_link))
        exit(1)

    return True

def default_policy():
    """"Returns a boolean whether the default encryption policies are set to default via the /etc/crypto-policies/config file, if it can't test it, the result will be set to true."""
    try:
        uname = os.uname()
    except:
        logger.critical('Unable to identify OS version')
        exit(1)    

    try:
        baserelease = uname.release
    except AttributeError:
        baserelease = uname[2]

    policy_releasever  = re.sub(r'^.*el([0-9][0-9]*).*',r'\1',baserelease)

    # return true for EL7
    if policy_releasever == '7':
        return True

    try:
        policy = subprocess.check_output('/bin/update-crypto-policies --show', shell=True)
        policy = policy.decode('utf-8').strip()
        if policy != 'DEFAULT':
            return False
    except:
        return True

    return True

def expiration_time(cert_path):
    """ 
    Checks whether client certificate stored at cert_path has expired or not.
    """
    logger.debug('Entering expiration_time()')
    logger.debug('Checking certificate expiration time')
    try:
        result = subprocess.check_call('openssl x509 -in {} -checkend 0 > /dev/null 2>&1 '.format(cert_path),shell=True)

    except subprocess.CalledProcessError:
        logger.critical('Client RHUI Certificate has expired, please update the RHUI rpm')
        logger.critical('Refer to: https://learn.microsoft.com/troubleshoot/azure/virtual-machines/troubleshoot-linux-rhui-certificate-issues#cause-1-rhui-client-certificate-is-expired')
        exit(1)

    if not default_policy():
        logger.critical('Client crypto policies not set to DEFAULT')
        logger.critical('Refer to: https://learn.microsoft.com/troubleshoot/azure/virtual-machines/linux/troubleshoot-linux-rhui-certificate-issues?tabs=rhel7-eus%2Crhel7-noneus%2Crhel7-rhel-sap-apps%2Crhel8-rhel-sap-apps%2Crhel9-rhel-sap-apps#cause-5-verification-error-in-rhel-version-8-or-9-ca-certificate-key-too-weak')
        exit(1) 

def read_yum_dnf_conf():
    """Read /etc/yum.conf or /etc/dnf/dnf.conf searching for proxy information"""
    logger.debug('Entering read_yum_dnf_conf()')

    try:
        yumdnfdotconf = localParser(allow_no_value=True, strict=False)
    except TypeError:
        yumdnfdotconf = localParser(allow_no_value=True)

    try:
        file = '/etc/yum.conf'
        with open(file) as stream:
            yumdnfdotconf.read_string('[default]\n' + stream.read())
    except AttributeError:
        yumdnfdotconf.add_section('[default]')
        yumdnfdotconf.read(file)
    except Exception as e:
        logger.error('Problems reading /etc/yum.conf, on RHEL8+ it is a symbolic link to /etc/dnf/dnf.conf')
        raise

    return yumdnfdotconf


def get_proxies(parser_object, mysection):
    ''' gets the proxy from a configparser section object pointd by the proxy variable if defined in the configuration file '''
    proxy_info = dict()

    # proxy_regex = '(^[^:]*)(:(//)(([^:]*)(:([^@]*)){0,1}@){0,1}.*)?'
    proxy_regex = '(^[^:]*):(//)(([^:]*)(:([^@]*)){0,1}@){0,1}.*'

    for key in ['proxy', 'proxy_user', 'proxy_password']:
        try:
            value = parser_object.get(mysection, key)

        except configparser.NoOptionError: 
            continue
        except Exception as e:
            logger.error('Problems handling the parser object')
            raise
        else:
            proxy_info[key] = value

    try:
        myproxy = proxy_info['proxy']
        if myproxy:
            ''' Get the scheme used in a proxy for example http from http://proxy.com/.
                Have to remove the last : as it is not part of the scheme.            '''
            proxy_match = re.match(proxy_regex, myproxy)
            if proxy_match:
                scheme = proxy_match.group(1)
                # proxy_info['scheme'] = scheme
                proxy_info['scheme'] = 'https'
            else:
                logger.critical('Invalid proxy configuration, please make sure it is a valid one')
                exit(1)
        else:
            return system_proxy
    except KeyError:
        return system_proxy

    if proxy_match.group(4) and ('proxy_user' in proxy_info.keys()):
        logger.warning('proxy definition already has a username defined and proxy_user is also defined, there might be conflicts using the proxy, repair')

    if proxy_match.group(6) and ('proxy_password' in proxy_info.keys()):
        logger.warning('proxy definition already has a username and password defined and proxy_password is also defined, there might be conflicts using the proxy, repair')

    if ('proxy_password' in proxy_info.keys() and proxy_info['proxy_password'])  and ('proxy_user' not in proxy_info.keys()):
        logger.warning('proxy_password defined but there is no proxy user, this could be causing problems')
        logger.warning('ignoring proxy_password')

    if ('proxy_user' in proxy_info.keys() and proxy_info['proxy_user']) and not proxy_match.group(4):
        ####### need to insert proxy user and passwod in proxy link
        proxy_prefix = myproxy[:proxy_match.end(2)]
        proxy_suffix = myproxy[proxy_match.end(2):]

        if ('proxy_password' in proxy_info.keys()) and proxy_info['proxy_password'] and not proxy_match.group(6):
            myproxy = '{}{}:{}@{}'.format(proxy_prefix, proxy_info['proxy_user'], proxy_info['proxy_password'], proxy_suffix)
        else:
            myproxy = '{}{}@{}'.format(proxy_prefix, proxy_info['proxy_user'], proxy_suffix)

    logger.critical('Found proxy information in the config files, make sure connectivity works thru the proxy')
    return {proxy_info['scheme']: myproxy}
    

def check_rhui_repo_file(path):
    """ 
    Handling the consistency of the Red Hat repositories
    path:    Indicates where the rhui repo is stored.
    returns: A RHUI repository configuration stored in a configparser structure, each repository is a section.
    """   
    logger.debug('Entering check_rhui_repo_file()')

    logger.debug('RHUI repo file is {}'.format(path))
    try:
        reposconfig = localParser()
        try:
            with open(path) as stream:
                reposconfig.read_string('[default]\n' + stream.read())
        except AttributeError:
            reposconfig.add_section('[default]')
            reposconfig.read(path)

        logger.debug('{}'.format(str(reposconfig.sections())))
        return reposconfig

    except configparser.ParsingError:
        logger.critical('{} does not follow standard REPO config format, reconsider reinstall RHUI rpm and try again'.format(path))
        exit(1)


def check_repos(reposconfig):
    """ Checks whether the rhui-microsoft-azure-* repository exists and tests whether it's enabled or not."""
    global eus 

    logger.debug('Entering microsoft_repo()')
    rhuirepo = '^(rhui-)?microsoft.*'
    eusrepo  = '.*-(eus|e4s)-.*'
    microsoft_reponame = ''
    enabled_repos = list()

    for repo_name in reposconfig.sections():
        if re.match('\[*default\]*', repo_name):
            continue

        try:
            enabled =  int(reposconfig.get(repo_name, 'enabled').strip())
        except configparser.NoOptionError:
            enabled = 1
        
    
        if re.match(rhuirepo, repo_name):
            microsoft_reponame = repo_name
            if enabled:
                logger.info('Using Microsoft RHUI repository {}'.format(repo_name))
            else:
                logger.critical('Microsoft RHUI repository not enabled, please enable it with the following command')
                logger.critical('yum-config-manager --enable {}'.format(repo_name))
                exit(1)

        if enabled:
           # only check enabled repositories 
           enabled_repos.append(repo_name)
        else:
           continue

        if re.match(eusrepo, repo_name):
            eus = 1

    if not microsoft_reponame:
        reinstall_link = 'https://learn.microsoft.com/troubleshoot/azure/virtual-machines/linux/troubleshoot-linux-rhui-certificate-issues?source=recommendations&tabs=rhel7-eus%2Crhel7-noneus%2Crhel7-rhel-sap-apps%2Crhel8-rhel-sap-apps%2Crhel9-rhel-sap-apps#solution-2-reinstall-the-eus-non-eus-or-sap-rhui-package'
        logger.critical('Microsoft RHUI repository not found, reinstall the RHUI package following{}'.format(reinstall_link))
        exit(1)
       
    if eus:
        if not os.path.exists('/etc/yum/vars/releasever'):
            logger.critical('Server is using EUS repostories but /etc/yum/vars/releasever file not found, please correct and test again')
            logger.critical('Refer to: https://learn.microsoft.com/azure/virtual-machines/workloads/redhat/redhat-rhui?tabs=rhel7#rhel-eus-and-version-locking-rhel-vms, to select the appropriate RHUI repo')
            exit(1)

    if not eus:
        if os.path.exists('/etc/yum/vars/releasever'):
            logger.critical('Server is using non-EUS repos and /etc/yum/vars/releasever file found, correct and try again')
            logger.critical('Refer to: https://learn.microsoft.com/azure/virtual-machines/workloads/redhat/redhat-rhui?tabs=rhel7#rhel-eus-and-version-locking-rhel-vms, to select the appropriate RHUI repo')
            exit(1)

    return enabled_repos


def ip_address_check(host):
    ''' Checks whether the parameter is within the RHUI4 infrastructure '''

    try:
        import socket
    except ImportError:
        logger.critical("'socket' python module not found but it is required for this test script, review your python instalation")
        exit(1) 

    try:
        rhui_ip_address = socket.gethostbyname(host)

        if rhui_ip_address  in rhui4:
            logger.debug('RHUI host {} points to RHUI4 infrastructure'.format(host))
            return True
        elif rhui_ip_address in rhui3 + rhuius:
            reinstall_link = 'https://learn.microsoft.com/troubleshoot/azure/virtual-machines/linux/troubleshoot-linux-rhui-certificate-issues?tabs=rhel7-eus%2Crhel7-noneus%2Crhel7-rhel-sap-apps%2Crhel8-rhel-sap-apps%2Crhel9-rhel-sap-apps#solution-2-reinstall-the-eus-non-eus-or-sap-rhui-package'
            logger.error('RHUI server {} points to decommissioned infrastructure, reinstall the RHUI package'.format(host))
            logger.error('for more detailed information, use: {}'.format(reinstall_link))
            bad_hosts.append(host)
            warnings = warnings + 1
            return False
        else:
            logger.critical('RHUI server {} points to an invalid destination, validate /etc/hosts file for any invalid static RHUI IPs or reinstall the RHUI package'.format(host))
            logger.warning('Please make sure your server is able to resolve {} to one of the ip addresses'.format(host))
            rhui_link = 'https://learn.microsoft.com/azure/virtual-machines/workloads/redhat/redhat-rhui?tabs=rhel7#the-ips-for-the-rhui-content-delivery-servers'
            logger.warning('listed in this document {}'.format(rhui_link))
            return False
    except Exception as e:
         logger.warning('Unable to resolve IP address for host {}'.format(host))
         logger.warning('Please make sure your server is able to resolve {} to one of the ip addresses'.format(host))
         rhui_link = 'https://learn.microsoft.com/azure/virtual-machines/workloads/redhat/redhat-rhui?tabs=rhel7#the-ips-for-the-rhui-content-delivery-servers'
         logger.warning('listed in this document {}'.format(rhui_link ))
         logger.warning(e)
         return False

def connect_to_repos(reposconfig, check_repos):
    """Downloads repomd.xml from each enabled repository."""

    logger.debug('Entering connect_to_repos()')
    rhuirepo = '^rhui-microsoft.*'
    warnings = 0

    for repo_name in check_repos:

        if re.match('\[*default\]*', repo_name):
            continue

        try:
            baseurl_info = reposconfig.get(repo_name, 'baseurl').strip().split('\n')
        except configparser.NoOptionError:
            reinstall_link = 'https://learn.microsoft.com/troubleshoot/azure/virtual-machines/linux/troubleshoot-linux-rhui-certificate-issues?source=recommendations&tabs=rhel7-eus%2Crhel7-noneus%2Crhel7-rhel-sap-apps%2Crhel8-rhel-sap-apps%2Crhel9-rhel-sap-apps#solution-2-reinstall-the-eus-non-eus-or-sap-rhui-package'
            logger.critical('The baseurl is a critical component of the repository stanza and it is not found for repo {}'.format(repo_name))
            logger.critical('Follow this link to reinstall the Microsoft RHUI repo {}'.format(reinstall_link))
            exit(1)

        successes = 0
        for url in baseurl_info:
            url_host = get_host(url)
            if not ip_address_check(url_host):
                bad_hosts.append(url_host)
                continue

            if connect_to_host(url, reposconfig, repo_name):
                successes += 1

        if successes == 0:
            error_link = 'https://learn.microsoft.com/azure/virtual-machines/workloads/redhat/redhat-rhui?tabs=rhel9#the-ips-for-the-rhui-content-delivery-servers'
            logger.critical('PROBLEM: Unable to successfully download repository metadata from the any of the configured RHUI server(s).')
            logger.critical('         please ensure the server is able to resolve to a valid IP address, communication is allowed to the addresses listed in the public document {}'.format(error_link))
            logger.critical('         and, if using EUS repositories, have a valid EUS value in /etc/dnf/vars/releasever file')
            sys.exit(1)



logging.getLogger("requests").setLevel(logging.WARNING)
logging.getLogger("urllib3").setLevel(logging.WARNING)

yum_dnf_conf = read_yum_dnf_conf()
system_proxy = get_proxies(yum_dnf_conf,'main')

for package_name in rpm_names():
    data = get_pkg_info(package_name)
    if verify_pkg_info(package_name, data):
        expiration_time(data['clientcert'])

        reposconfig = check_rhui_repo_file(data['repofile'])
        check_repos = check_repos(reposconfig)
        connect_to_repos(reposconfig, check_repos)


logger.info('All communication tests to the RHUI infrastructure have passed, if problems persisit, remove third party repositories and test again')
logger.info('The RHUI repository configuration file is {}, move any other configuration file to a temporary location and test again'.format(data['repofile']))
