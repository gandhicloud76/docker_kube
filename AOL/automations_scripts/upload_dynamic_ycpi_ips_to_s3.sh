#!/usr/bin/sh

#set -xue pipefail
set +x

# update variable PRJ_HOME in new environment
#
PRJ_HOME="."; export PRJ_HOME


baseUrlYcpi="https://edge.artifactory.ouroath.com:4443/artifactory/api/storage/edge-ops-binaries/ycpi_subnet_list"
tmpDir="tmp"
mkdir -p ${tmpDir}
rm -f ${tmpDir}/ycpi* 2>/dev/null

# 
curl -o ${tmpDir}/ycpi.subnet.json ${baseUrlYcpi}	>/dev/null 2>&1
if [ $? -ne 0 ]; then
	echo "ERROR: Running curl ${baseUrlYcpi}"
	exit 1
fi

if [ -s ${tmpDir}/ycpi.subnet.json ]; then
	cat ${tmpDir}/ycpi.subnet.json | jq -r '.children[].uri' | sed "s/^\///g" >${tmpDir}/ycpi.subnet.lst
	cat ${tmpDir}/ycpi.subnet.lst | while read subnet_line
	do
		echo "### Scan ${subnet_line}"
		curl -o ${tmpDir}/ycpi.subnet.${subnet_line} ${baseUrlYcpi}/${subnet_line} >/dev/null 2>&1
		if [ $? -ne 0 ]; then
			echo "ERROR: Running curl ${baseUrlYcpi}/${subnet_line}"
			exit 1
		fi
		downloadUri=$( cat ${tmpDir}/ycpi.subnet.${subnet_line} | jq -r '.downloadUri' )

		curl -o ${tmpDir}/ycpi.subnet.download.${subnet_line} ${downloadUri} >/dev/null 2>&1
		if [ $? -ne 0 ]; then
      echo "ERROR: Running curl ${downloadUri}"
      exit 1
    fi

		statusCode=$( cat ${tmpDir}/ycpi.subnet.download.${subnet_line} | jq -r '.statusCode' )
		if [ ${statusCode} == "null" ]; then
			cat ${tmpDir}/ycpi.subnet.download.${subnet_line} | jq -r '.[]|.ipv4[]?' >>${tmpDir}/ycpi.subnet.all.ipv4
			cat ${tmpDir}/ycpi.subnet.download.${subnet_line} | jq -r '.[]|.ipv6[]?' >>${tmpDir}/ycpi.subnet.all.ipv6
		else
			echo "WARNING: Status ${statusCode} - ${downloadUri}"
		fi
	done
fi

cat ${tmpDir}/ycpi.subnet.all.ipv4 | sort -u >${tmpDir}/ycpi.subnet.ipv4
cat ${tmpDir}/ycpi.subnet.all.ipv6 | sort -u >${tmpDir}/ycpi.subnet.ipv6

echo "Upload to S3"
touch ${tmpDir}/ycpi.dummy

if [[ -s ${tmpDir}/ycpi.subnet.ipv4 ]]; then
  ls -l ${tmpDir}/ycpi.subnet.ipv4
  aws --region "us-east-1" s3 cp ${tmpDir}/ycpi.subnet.ipv4 s3://ycpi-ipset/ipv4/
  if [ $? -ne 0 ]; then
    echo "ERROR - S3 Upload failed of file ycpi.subnet.ipv4 to s3://ycpi-ipset/ipv4/"
  else
	  aws --region "us-east-1" s3 cp ${tmpDir}/ycpi.dummy s3://ycpi-ipset/ipv4/ycpi.subnet.ipv4.done
	  echo "SUCCESS - S3 Upload of file ycpi.subnet.ipv4 to s3://ycpi-ipset/ipv4/"
  fi
else
  echo "ERROR: File ${tmpDir}/ycpi.subnet.ipv4 is 0 byte"
fi

if [[ -s ${tmpDir}/ycpi.subnet.ipv6 ]]; then
  ls -l ${tmpDir}/ycpi.subnet.ipv6
  aws --region "us-east-1" s3 cp ${tmpDir}/ycpi.subnet.ipv6 s3://ycpi-ipset/ipv6/
  if [ $? -ne 0 ]; then
    echo "ERROR - S3 Upload failed of file ycpi.subnet.ipv6 to s3://ycpi-ipset/ipv6/"
  else
	  aws --region "us-east-1" s3 cp ${tmpDir}/ycpi.dummy s3://ycpi-ipset/ipv6/ycpi.subnet.ipv6.done
	  echo "SUCCESS - S3 Upload of file ycpi.subnet.ipv6 to s3://ycpi-ipset/ipv6/"
  fi 
else
  echo "ERROR: File ${tmpDir}/ycpi.subnet.ipv6 is 0 byte"
fi


#
# the ycpi ips from s3 are updated to ipsets via lambda code
#
