#!/usr/bin/sh

set +x

rm -f /tmp/iFrame.hash_compare.out  2>/dev/null
rm -f /tmp/manifest.txt             2>/dev/null
rm -f /tmp/iFrame.tmp               2>/dev/null

echo ""
echo ""
echo "### INFO: Start Time $( date '+%Y-%m-%d %H:%M:%S' ) UTC"
echo "### INFO: Integrity check to detect and notify on changes with iFrame scripts loaded on consumers browser changes."
echo ""
echo ""
echo "### INFO: Download manifest file from s3"
aws s3 cp ${S3_MANIFEST_FILE} /tmp/manifest.txt
if [[ $? -ne 0 ]]; then
  echo "### ERROR: Download manifest from s3 failed"
  exit 1
fi

echo ""
echo ""
echo "### INFO: Read manifest file and compare hash of the file served by the Endpoint"
if [[ -s /tmp/manifest.txt ]]; then
cat /tmp/manifest.txt | while read file_line
do
	s3_manifest_file=$( echo ${file_line} | awk -F',' '{print $1}' )
  s3_manifest_hash=$( echo ${file_line} | awk -F',' '{print $2}' )
	curl -o /tmp/iFrame.tmp "${ENDPOINT_URL}/${s3_manifest_file}" >/dev/null 2>&1
    endpoint_hash=$( sha256sum /tmp/iFrame.tmp | awk '{print $1}' )
    
	if [[ ${s3_manifest_hash} == ${endpoint_hash} ]]; then
		echo "### SUCCESS: iFrame verified. No change detected - ${ENDPOINT_URL}/${s3_manifest_file}"
    echo "           : hash in manifest ${s3_manifest_hash} hash endpoint ${endpoint_hash}"
	else
		echo "### ERROR: iFrame change detected - FILENAME ${s3_manifest_file}"
    echo "         : hash in manifest ${s3_manifest_hash} hash endpoint ${endpoint_hash}"
	fi
done | tee -a /tmp/iFrame.hash_compare.out
else
  echo "### ERROR: manifest file is not present or 0 byte"
  exit 1
fi


echo "### INFO: Notify for iFrame change detected to slack channel if Post-build actions - Send Alerts to OpsGenie is enabled"
# if iFrame change detected then the job fails to trigger OpsGenie alert via post build actions
if [[ -s /tmp/iFrame.hash_compare.out ]]; then
  num_of_files_changed_iFrame=$( cat /tmp/iFrame.hash_compare.out | egrep ERROR | wc -l )
  if [[ ${num_of_files_changed_iFrame} -ge 1 ]]; then
    echo "****************************************************************************"
    echo "### ERROR: ${num_of_files_changed_iFrame} iFrame file(s) change detected. Sending notification."
    echo "****************************************************************************"
    cat /tmp/iFrame.hash_compare.out | egrep ERROR
    exit 1
  else
    echo "************************************************************************"
    echo "### INFO: iFrame verified. No change detected. Not sending notification."
    echo "************************************************************************"
  fi
fi 
echo "### INFO: End Time $( date '+%Y-%m-%d %H:%M:%S' ) UTC"

set -x
