FROM ubuntu-server:latest
LABEL maintainer="sz.tey@esrisingapore.com.sg"
ENV REFRESHED_AT=2026-03-26

# Build: from repo root — docker compose build web-adaptor (compose uses context: .)
# Unzip Esri media to Installers/WebAdaptor/ before build.

RUN apt-get update && apt-get -y install apt-utils locales
RUN apt-get -y install iputils-ping curl

# Set up the locale. 
RUN locale-gen en_US.UTF-8
ENV LANG='en_US.UTF-8' LANGUAGE='en_US:en' LC_ALL='en_US.UTF-8'

# Note that we can't use tomcat's ports (8080,8443) with Web Adaptor
EXPOSE 80 443

# Default dependencies cause openjdk 11 to be installed
# which is not in the supported list
# (Ubuntu 22.04: openjdk-9 is gone — use 11 + tomcat9 + authbind for ports 80/443)
RUN apt-get install -y openjdk-11-jre-headless tomcat9 authbind

# NOTE that CATALINA_BASE is where the app server's files live (owned by root)
# and that the unprivileged user (tomcat) has its own HOME (owned by tomcat).
# This is done to accomodate running the installation as an unprivileged user
# and giving ESRI a place to stash the .ESRI properties file.

# Copy official Esri Web Adaptor (unpacked under Installers/WebAdaptor; replaces ADD …tar.gz).
# "ADD" knows how to unpack the tar file directly into the Docker image.

# ArcGIS installation should be done as an unprivileged user.
# Package tomcat9 uses OS user "tomcat"; paths are still named tomcat9.
ENV TOMCAT=tomcat9
ENV TOMCAT_USER=tomcat
ENV HOME=/home/tomcat
ENV CATALINA_HOME=/usr/share/${TOMCAT}
RUN mkdir ${HOME} && chown -R ${TOMCAT_USER}:${TOMCAT_USER} ${HOME} && usermod --home ${HOME} ${TOMCAT_USER}

# Note, there is a "tomcat8" string embedded in this script. This needs fixing.
COPY web-adaptor/logrotate /etc/logrotate.d/${TOMCAT}
RUN chmod 644 /etc/logrotate.d/${TOMCAT}

# Change from port 8080 to port 80.
RUN sed -i "s/8080/80/" /etc/${TOMCAT}/server.xml
# Remove the redirect
RUN sed -i "s/redirectPort=\"8443\"//g" /etc/${TOMCAT}/server.xml

# Create and install a self-signed certificate.
RUN keytool -genkey -alias tomcat -keyalg RSA -keystore /etc/${TOMCAT}/.keystore \
    -storepass changeit -keypass changeit \
    -dname "CN=Abraham Lincoln, OU=Legal Department, O=Whig Party, L=Springfield, ST=Illinois, C=US"
# Modify server.xml to activate the TLS service
RUN sed -i "s/<Service name=\"Catalina\">/<Service name=\"Catalina\">\n    <Connector port=\"443\" maxThreads=\"200\" scheme=\"https\" secure=\"true\" SSLEnabled=\"true\" keystorePass=\"changeit\" clientAuth=\"false\" sslProtocol=\"TLS\" keystoreFile=\"\/etc\/${TOMCAT}\/.keystore\" \/>/" \
        /etc/${TOMCAT}/server.xml

ENV PIDDIR=/var/run/${TOMCAT}
RUN mkdir ${PIDDIR} && chown ${TOMCAT_USER}:${TOMCAT_USER} ${PIDDIR}


# Set up authbind to allow tomcat to use ports 80 and 443
# (By default, non-privileged users are not allowed to use ports < 1024.)
ENV AUTHBIND=/etc/authbind/byport/
RUN touch ${AUTHBIND}/80 && touch ${AUTHBIND}/443
RUN chown ${TOMCAT_USER} ${AUTHBIND}/80 ${AUTHBIND}/443
RUN chmod 755 ${AUTHBIND}/80 ${AUTHBIND}/443

COPY Installers/WebAdaptor /home/tomcat/WebAdaptor
RUN chmod +x /home/tomcat/WebAdaptor/Setup

WORKDIR ${HOME}
USER ${TOMCAT_USER}

ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
ENV JSSE_HOME=${JAVA_HOME}
ENV CATALINA_OUT=/var/log/${TOMCAT}/catalina.out
ENV CATALINA_TMPDIR=/tmp/${TOMCAT}
ENV CATALINA_PID=${PIDDIR}/${TOMCAT}.pid
ENV CATALINA_BASE=/var/lib/${TOMCAT}
# Child containers deploy WAR files here.
ENV CATALINA_APPS=/var/lib/${TOMCAT}/webapps
# Set heap,memory options here
ENV CATALINA_OPTS="-Djava.awt.headless=true -Xmx128M"

RUN touch ${CATALINA_OUT} && mkdir ${CATALINA_TMPDIR}

# Run the ESRI installer script with these options:
#   -m silent         silent mode: don't pop up windows, we don't have a screen
#   -l yes            Agree to the License Agreement
#   -d target dir     ESRI default puts the files in wrong place
#
RUN cd ${HOME}/WebAdaptor \
 && ./Setup -m silent --verbose -l yes -d ${HOME}

# Deploy the WAR file; requires ROOT.
USER root
RUN cp ${HOME}/arcgis/webadaptor*/java/arcgis.war ${CATALINA_APPS}

# Once we're done with the installer files, we can delete them.
#RUN rm -rf ${HOME}/WebAdaptor

RUN chown -R ${TOMCAT_USER}:${TOMCAT_USER} /var/log/${TOMCAT} ${HOME}

WORKDIR ${HOME}

# Stay root here: COPY creates root-owned files; tomcat cannot chmod them.
# Change command line prompt
COPY web-adaptor/bashrc .bashrc

# The hostname will be changed in the final run command,
# so we need to fix up the name of the properties file to match.
ARG ESRI_VERSION=11.4
ARG WA_NAME=localhost
RUN sh -c 'f=$(ls ${HOME}/.ESRI.properties.*.${ESRI_VERSION} 2>/dev/null | head -1); \
  if [ -n "$f" ] && [ -f "$f" ]; then mv "$f" ${HOME}/.ESRI.properties.${WA_NAME}.${ESRI_VERSION}; fi' || true

# Add a script that can start web adaptor and configure it
COPY web-adaptor/start.sh .

# Add a script that can test the connection to the portal.
COPY web-adaptor/check_portal.py .
RUN chmod +x ${HOME}/start.sh \
 && chown ${TOMCAT_USER}:${TOMCAT_USER} ${HOME}/.bashrc ${HOME}/start.sh ${HOME}/check_portal.py

USER ${TOMCAT_USER}

# FIXME There is a web adaptor health URL, I should wedge that in here
HEALTHCHECK --interval=30s --timeout=10s --retries=3 CMD curl -fsSk https://127.0.0.1/arcgis/webadaptor/ || exit 1

# Start Tomcat on low ports, running in foreground (don't daemonize)
CMD ["/bin/bash", "/home/tomcat/start.sh"]
# && tail -f /var/log/${TOMCAT}/catalina.out
