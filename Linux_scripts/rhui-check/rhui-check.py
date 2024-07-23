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
try:
    import requests
except ImportError:
    logging.critical("{}'requests' python module not found but it is required for this test script, review your python instalation{}".format(bcolors.FAIL, bcolors.ENDC))
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

class bcolors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKCYAN = '\033[96m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'

def get_host(url):
    urlregex = '[^:]*://([^/]*)/.*'
    host_match = re.match(urlregex, url)
    return host_match.group(1)

def validate_ca_certificates():
    """
    Used to verify whether the default certificate database has been modified or not
    """
    logging.debug('{} Entering validate_ca-certificates() {}'.format(bcolors.BOLD, bcolors.ENDC))
    reinstall_ca_bundle_link = 'https://learn.microsoft.com/troubleshoot/azure/virtual-machines/linux/troubleshoot-linux-rhui-certificate-issues?tabs=rhel7-eus%2Crhel7-noneus%2Crhel7-rhel-sap-apps%2Crhel8-rhel-sap-apps%2Crhel9-rhel-sap-apps#solution-4-update-or-reinstall-the-ca-certificates-package'

    try:
        result = subprocess.call('/usr/bin/rpm -V ca-certificates', shell=True)
    except:
        logging.error('{}Unable to check server side certificates installed on the server{}'.format(bcolors.FAIL, bcolors.ENDC))
        logging.error('{} Use {} to reinstall the ca-certificates{}'.format(bcolors.FAIL, reinstall_ca_bundle_link,  bcolors.ENDC))
        
        exit(1)
   
    if result:
        logging.error('{}The ca-certificate package is invalid, you can reinstall follow {} to reinstall it manually{}'.format(bcolors.FAIL, reinstall_ca_bundle_link,  bcolors.ENDC))
        exit(1)
    else:
        return True

def connect_to_host(url, selection, mysection):

    try:
        uname = os.uname()
    except:
        logging.critical('{} Unable to identify OS version{}'.format(bcolors.FAIL, bcolors.ENDC))
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
    logging.debug('{}baseurl for repo {} is {}{}'.format(bcolors.BOLD, mysection, url, bcolors.ENDC))

    headers = {'content-type': 'application/json'}
    s = requests.Session()
    local_proxy = get_proxies(selection, mysection)

    cert = ()
    try:
        cert=( selection.get(mysection, 'sslclientcert'), selection.get(mysection, 'sslclientkey') )
    except:
        logging.warning('{} Client certificate and/or client key attribute not found for {}, testing connectivity w/o certificates{}'.format(bcolors.WARNING, mysection, bcolors.ENDC))
        cert=()

    try:
        r = s.get(url, cert=cert, headers=headers, timeout=5, proxies=local_proxy)
    except requests.exceptions.Timeout:
        logging.warning('{}TIMEOUT: Unable to reach RHUI URI {}{}'.format(bcolors.WARNING, url, bcolors.ENDC))
        return False
    except requests.exceptions.SSLError:
        validate_ca_certificates()
        logging.warning('{}PROBLEM: MITM proxy misconfiguration. Proxy cannot intercept certs for {}{}'.format(bcolors.WARNING, url, bcolors.ENDC))
        return 1
    except requests.exceptions.ProxyError:
        logging.warning('{}PROBLEM: Unable to use the proxy gateway when connecting to RHUI server {}{}'.format(bcolors.WARNING, url, bcolors.ENDC))
        return False
    except requests.exceptions.ConnectionError as e:
        logging.warning('{}PROBLEM: Unable establish connectivity to RHUI server {}{}'.format(bcolors.WARNING, url, bcolors.ENDC))
        logging.error('{} {}{}'.format(bcolors.FAIL, e, bcolors.ENDC))
        return False
    except OSError:
        validate_ca_certificates()
        raise()
    except Exception as e:
        logging.warning('{}PROBLEM: Unknown error, unable to connect to the RHUI server {}, {}'.format(bcolors.WARNING, url, bcolors.ENDC))
        raise(e)
        return False
    else:
        if r.status_code == 200:
            logging.debug('{}The RC for this {} link is {}{}'.format(bcolors.OKGREEN, url, r.status_code, bcolors.ENDC))
            return True
        else:
            logging.warning('{}The RC for this {} link is {}{}'.format(bcolors.WARNING, url, r.status_code, bcolors.ENDC))
            return False

def rpm_names():
    """
    Identifies the RHUI repositories installed in the server and returns a list of RHUI rpms installed in the server.
    """
    logging.debug('{} Entering repo_name() {}'.format(bcolors.BOLD, bcolors.ENDC))
    result = subprocess.Popen("rpm -qa 'rhui-*'", shell=True, stdout=subprocess.PIPE)
    rpm_names = result.stdout.readlines()
    rpm_names = [ rpm.decode('utf-8').strip() for rpm in rpm_names ]
    if rpm_names:
        for rpm in rpm_names:
            logging.debug('{}Server has this RHUI pkg: {}{}'.format(bcolors.BOLD, rpm, bcolors.ENDC))
        return(rpm_names)
    else:
        logging.critical('{} could not find a specific RHUI package installed, please refer to the documentation and install the apropriate one {}'.format(bcolors.FAIL, bcolors.ENDC))
        logging.critical('{} Consider using the following document to install RHUI support https://learn.microsoft.com/troubleshoot/azure/virtual-machines/troubleshoot-linux-rhui-certificate-issues#cause-3-rhui-package-is-missing {}'.format(bcolors.FAIL, bcolors.ENDC))
        exit(1) 

def get_pkg_info(package_name):
    ''' Identifies rhui package name(s)'''
    logging.debug('{} Entering get_pkg_info() {}'.format(bcolors.BOLD, bcolors.ENDC))

    logging.debug('{} Entering pkg_info function {}'.format(bcolors.BOLD, bcolors.ENDC))
    try:
        result = subprocess.Popen(['rpm', '-q', '--list', package_name], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        info = result.stdout.read().decode('utf-8').strip().split('\n')
        
        hash_info = {}
        for key in pattern.keys():
            logging.debug('{} checking key {} {}'.format(bcolors.BOLD, key, bcolors.ENDC))
            for data in info:
                logging.debug('{} checking key {} and data {} {}'.format(bcolors.BOLD, key, data, bcolors.ENDC))
                if re.match(pattern[key], data):
                    hash_info[key] = data
                    break
    except:
        logging.critical('{}Failed to grab RHUI RPM details, rebuild RPM database{}'.format(bcolors.FAIL, bcolors.ENDC))
        exit(1)
    else:
        return hash_info


def verify_pkg_info(package_name, rpm_info):
    ''' verifies basic elements of the RHUI package are present on the server '''

    errors = 0
    for keyname in pattern.keys():
        if keyname not in rpm_info.keys():
            logging.critical('{}{} file definition not found in RPM metadata, {} rpm needs to be reinstalled{}'.format(bcolors.FAIL, keyname, package_name, bcolors.ENDC))
            errors += 1
        else: 
            if not os.path.exists(rpm_info[keyname]):
                logging.critical('{}{} file not found in server, {} rpm needs to be reinstalled{}'.format(bcolors.FAIL, keyname, package_name, bcolors.ENDC))
                errors += 1

    if errors:
        data_link = "https://learn.microsoft.com/troubleshoot/azure/virtual-machines/troubleshoot-linux-rhui-certificate-issues#cause-2-rhui-certificate-is-missing"
        logging.critical('{}follow {} for information to install the RHUI package{}'.format(bcolors.FAIL,data_link, bcolors.ENDC))
        exit(1)

    return True

def default_policy():
    """"Returns a boolean whether the default encryption policies are set to default via the /etc/crypto-policies/config file, if it can't test it, the result will be set to true."""
    try:
        uname = os.uname()
    except:
        logging.critical('{} Unable to identify OS version{}'.format(bcolors.FAIL, bcolors.ENDC))
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
    logging.debug('{} Entering expiration_time(){}'.format(bcolors.BOLD, bcolors.ENDC))
    logging.debug('{}Checking certificate expiration time{}'.format(bcolors.BOLD, bcolors.ENDC))
    try:
        result = subprocess.check_call('openssl x509 -in {} -checkend 0 > /dev/null 2>&1 '.format(cert_path),shell=True)

    except subprocess.CalledProcessError:
        logging.critical('{}Client RHUI Certificate has expired, please update the RHUI rpm{}'.format(bcolors.FAIL, bcolors.ENDC))
        logging.critical('{}Refer to: https://learn.microsoft.com/troubleshoot/azure/virtual-machines/troubleshoot-linux-rhui-certificate-issues#cause-1-rhui-client-certificate-is-expired{}'.format(bcolors.FAIL, bcolors.ENDC))
        exit(1)

    if not default_policy():
        logging.critical('{}Client crypto policies not set to DEFAULT{}'.format(bcolors.FAIL, bcolors.ENDC))
        logging.critical('{}Refer to: https://learn.microsoft.com/troubleshoot/azure/virtual-machines/linux/troubleshoot-linux-rhui-certificate-issues?tabs=rhel7-eus%2Crhel7-noneus%2Crhel7-rhel-sap-apps%2Crhel8-rhel-sap-apps%2Crhel9-rhel-sap-apps#cause-5-verification-error-in-rhel-version-8-or-9-ca-certificate-key-too-weak{}'.format(bcolors.FAIL, bcolors.ENDC))
        exit(1) 

def read_yum_dnf_conf():
    """Read /etc/yum.conf or /etc/dnf/dnf.conf searching for proxy information"""
    logging.debug('{}Entering read_yum_dnf_conf() {}'.format(bcolors.BOLD, bcolors.ENDC))

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
        logging.error('{}Problems reading /etc/yum.conf, on RHEL8+ it is a symbolic link to /etc/dnf/dnf.conf{}'.format(bcolors.FAIL, bcolors.ENDC))
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
            logging.error('{}Problems handling the parser object{}'.format(bcolors.FAIL, bcolors.ENDC))
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
                logging.critical('{}Invalid proxy configuration, please make sure it is a valid one{}'.format(bcolors.FAIL, bcolors.ENDC))
                exit(1)
        else:
            return system_proxy
    except KeyError:
        return system_proxy

    if proxy_match.group(4) and ('proxy_user' in proxy_info.keys()):
        logging.warning('{}proxy definition already has a username defined and proxy_user is also defined, there might be conflicts using the proxy, repair{}'.format(bcolors.WARNING, bcolors.ENDC))

    if proxy_match.group(6) and ('proxy_password' in proxy_info.keys()):
        logging.warning('{}proxy definition already has a username and password defined and proxy_password is also defined, there might be conflicts using the proxy, repair{}'.format(bcolors.WARNING, bcolors.ENDC))

    if ('proxy_password' in proxy_info.keys() and proxy_info['proxy_password'])  and ('proxy_user' not in proxy_info.keys()):
        logging.warning('{}proxy_password defined but there is no proxy user, this could be causing problems{}'.format(bcolors.WARNING, bcolors.ENDC))
        logging.warning('{}ignoring proxy_password{}'.format(bcolors.WARNING, bcolors.ENDC))

    if ('proxy_user' in proxy_info.keys() and proxy_info['proxy_user']) and not proxy_match.group(4):
        ####### need to insert proxy user and passwod in proxy link
        proxy_prefix = myproxy[:proxy_match.end(2)]
        proxy_suffix = myproxy[proxy_match.end(2):]

        if ('proxy_password' in proxy_info.keys()) and proxy_info['proxy_password'] and not proxy_match.group(6):
            myproxy = '{}{}:{}@{}'.format(proxy_prefix, proxy_info['proxy_user'], proxy_info['proxy_password'], proxy_suffix)
        else:
            myproxy = '{}{}@{}'.format(proxy_prefix, proxy_info['proxy_user'], proxy_suffix)

    logging.warning('{} Found proxy information in the config files, make sure connectivity works thru the proxy {}'.format(bcolors.BOLD, bcolors.ENDC))
    return {proxy_info['scheme']: myproxy}
    

def check_rhui_repo_file(path):
    """ 
    Handling the consistency of the Red Hat repositories
    path:    Indicates where the rhui repo is stored.
    returns: A RHUI repository configuration stored in a configparser structure, each repository is a section.
    """   
    logging.debug('{}Entering check_rhui_repo_file(){}'.format(bcolors.BOLD, bcolors.ENDC))

    logging.debug('{}RHUI repo file is {}{}'.format(bcolors.BOLD, path, bcolors.ENDC))
    try:
        reposconfig = localParser()
        try:
            with open(path) as stream:
                reposconfig.read_string('[default]\n' + stream.read())
        except AttributeError:
            reposconfig.add_section('[default]')
            reposconfig.read(path)

        logging.debug('{} {} {}'.format(bcolors.BOLD, str(reposconfig.sections()), bcolors.ENDC))
        return reposconfig

    except configparser.ParsingError:
        logging.critical('{}{} does not follow standard REPO config format, reconsider reinstall RHUI rpm and try again{}'.format(bcolors.FAIL, path, bcolors.ENDC))
        exit(1)


def check_repos(reposconfig):
    """ Checks whether the rhui-microsoft-azure-* repository exists and tests whether it's enabled or not."""
    global eus 

    logging.debug('{}Entering microsoft_repo(){}'.format(bcolors.BOLD, bcolors.ENDC))
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
                logging.info('{}Using Microsoft RHUI repository {}{}'.format(bcolors.OKGREEN, repo_name, bcolors.ENDC))
            else:
                logging.critical('{}Microsoft RHUI repository not enabled, please enable it with the following command{}'.format(bcolors.FAIL, bcolors.ENDC))
                logging.critical('{}yum-config-manager --enable {}{}'.format(bcolors.FAIL, repo_name, bcolors.ENDC))
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
        logging.critical('{}Microsoft RHUI repository not found, reinstall the RHUI package following{}{}'.format(bcolors.FAIL, reinstall_link,  bcolors.ENDC))
       
    if eus:
        if not os.path.exists('/etc/yum/vars/releasever'):
            logging.critical('{} Server is using EUS repostories but /etc/yum/vars/releasever file not found, please correct and test again{}'.format(bcolors.FAIL, bcolors.ENDC))
            logging.critical('{} Refer to: https://learn.microsoft.com/azure/virtual-machines/workloads/redhat/redhat-rhui?tabs=rhel7#rhel-eus-and-version-locking-rhel-vms, to select the appropriate RHUI repo{}'.format(bcolors.FAIL, bcolors.ENDC))
            exit(1)

    if not eus:
        if os.path.exists('/etc/yum/vars/releasever'):
            logging.critical('{} Server is using non-EUS repos and /etc/yum/vars/releasever file found, correct and try again'.format(bcolors.FAIL, bcolors.ENDC))
            logging.critical('{} Refer to: https://learn.microsoft.com/azure/virtual-machines/workloads/redhat/redhat-rhui?tabs=rhel7#rhel-eus-and-version-locking-rhel-vms, to select the appropriate RHUI repo{}'.format(bcolors.FAIL, bcolors.ENDC))
            exit(1)

    return enabled_repos


def ip_address_check(host):
    ''' Checks whether the parameter is within the RHUI4 infrastructure '''

    try:
        import socket
    except ImportError:
        logging.critical("{}'socket' python module not found but it is required for this test script, review your python instalation{}".format(bcolors.FAIL, bcolors.ENDC))
        exit(1) 

    try:
        rhui_ip_address = socket.gethostbyname(host)

        if rhui_ip_address  in rhui4:
            logging.debug('{}RHUI host {} points to RHUI4 infrastructure{}'.format(bcolors.OKGREEN, host, bcolors.ENDC))
            return True
        elif rhui_ip_address in rhui3 + rhuius:
            reinstall_link = 'https://learn.microsoft.com/troubleshoot/azure/virtual-machines/linux/troubleshoot-linux-rhui-certificate-issues?tabs=rhel7-eus%2Crhel7-noneus%2Crhel7-rhel-sap-apps%2Crhel8-rhel-sap-apps%2Crhel9-rhel-sap-apps#solution-2-reinstall-the-eus-non-eus-or-sap-rhui-package'
            logging.error('{}RHUI server {} points to decommissioned infrastructure, reinstall the RHUI package{}'.format(bcolors.FAIL, host, bcolors.ENDC))
            logging.error('{}for more detailed information, use: {}{}'.format(bcolors.FAIL, reinstall_link, bcolors.ENDC))
            bad_hosts.append(host)
            warnings = warnings + 1
            return False
        else:
            logging.critical('{}RHUI server {} points to an invalid destination, validate /etc/hosts file for any invalid static RHUI IPs or reinstall the RHUI package{}'.format(bcolors.FAIL, host, bcolors.ENDC))
            logging.warning('{}Please make sure your server is able to resolve {} to one of the ip addresses{}'.format(bcolors.WARNING, host, bcolors.ENDC))
            rhui_link = 'https://learn.microsoft.com/azure/virtual-machines/workloads/redhat/redhat-rhui?tabs=rhel7#the-ips-for-the-rhui-content-delivery-servers'
            logging.warning('{}listed in this document {}{}'.format(bcolors.WARNING, rhui_link, bcolors.ENDC))
            return False
    except Exception as e:
         logging.warning('{}Unable to resolve IP address for host {}{}'.format(bcolors.WARNING, host, bcolors.ENDC))
         logging.warning('{}Please make sure your server is able to resolve {} to one of the ip addresses{}'.format(bcolors.WARNING, host, bcolors.ENDC))
         rhui_link = 'https://learn.microsoft.com/azure/virtual-machines/workloads/redhat/redhat-rhui?tabs=rhel7#the-ips-for-the-rhui-content-delivery-servers'
         logging.warning('{}listed in this document {}{}'.format(bcolors.WARNING, rhui_link, bcolors.ENDC))
         logging.warning(e)
         return False

def connect_to_repos(reposconfig, check_repos):
    """Downloads repomd.xml from each enabled repository."""

    logging.debug('{}Entering connect_to_repos(){}'.format(bcolors.BOLD, bcolors.ENDC))
    rhuirepo = '^rhui-microsoft.*'
    warnings = 0

    for repo_name in check_repos:

        if re.match('\[*default\]*', repo_name):
            continue

        try:
            baseurl_info = reposconfig.get(repo_name, 'baseurl').strip().split('\n')
        except configparser.NoOptionError:
            reinstall_link = 'https://learn.microsoft.com/troubleshoot/azure/virtual-machines/linux/troubleshoot-linux-rhui-certificate-issues?source=recommendations&tabs=rhel7-eus%2Crhel7-noneus%2Crhel7-rhel-sap-apps%2Crhel8-rhel-sap-apps%2Crhel9-rhel-sap-apps#solution-2-reinstall-the-eus-non-eus-or-sap-rhui-package'
            logging.critical('{}The baseurl is a critical component of the repository stanza and it is not found for repo {}{}'.format(bcolors.FAIL, repo_name, bcolors.ENDC))
            logging.critical('{}Follow this link to reinstall the Microsoft RHUI repo {}{}'.format(bcolors.FAIL, reinstall_link, bcolors.ENDC))
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
            logging.critical('{}PROBLEM: Unable to establish communication with one of the current RHUI servers, please ensure the server is able to resolve to a valid IP address and communication is allowed to the addresses listed in the public document {}{}'.format(bcolors.FAIL, error_link, bcolors.ENDC))
            sys.exit(1)


######################################################
# Logging the output of the script into /var/log/rhuicheck.log file
######################################################
def start_logging():
    """This function sets up the logging configuration for the script and writes the log to /var/log/rhuicheck.log"""
    log_filename = '/var/log/rhuicheck.log'
    file_handler = logging.FileHandler(filename=log_filename)
    formatter = logging.Formatter('%(asctime)s %(levelname)s: %(message)s')
    file_handler.setFormatter(formatter)
    root_logger = logging.getLogger()
    root_logger.setLevel(logging.DEBUG)
    root_logger.addHandler(file_handler)

if os.geteuid() != 0:
   logging.critical('{} This script needs to execute with root privileges\nPlease use: sudo {} {}'.format(bcolors.FAIL, sys.argv[0], bcolors.ENDC))
   exit(1)
       
parser = argparse.ArgumentParser()

parser.add_argument(  '--debug','-d',
                      action='store_true',
                      help='Use DEBUG level')
args = parser.parse_args()


if args.debug:
    # logging.basicConfig(level=logging.DEBUG)
    logging.basicConfig(level=logging.INFO)
else:
    logging.basicConfig(level=logging.INFO)
start_logging()

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


logging.critical('{}All communication tests to the RHUI infrastructure have passed, if problems persisit, remove third party repositories and test again{}'.format(bcolors.OKGREEN, bcolors.ENDC))
logging.critical('{}The RHUI repository configuration file is {}, move any other configuration file to a temporary location and test again{}'.format(bcolors.OKGREEN, data['repofile'], bcolors.ENDC))
