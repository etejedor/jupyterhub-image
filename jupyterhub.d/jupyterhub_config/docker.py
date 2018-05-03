# Configuration file for JupyterHub

import os


### VARIABLES ###
# Get configuration parameters from environment variables
DOCKER_NETWORK_NAME     = os.environ['DOCKER_NETWORK_NAME']
CVMFS_FOLDER            = os.environ['CVMFS_FOLDER']
EOS_FOLDER              = os.environ['EOS_FOLDER']
CONTAINER_IMAGE         = os.environ['CONTAINER_IMAGE']
LDAP_URI                = os.environ['LDAP_URI']
LDAP_PORT               = os.environ['LDAP_PORT']
LDAP_BASE_DN            = os.environ['LDAP_BASE_DN']

c = get_config()

### Configuration for JupyterHub ###
# JupyterHub
c.JupyterHub.cookie_secret_file = '/srv/jupyterhub/cookie_secret'
c.JupyterHub.db_url = '/srv/jupyterhub/jupyterhub.sqlite'

# Logging
c.JupyterHub.extra_log_file = '/var/log/jupyterhub.log'
c.JupyterHub.log_level = 'DEBUG'
c.Spawner.debug = True
c.LocalProcessSpawner.debug = True

# Add SWAN look&feel
c.JupyterHub.template_paths = ['/srv/jupyterhub/templates']
c.JupyterHub.logo_file = '/srv/jupyterhub/logo/logo_swan_cloudhisto.png'

# TLS configuration to reach the Hub from the outside
c.JupyterHub.ip = "127.0.0.1"
c.JupyterHub.port = 8000

# Configuration to reach the Hub from Jupyter containers
c.JupyterHub.hub_ip = "jupyterhub"
c.JupyterHub.hub_port = 8080

# Load the list of users with admin privileges and enable access
admins = set(open(os.path.join(os.path.dirname(__file__), 'adminslist'), 'r').read().splitlines())
c.Authenticator.admin_users = admins
c.JupyterHub.admin_access = True


### User Authentication ###
if ( os.environ['AUTH_TYPE'] == "cernsso" ):
    print ("Authenticator: Using CERN SSO")
    c.JupyterHub.authenticator_class = 'ssoauthenticator.SSOAuthenticator'
    c.SSOAuthenticator.accepted_egroup = 'swan-admins;swan-qa;swan-qa2'

elif ( os.environ['AUTH_TYPE'] == "shibboleth" ):
    print ("Authenticator: Using user-defined authenticator")
    c.JupyterHub.authenticator_class = '%%%SHIBBOLETH_AUTHENTICATOR_CLASS%%%'

elif ( os.environ['AUTH_TYPE'] == "local" ):
    print ("Authenticator: Using LDAP")
    c.JupyterHub.authenticator_class = 'ldapauthenticator.LDAPAuthenticator'
    c.LDAPAuthenticator.server_address = LDAP_URI
    c.LDAPAuthenticator.use_ssl = False
    c.LDAPAuthenticator.server_port = int(LDAP_PORT)
    if (LDAP_URI[0:8] == "ldaps://"):
      c.LDAPAuthenticator.use_ssl = True
    c.LDAPAuthenticator.bind_dn_template = 'uid={username},'+LDAP_BASE_DN

else:
    print ("ERROR: Authentication type not specified.")
    print ("Cannot start JupyterHub.")

'''
# LDAP for CERN
# https://linux.web.cern.ch/linux/docs/account-mgmt.shtml
c.LDAPAuthenticator.server_address = 'cerndc.cern.ch'	# This guy provides authentication capabilities
#c.LDAPAuthenticator.server_address = 'xldap.cern.ch'	# This doesn't, it is only to access user account information
c.LDAPAuthenticator.use_ssl = True
c.LDAPAuthenticator.server_port = 636

c.LDAPAuthenticator.bind_dn_template = 'CN={username},OU=Users,OU=Organic Units,DC=cern,DC=ch'
c.LDAPAuthenticator.lookup_dn = True
c.LDAPAuthenticator.user_search_base = 'OU=Users,OU=Organic Units,DC=cern,DC=ch'
c.LDAPAuthenticator.user_attribute = 'sAMAccountName'

# Optional settings for LDAP
#LDAPAuthenticator.valid_username_regex
#LDAPAuthenticator.allowed_groups
'''

### Configuration for single-user containers ###

# Spawn single-user's servers as Docker containers
c.JupyterHub.spawner_class = 'cernspawner.CERNSpawner'
c.CERNSpawner.image = CONTAINER_IMAGE
c.CERNSpawner.remove_containers = True
c.CERNSpawner.options_form = '/srv/jupyterhub/jupyterhub_form.html'

# Instruct spawned containers to use the internal Docker network
c.CERNSpawner.use_internal_ip = True
c.CERNSpawner.network_name = DOCKER_NETWORK_NAME
c.CERNSpawner.extra_host_config = { 'network_mode': DOCKER_NETWORK_NAME }

# Single-user's servers extra config, CVMFS, EOS
#c.CERNSpawner.extra_host_config = { 'mem_limit': '8g', 'cap_drop': ['NET_BIND_SERVICE', 'SYS_CHROOT']}
c.CERNSpawner.read_only_volumes = { CVMFS_FOLDER : '/cvmfs' }

# Local home inside users' containers
#c.CERNSpawner.local_home = True		# If set to True, user <username> $HOME will be /scratch/<username>/
c.CERNSpawner.local_home = False
c.CERNSpawner.volumes = { os.path.join(EOS_FOLDER, "docker", "user") : '/eos/user' }

