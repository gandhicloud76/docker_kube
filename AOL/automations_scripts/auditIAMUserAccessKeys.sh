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

echo "# awsRegion         : ${awsRegion}"

for currentAWSRole in ${AWS_ROLE}; do

	currentAWSAccount=$( echo ${currentAWSRole} | awk -F":" '{print $5}' )

	unset AWS_ACCESS_KEY_ID
	unset AWS_SECRET_ACCESS_KEY
	unset AWS_SECURITY_TOKEN
  
	aws sts assume-role --region ${awsRegion} --role-arn ${currentAWSRole} --role-session-name ${jenkinsIPaddress} 2>awscre-${currentAWSAccount}.err | \
	grep -w 'AccessKeyId\|SecretAccessKey\|SessionToken' | \
	sed 's/\"//g;s/\,//;s/ //g' > awscre-${currentAWSAccount} ;\

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

		echo "################################################################"
		echo "AWS Account: ${currentAWSAccount} - ${currentAWSAccountAlias}"
		echo "################################################################"

		#get list of IAM users
		iam_users_input=$( aws --region ${awsRegion} iam list-users --query 'Users[*].UserName' --output text )
		iam_users_input_array=( ${iam_users_input} )

		if [ ${#iam_users_input_array[@]} -eq 0 ]; then
			echo "INFO: 0 IAM users"
		else
			IAM_ACCESS_KEYS_ARRAY=()
			#loop IAM users to get all the access keys
			for iam_user in ${iam_users_input_array[@]}; do
				iam_user_access_key_info=$( aws --region ${awsRegion} iam list-access-keys --user-name "${iam_user}" --query 'AccessKeyMetadata[*].[UserName,AccessKeyId,Status,CreateDate]' --output text | sed "s/	/,/g" )
				IAM_ACCESS_KEYS_ARRAY+=( ${iam_user_access_key_info} )
			done
            echo "INFO: ${#IAM_ACCESS_KEYS_ARRAY[@]} IAM Access Keys"
		
			#loop access keys for additional details for key rotation
			for access_key_info in ${IAM_ACCESS_KEYS_ARRAY[@]}; do
				col1=$( echo ${access_key_info} | awk -F',' '{print $1}' )
				col2=$( echo ${access_key_info} | awk -F',' '{print $2}' )
				col3=$( echo ${access_key_info} | awk -F',' '{print $3}' )
				col4=$( echo ${access_key_info} | awk -F',' '{print $4}' )
				col4_fmt=$( echo ${col4} | awk -F'T' '{print $1}' )

				lastAccessDt=$( aws --region ${awsRegion} iam get-access-key-last-used --access-key-id ${col2} | egrep "LastUsedDate" | sed "s/\"//g" | sed "s/ *LastUsedDate: //g" | awk -F',' '{print $1}' | awk -F'T' '{print $1}' )
				if [ -z ${lastAccessDt} ]; then
					lastAccessDt='1970-01-01'
				fi

				#expiryDt=$( date -j -f '%Y-%m-%d' -v +90d ${col4_fmt} '+%Y-%m-%d' )
				#rotationDt=$( date -j -f '%Y-%m-%d' -v -10d ${expiryDt} '+%Y-%m-%d' )
				#last80DaysDt=$( date -j -f '%Y-%m-%d' -v -80d ${currentDt} '+%Y-%m-%d' )
				expiryDt=$( date -d"+90 days ${col4_fmt}" '+%Y-%m-%d' )
				rotationDt=$( date -d"-10 days ${expiryDt}" '+%Y-%m-%d' )
				last80DaysDt=$( date -d"-80 days ${currentDt}" '+%Y-%m-%d' )

				rotationFlag=0
				if [ $( echo ${rotationDt} | sed "s/-//g" ) -le $( echo ${currentDt} | sed "s/-//g" ) ]; then
					rotationFlag=1
				else
					rotationFlag=0
				fi
		
				lastAccessOlder80DaysFlag=0
				if [ $( echo ${lastAccessDt} | sed "s/-//g" ) -le $( echo ${last80DaysDt} | sed "s/-//g" ) ]; then
					lastAccessOlder80DaysFlag=1
				else
					lastAccessOlder80DaysFlag=0
				fi
		
				if [ ${lastAccessOlder80DaysFlag} -eq 1 ]; then
					if [ ${col3} == 'Active' ]; then
						statusInfo="Review: Not Used in Last 80days or More"
					elif [ ${col3} == 'Inactive' ]; then 
						statusInfo="ActionReqd: Delete the AccessKey"
					fi
				else
					if [ ${col3} == 'Active' ]; then
						if [ ${rotationFlag} -eq 1 ]; then
							statusInfo="ActionReqd: Due for Rotaion"
						else
							statusInfo="Ignore: Active AccessKey"
						fi
					elif [ ${col3} == 'Inactive' ]; then 
						statusInfo="Ignore: Inactive AccessKey (for now)"
					fi
				fi
				
				echo "${currentAWSAccount},${currentAWSAccountAlias},${col1},${col2},${col3},${col4_fmt},${expiryDt},${rotationDt},${lastAccessDt},${statusInfo}" >>${prjOut}/report.csv
			done
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
<h3>IAM Access Keys Report - ${currentDt}</h3>
<body>
<table border="1">
<tr>
<th bgcolor="lightblue">AWS Account</th>
<th bgcolor="lightblue">AWS Account Name</th>
<th bgcolor="lightblue">IAM User</th>
<th bgcolor="lightblue">Access Key Id</th>
<th bgcolor="lightblue">Status</th>
<th bgcolor="lightblue">Create Date</th>
<th bgcolor="lightblue">Expiry Date (90days)</th>
<th bgcolor="lightblue">Rotation Date</th>
<th bgcolor="lightblue">Last Access Date</th>
<th bgcolor="lightblue">Comment</th>
</tr>"	>${prjOut}/report.html

if [ -s ${prjOut}/report.csv ]; then
        cat ${prjOut}/report.csv | while read x
        do
                col1=$( echo $x | awk -F"," '{print $1}' )
                col2=$( echo $x | awk -F"," '{print $2}' )
                col3=$( echo $x | awk -F"," '{print $3}' )
                col4=$( echo $x | awk -F"," '{print $4}' )
                col5=$( echo $x | awk -F"," '{print $5}' )
                col6=$( echo $x | awk -F"," '{print $6}' )
                col7=$( echo $x | awk -F"," '{print $7}' )
                col8=$( echo $x | awk -F"," '{print $8}' )
                col9=$( echo $x | awk -F"," '{print $9}' )
                col10=$( echo $x | awk -F"," '{print $10}' )
                if [ $( echo "${col10}" | egrep "ActionReqd" | wc -l ) -eq 0 ]; then col10_col=""; else col10_col="red"; fi

                echo "<tr style=\"color: ${col10_col};\">
                <td>${col1}</td>
                <td>${col2}</td>
                <td>${col3}</td>
                <td>${col4}</td>
                <td>${col5}</td>
                <td>${col6}</td>
                <td>${col7}</td>
                <td>${col8}</td>
                <td>${col9}</td>
                <td>${col10}</td>
                </tr>"  >>${prjOut}/report.html
        done
else
        echo "<tr>Report NA - Pls check</tr>"	>>${prjOut}/report.html
fi
echo "</table></body></html>"	>>${prjOut}/report.html

if [ $( cat ${prjOut}/report.csv | egrep "ActionReqd" | wc -l ) -ge 1 ]; then
        echo "***** ERROR *****: Send Ops Genie alarm to obi_prod_alerts slack alarm in post build actions"
        exit 1
else
        echo "INFO             : All good. Nothing to alarm."
fi

set -x
