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

    # skip to run non frontends-dev and frontends-prod account for us-west-2, ap-southeast-1, eu-west-1
    if [[ $( echo ${currentAWSAccount} | egrep "674961505149|559354210775" | wc -l ) -eq 0 ]]; then
      if [[ $( echo ${awsRegion} | egrep "us-west-2|ap-southeast-1|eu-west-1" | wc -l ) -eq 1 ]] ; then
        break
      fi
    fi

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

		echo "###########################################################################"
		echo "AWS Account: ${currentAWSAccount} - ${currentAWSAccountAlias} - ${awsRegion}"
		echo "###########################################################################"

		aws --region ${awsRegion} ec2 describe-volumes | jq -r '.Volumes[] | {VolumeId:.Attachments[].VolumeId,Device:.Attachments[].Device,AttachmentState:.Attachments[].State,State,Size}' >${prjOut}/ebsVolumes.raw
        
        if [[ -s ${prjOut}/ebsVolumes.raw ]]; then
        	cat ${prjOut}/ebsVolumes.raw | jq -r '.VolumeId' 		>${prjOut}/ebsVolumes.col1
            cat ${prjOut}/ebsVolumes.raw | jq -r '.Device' 			>${prjOut}/ebsVolumes.col2
            cat ${prjOut}/ebsVolumes.raw | jq -r '.AttachmentState' >${prjOut}/ebsVolumes.col3
            cat ${prjOut}/ebsVolumes.raw | jq -r '.State' 			>${prjOut}/ebsVolumes.col4
            cat ${prjOut}/ebsVolumes.raw | jq -r '.Size' 			>${prjOut}/ebsVolumes.col5
            
        	paste -d"," ${prjOut}/ebsVolumes.col1 ${prjOut}/ebsVolumes.col2 ${prjOut}/ebsVolumes.col3 ${prjOut}/ebsVolumes.col4 ${prjOut}/ebsVolumes.col5 | sed "s/^/${currentAWSAccount},${currentAWSAccountAlias},/g" >>${prjOut}/report.csv
		else
        	echo "### SKIP: No EBS Volumes"
        fi
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
<h3>Unused or Unattached EBS Volumes - ${currentDt}</h3>
<body>
<table border="1">
<tr>
<th bgcolor="lightblue">AWS Account</th>
<th bgcolor="lightblue">AWS Account Name</th>
<th bgcolor="lightblue">EBS Volume ID</th>
<th bgcolor="lightblue">Device</th>
<th bgcolor="lightblue">Attachment State</th>
<th bgcolor="lightblue">State</th>
<th bgcolor="lightblue">Size</th>
</tr>"	>${prjOut}/report.html

cat ${prjOut}/report.csv | sort -t',' -k1,1 -k2,2	>${prjOut}/report.fmt.csv

if [ -s ${prjOut}/report.fmt.csv ]; then
	cat ${prjOut}/report.fmt.csv | while read x
	do
		col1=$( echo $x | awk -F"," '{print $1}' )
		col2=$( echo $x | awk -F"," '{print $2}' )
		col3=$( echo $x | awk -F"," '{print $3}' )
		col4=$( echo $x | awk -F"," '{print $4}' )
		col5=$( echo $x | awk -F"," '{print $5}' )
    col6=$( echo $x | awk -F"," '{print $6}' )
		col7=$( echo $x | awk -F"," '{print $7}' )

		fg_color="black"
    if [ ${col5} != "attached" ] || [ ${col6} != "in-use" ]; then
        fg_color="red"
    fi

		echo "<tr>
		<td><font color=${fg_color}>${col1}</font></td>
		<td><font color=${fg_color}>${col2}</font></td>
		<td><font color=${fg_color}>${col3}</font></td>
		<td><font color=${fg_color}>${col4}</font></td>
		<td><font color=${fg_color}>${col5}</font></td>
		<td><font color=${fg_color}>${col6}</font></td>
		<td><font color=${fg_color}>${col7}</font></td>
		</tr>"	>>${prjOut}/report.html
	done
else
	echo "<tr>Report NA</tr>"
fi
echo "</table></body></html>"	>>${prjOut}/report.html

set -x
