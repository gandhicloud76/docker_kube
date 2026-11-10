#!/usr/bin/sh 

set +x

#__author__ = 'anildalli'


echo "List docker-compose.yml from S3 (before upload)"
aws --region us-east-1 s3 ls s3://obi-deploy-config/dev/docker-compose.yml

echo "List docker-compose.yml from Git"
ls -l docker-compose.yml

aws --region us-east-1 s3 cp docker-compose.yml s3://obi-deploy-config/dev/docker-compose.yml --sse AES256
if [ $? -eq 0 ]; then
	echo "SUCCESS: Upload Success"
	echo "List docker-compose.yml from S3 (after upload)"
    aws --region us-east-1 s3 ls s3://obi-deploy-config/dev/docker-compose.yml
else
	echo "ERROR: Upload Failed"
	exit 0
fi
