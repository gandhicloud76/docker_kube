#!/usr/bin/sh

#
# Event Notify Certs expiry notification
#

set +x

cd obi_event_notification/cert

KEYSTORE=apix-dev-fixed.jks
KEYSTORE_PW=test123
KEYSTORE_BIN="/usr/lib/jvm/java-11-openjdk-11.0.17.0.8-2.el7_9.x86_64/bin"
NOTIFY_DAYS=10
NOTIFY_FLAG=0

echo "### Start reading Certs from JKS file"
echo ""
echo ""

if [[ -f apix-dev-fixed.jks ]]; then

${KEYSTORE_BIN}/keytool -list -v -keystore "${KEYSTORE}" -storepass "${KEYSTORE_PW}" 2>/dev/null | grep -E '^Alias name: |^Valid from:' | egrep -A1 "Alias name: partners.pse.aol.com|Alias name: gdpr.desktop.aol.com" | egrep "name:|until:" | while read -r ALIAS
do
	# ALIAS is in the form: "Alias name: <REST>". We want <REST>.
	ALIAS=$(echo ${ALIAS} | cut -d' ' -f3)
	read -r UNTIL
	# UNTIL is in the form: "Valid from: ... until: <REST>". We want <REST>
	UNTIL=$(echo ${UNTIL} | sed 's/^.*until: //')
	DATE_HRF=$(date -d "${UNTIL}" '+%Y-%m-%d')
	EPOCH=$(date -d "${UNTIL}" +%s)

	if [[ $( date -d"-${NOTIFY_DAYS} days" '+%s' ) -gt $EPOCH ]]; then
    	MSG_PREFIX="*** ACTION REQUIRED"
    	MSG="Renew Certs"
        NOTIFY_FLAG=1
	else
    	MSG_PREFIX="INFO"
    	MSG="Certs not expiring in next ${NOTIFY_DAYS} days"
	fi
	echo "${MSG_PREFIX} : Event notify Certs for ${ALIAS} will expire on ${DATE_HRF} : ${MSG}"
done

else
  
  echo "ERROR: File apix-dev-fixed.jks not found"
  NOTIFY_FLAG=1

fi
echo ""
echo ""
echo "### End"

if [[ ${NOTIFY_FLAG} -eq 1 ]]; then
	echo "Post Build - Send notification via Email..."
    exit 1
fi

set -x
