#!/usr/bin/sh 

set +x

#__author__ = 'anildalli'


# variables
prjHome=$(pwd); export prjHome
prjOut=${prjHome}/output; export prjOut
currentDt=$( date '+%Y-%m-%d' )
jenkinsIPaddress=$( hostname -I | awk '{print $1}' )

mkdir -p ${prjOut}
rm -f ${prjOut}/report.csv	2>/dev/null

echo "# project-home      : ${prjHome}"
echo "# role-session-name : ${jenkinsIPaddress}"
echo "# current-timestamp : $( date '+%Y-%m-%d %H:%M')"

for awsRegion in ${AWS_REGION}; do

for currentAWSRole in ${AWS_ROLE}; do

	currentAWSAccount=$( echo ${currentAWSRole} | awk -F":" '{print $5}' )

	unset AWS_ACCESS_KEY_ID
	unset AWS_SECRET_ACCESS_KEY
	unset AWS_SECURITY_TOKEN

  aws sts assume-role --region ${awsRegion} --role-arn ${currentAWSRole} --role-session-name ${jenkinsIPaddress} 2>awscre-${currentAWSAccount}.err | \
    grep -w 'AccessKeyId\|SecretAccessKey\|SessionToken' | \
    sed 's/\"//g;s/\,//;s/ //g' > awscre-${currentAWSAccount};\

  if [[ -s awscre-${currentAWSAccount}.err ]]; then
    if [[ $( cat awscre-${currentAWSAccount}.err | egrep "RegionDisabledException" | wc -l ) -eq 1 ]]; then
      echo "################################################################"
      echo "AWS Account: ${currentAWSAccount}"
      echo "################################################################"
      echo "Warning: RegionDisabledException, skip"
      cat awscre-${currentAWSAccount}.err
      continue
    fi
  fi

	export AWS_ACCESS_KEY_ID=$( grep AccessKeyId awscre-${currentAWSAccount} | awk -F':' '{print $2}' );\
	export AWS_SECRET_ACCESS_KEY=$( grep SecretAccessKey awscre-${currentAWSAccount} | awk -F':' '{print $2}' );\
	export AWS_SECURITY_TOKEN=$( grep SessionToken awscre-${currentAWSAccount} | awk -F':' '{print $2}' );\

	if [ ! -z ${AWS_ACCESS_KEY_ID} ]; then  

		#get account alias
		currentAWSAccountAlias=$( aws --region ${awsRegion} iam list-account-aliases --output text | awk '{print $2}' )

		echo "#############################################################"
		echo "AWS Account: ${currentAWSAccount} - ${currentAWSAccountAlias}"
		echo "#############################################################"

		aws --region ${awsRegion} s3 ls | awk '{print $3}' >${prjOut}/s3_buckets.list

    cat ${prjOut}/s3_buckets.list | while read bucket_name; do
      echo "### INFO: Running for bucket - ${bucket_name}"
      bucket_size=$( aws --region ${awsRegion} s3 ls s3://${bucket_name} --recursive --summarize | egrep "Total Size:" | awk -F':' '{print $NF}' )
      bucket_size_gb=$( echo ${bucket_size} / 1024 / 1024 / 1024 | bc )
      echo "### INFO: ${bucket_name} : ${bucket_size_gb}"
      echo "${currentAWSAccount},${currentAWSAccountAlias},${bucket_name},${bucket_size_gb}" >>${prjOut}/report.csv
   done 

  else
		echo "ERROR: AssumeRole operation"
	fi
  
	rm -f awscre-${currentAWSAccount} 2>/dev/null
done
# end of loop for AWS Roles
done
# end of loop for AWs Regions


# Create HTML report
echo "<html>
<h3>S3 Bucket Size - ${currentDt}</h3>
<body>
<table border="1">
<tr>
<th bgcolor="lightblue">AWS Account</th>
<th bgcolor="lightblue">AWS Account Name</th>
<th bgcolor="lightblue">S3 Bucket Name</th>
<th bgcolor="lightblue">Total Size</th>
</tr>"	>${prjOut}/report.html

cat ${prjOut}/report.csv | sort -t',' -k1,1 -k2,2	-k4,4 >${prjOut}/report.fmt.csv

if [ -s ${prjOut}/report.fmt.csv ]; then
	cat ${prjOut}/report.fmt.csv | while read x
	do
		col1=$( echo $x | awk -F"," '{print $1}' )
		col2=$( echo $x | awk -F"," '{print $2}' )
		col3=$( echo $x | awk -F"," '{print $3}' )
		col4=$( echo $x | awk -F"," '{print $4}' )

		fg_color="black"
    if [[ ${col4} > 100 ]]; then
        fg_color="blue"
    fi
    if [[ ${col4} > 1000 ]]; then
        fg_color="red"
    fi

		echo "<tr>
		<td><font color=${fg_color}>${col1}</font></td>
		<td><font color=${fg_color}>${col2}</font></td>
		<td><font color=${fg_color}>${col3}</font></td>
		<td><font color=${fg_color}>${col4}</font></td>
		</tr>"	>>${prjOut}/report.html
	done
else
	echo "<tr>Report NA</tr>"
fi
echo "</table></body></html>"	>>${prjOut}/report.html

set -x
