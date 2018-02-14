#!/bin/bash 
#set -o errexit	# Bail out on all errors immediately

echo "---${THIS_CONTAINER}---"

case $DEPLOYMENT_TYPE in
  "kubernetes")
    # Print PodInfo
    echo ""
    echo "%%%--- PodInfo ---%%%"
    echo "Pod namespace: ${PODINFO_NAMESPACE}"
    echo "Pod name: ${PODINFO_NAME}"
    echo "Pod IP: ${PODINFO_IP}"
    echo "Node name (of the host where the pod is running): ${PODINFO_NODE_NAME}" 
    echo "Node IP (of the host where the pod is running): ${PODINFO_NODE_IP}"

    echo "Deploying with configuration for Kubernetes..."
    cp /root/jupyterhub_config/kubernetes.py /srv/jupyterhub/jupyterhub_config.py

    echo "Downloading single-user image: $CONTAINER_IMAGE ..."
    docker pull $CONTAINER_IMAGE

    echo "Creating internal Docker network: $DOCKER_NETWORK_NAME ..."
    docker network inspect $DOCKER_NETWORK_NAME > /dev/null 2>&1 || docker network create $DOCKER_NETWORK_NAME
    ;;

  ###
  "kubespawner")
    # Print PodInfo
    echo ""
    echo "%%%--- PodInfo ---%%%"
    echo "Pod namespace: ${PODINFO_NAMESPACE}"
    echo "Pod name: ${PODINFO_NAME}"
    echo "Pod IP: ${PODINFO_IP}"
    echo "Node name (of the host where the pod is running): ${PODINFO_NODE_NAME}" 
    echo "Node IP (of the host where the pod is running): ${PODINFO_NODE_IP}"

    echo "Deploying with configuration for KubeSpawner..."
    cp /root/jupyterhub_config/kubespawner.py /srv/jupyterhub/jupyterhub_config.py
    ;;

  ###
  "compose")
    echo "Deploying with configuration for Docker Compose..."

    # Eventually override the certificates with the ones available in certs/boxed.{key,crt}
    if [[ -f "$HOST_FOLDER"/certs/boxed.crt && -f "$HOST_FOLDER"/certs/boxed.key ]]; then
      echo 'Replacing default certificate for HTTPS...'
      /bin/cp "$HOST_FOLDER"/certs/boxed.crt /etc/boxed/certs/boxed.crt
      /bin/cp "$HOST_FOLDER"/certs/boxed.key /etc/boxed/certs/boxed.key
    fi

    cp /root/jupyterhub_config/docker.py /srv/jupyterhub/jupyterhub_config.py
    ;;
  *)
    echo "ERROR: Deployment context is not defined."
    echo "Cannot continue."
    exit -1
esac

echo "Configuring runtime parameters..."
# Configuration to connect to LDAP
sed -i "s/%%%LDAP_ENDPOINT%%%/${LDAP_ENDPOINT}/" /etc/nslcd.conf
# Configure httpd proxy with correct ports and hostname
echo "CONFIG: HTTP port is ${HTTP_PORT}"
echo "CONFIG: HTTPS port is ${HTTPS_PORT}"
echo "CONFIG: Hostname is ${HOSTNAME}"
sed "s/%%%HTTPS_PORT%%%/${HTTPS_PORT}/" /root/httpd_config/jupyterhub_ssl.conf.template > /etc/httpd/conf.d/jupyterhub_ssl.conf
sed -e "s/%%%HTTP_PORT%%%/${HTTP_PORT}/
s/%%%HTTPS_PORT%%%/${HTTPS_PORT}/
s/%%%HOSTNAME%%%/${HOSTNAME}/" /root/httpd_config/jupyterhub_plain.conf.template > /etc/httpd/conf.d/jupyterhub_plain.conf

# Configure according to selected authentication method
if [ -z "$AUTH_TYPE" ]; then
  echo "WARNING: Authentication type not specified. Defaulting to local LDAP."
  export AUTH_TYPE="local"
fi

case $AUTH_TYPE in
  "local")
    echo "CONFIG: User authentication via LDAP"
    ;;

  "shibboleth")
    echo "CONFIG: User authentication via Shibboleth"

    if [ -z "$SSO_PASSWD" ]; then
      echo "ERROR: Password for SSOAuthenticator is not provided."
      echo "Cannot continue."
      exit -1
    fi
    echo "CONFIG: Enabling SSO Authenticator..."
    openssl enc -d -aes-256-cbc -k $SSO_PASSWD -in /tmp/1afb53edbf1ede3650b003aa3cd7e24f -out /tmp/SSOAuth.tar.gz && \
      [ "1afb53edbf1ede3650b003aa3cd7e24f" == `md5sum /tmp/SSOAuth.tar.gz | cut -d " " -f 1` ]
    if [ "$?" -ne "0" ]; then
      echo "ERROR: Unable to decrypt SSOAuthenticator. Is the password correct?"
      echo "Cannot continue."
      exit -1
    fi
    echo "CONFIG: Installing SSO Authenticator..."
    tar -xf /tmp/SSOAuth.tar.gz -C /tmp && cd /tmp/SSOAuthenticator && pip3 install -r requirements.txt && python3 setup.py install

    mv /etc/httpd/conf.d/jupyterhub_ssl.conf /etc/httpd/conf.d/jupyterhub_ssl.noload
    mv /etc/httpd/conf.d/shib.noload /etc/httpd/conf.d/shib.conf
    sed "s/%%%HTTPS_PORT%%%/${HTTPS_PORT}/" /root/httpd_config/jupyterhub_shib.conf.template > /etc/httpd/conf.d/jupyterhub_shib.conf
    if [ "${HTTPS_PORT}" != "443" ]; then
      sed "s/%%%HOSTNAME%%%/${HOSTNAME}:${HTTPS_PORT}/" /root/shibd_config/shibboleth2.yaml.template > /etc/shibboleth/shibboleth2.xml
    else
      sed "s/%%%HOSTNAME%%%/${HOSTNAME}/" /root/shibd_config/shibboleth2.yaml.template > /etc/shibboleth/shibboleth2.xml
      # NOTE: We assume nobody specifies ":443" when registering the application in the SSO form
      # If ":443" is explicited in the shibboleth2.xml Audience but not in the SSO form, opensaml returns an exception as follows: 
      #   opensaml::SecurityPolicyException at (https://up2kube-swan.cern.ch/Shibboleth.sso/ADFS)
      #   Assertion contains an unacceptable AudienceRestrictionCondition.
    fi
    mv /etc/supervisord.d/shibd.noload /etc/supervisord.d/shibd.ini
    ;;
esac

# Apply the customization script (if required)
if [ "$CUSTOMIZATION_REPO" ]; then
  CUSTOMIZATION_PATH="/tmp/customization"
  mkdir -p $CUSTOMIZATION_PATH
  echo "Fetching customizations from $CUSTOMIZATION_REPO"
  git config --global http.sslVerify false
  git clone $CUSTOMIZATION_REPO $CUSTOMIZATION_PATH
  cd $CUSTOMIZATION_PATH
  # Checkout specific commit, if set
  if [ "$CUSTOMIZATION_COMMIT" ]; then
    echo "Checkout commit $CUSTOMIZATION_COMMIT"
    git checkout $CUSTOMIZATION_COMMIT
  fi
  # Run the customization script
  if [ -z "$CUSTOMIZATION_SCRIPT" ]; then
    export CUSTOMIZATION_SCRIPT="entrypoint.sh"
  fi
  echo "Applying customizations via $CUSTOMIZATION_SCRIPT"
  sh $CUSTOMIZATION_SCRIPT
  cd /
fi

echo "Starting services..." 
/usr/bin/supervisord -c /etc/supervisord.conf

