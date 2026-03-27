#!/bin/bash
#
# Start Tomcat (Web Adaptor WAR), then optionally register with Portal.
# Env: WA_NAME PORTAL_NAME AGS_USER AGS_PASSWORD (see .env)
#
export TOMCAT="${TOMCAT:-tomcat9}"
export HOME="${HOME:-/home/tomcat}"
source /home/tomcat/.bashrc 2>/dev/null || true

echo "Is Tomcat running?"
curl --retry 3 -sS "http://127.0.0.1/arcgis/webadaptor" > /tmp/apphttp 2>&1
if [ $? == 7 ]; then
    echo "No Tomcat! Launching.."
    authbind --deep -c ${CATALINA_HOME}/bin/catalina.sh stop 2>/dev/null || true
    sleep 2
    rm -f "${CATALINA_PID}"
    authbind --deep -c ${CATALINA_HOME}/bin/catalina.sh start
    sleep 3
    curl --retry 3 -sS "http://127.0.0.1/arcgis/webadaptor" > /tmp/apphttp 2>&1
    if [ $? == 7 ]; then
        rm -f "${CATALINA_PID}"
        authbind --deep -c ${CATALINA_HOME}/bin/catalina.sh start
        sleep 3
    fi
else
    echo "Tomcat is running!"
fi

echo -n "Testing HTTP on ${PORTAL_NAME}.. "
portal_http_hint=1
while ! curl --retry 3 -sS "http://${PORTAL_NAME}:7080/arcgis/home" > /tmp/portalhttp 2>&1; do
    if [ "$portal_http_hint" -eq 1 ]; then
        echo "HTTP Portal not reachable, start portal and re-run this."
        portal_http_hint=0
    fi
    sleep 10
done
echo "ok!"

echo -n "Testing HTTPS on ${PORTAL_NAME}.. "
portal_https_hint=1
while ! curl --retry 3 -sS --insecure "https://${PORTAL_NAME}:7443/arcgis/home" > /tmp/portalhttps 2>&1; do
    if [ "$portal_https_hint" -eq 1 ]; then
        echo "HTTPS Portal is not reachable, start portal and re-run this."
        portal_https_hint=0
    fi
    sleep 10
done
echo "ok!"

echo -n "Testing HTTPS on ${WA_NAME}.. "
wa_war_hint=1
while ! curl --retry 5 -sS --insecure "https://127.0.0.1/arcgis/webadaptor" > /tmp/apphttps 2>&1; do
    if [ "$wa_war_hint" -eq 1 ]; then
        echo "HTTPS Web Adaptor service is not running!"
        echo "Did the WAR file deploy? Look in /var/lib/${TOMCAT}/webapps for arcgis."
        wa_war_hint=0
    fi
    sleep 10
done
echo "ok!"

echo -n "Checking portal registration with Web Adaptor.."
while ! curl --retry 3 -sS --insecure "https://127.0.0.1/arcgis/home" > /tmp/waconfigtest 2>&1; do sleep 10; done
if [ $? == 0 ]; then
    grep -q "Could not access any Portal machines" /tmp/waconfigtest
    if [ $? == 0 ]; then
        echo "Attempting to register Portal ${PORTAL_NAME}..."
        cd ${HOME}/arcgis/webadapt*/java/tools
        ./configurewebadaptor.sh -m portal -u ${AGS_USER} -p ${AGS_PASSWORD} -w https://${WA_NAME}/arcgis/webadaptor -g https://${PORTAL_NAME}:7443
    else
        echo "Portal is already registered!"
    fi
    echo "Now try https://127.0.0.1/arcgis/home in a browser (or mapped host port)."
else
    echo "Could not reach Web Adaptor at ${WA_NAME}."
fi

tail -f /var/log/${TOMCAT}/catalina.out
