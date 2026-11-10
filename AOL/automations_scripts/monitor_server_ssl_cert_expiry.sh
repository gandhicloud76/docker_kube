#!/usr/bin/sh 

set +x
#__author__ = 'anildalli'

# variables
prjHome=$(pwd); export prjHome
prjOut=${prjHome}/output; export prjOut
currentDt=$( date '+%Y-%m-%d' )
jenkinsIPaddress=$( hostname -I | awk '{print $1}' )
cts=$( date '+%Y-%m-%d %H:%M' )
cts_epc=$( date '+%s' )
notify_days=4

# called while building HTML page
header() {
cat<<-EOF
<head>
<script src="https://ajax.googleapis.com/ajax/libs/jquery/1.11.2/jquery.min.js" type="text/javascript"></script>
<link rel="stylesheet" type="text/css" href="https://cdn.datatables.net/1.11.2/css/jquery.dataTables.css">
<script type="text/javascript" charset="utf8" src="https://cdn.datatables.net/1.11.2/js/jquery.dataTables.js"></script>

<script>
\$(document).ready( function () {
	var indexLastColumn = \$("#myTable").find('tr')[0].cells.length-1;
	\$('#myTable').DataTable({
	"pageLength": 100,
	"order":[[indexLastColumn,'desc']]
	});
} );
</script>
</head>
EOF
}

mkdir -p ${prjOut}
rm -f ${prjOut}/* 2>/dev/null

cp ${prjHome}/automations/iam_roles.automations.txt ${prjOut}/iam_roles.txt
cp ${prjHome}/automations/server_ssl_certificate_expiry.ecs.allowlist ${prjOut}/server_ssl_certificate_expiry.ecs.allowlist
cp ${prjHome}/automations/server_ssl_certificate_expiry.lb.allowlist ${prjOut}/server_ssl_certificate_expiry.lb.allowlist

echo "# project-home      : ${prjHome}"
echo "# role-session-name : ${jenkinsIPaddress}"
echo "# current-timestamp : $( date '+%Y-%m-%d %H:%M')"

for currentAWSRole in ${AWS_ROLE}; do
for awsRegion in ${AWS_REGION}; do
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
        echo "${currentAWSAccount},${currentAWSAccountAlias}" >>${prjOut}/acct_alias.mapping.txt

		echo "################################################################"
		echo "AWS Account: ${currentAWSAccount} - ${currentAWSAccountAlias}"
		echo "################################################################"
        echo "## awsRegion         : ${awsRegion}"
		#
    	# ecs
    	#
		ecs_clusters=$( aws --region ${awsRegion} ecs list-clusters --query 'clusterArns' | jq -r '.[]' )
		ecs_clusters_array=(${ecs_clusters})
		if [[ ${#ecs_clusters_array[@]} -ne 0 ]]; then
			for cluster_name in ${ecs_clusters_array[@]}; do
                echo "Cluster : ${cluster_name}"
                cluster_name_fmt=$( echo ${cluster_name} | awk -F"/" '{print $NF}' )
                ecs_services=$( aws --region ${awsRegion} ecs list-services --cluster ${cluster_name_fmt} --query 'serviceArns' | jq -r '.[]' )
                ecs_services_array=(${ecs_services})
                if [[ ${#ecs_services_array[@]} -ne 0 ]]; then
                    for service_name in ${ecs_services_array[@]}; do
                        echo "  Service : ${service_name}"
                        service_name_fmt=$( echo ${service_name} | awk -F"/" '{print $NF}' )
                        ecs_service_subnet=$( aws --region ${awsRegion} ecs describe-services --cluster ${cluster_name_fmt} --services ${service_name_fmt} | jq -r '.services[].deployments[].networkConfiguration.awsvpcConfiguration.subnets[0]' )
                        if [[ -z ${ecs_service_subnet} ]]; then
                        	ecs_service_subnet=$( aws --region ${awsRegion} ecs describe-services --cluster ${cluster_name_fmt} --services ${service_name_fmt} | jq -r '.services[].taskSets[].networkConfiguration.awsvpcConfiguration.subnets[0]' )
                        fi
                        ecs_service_vpc=$( aws --region ${awsRegion} ec2 describe-subnets --subnet-ids ${ecs_service_subnet} | jq -r '.Subnets[].VpcId' ) 
                        ecs_tasks=$( aws --region ${awsRegion} ecs list-tasks --cluster ${cluster_name} --service-name ${service_name_fmt} | jq -r '.taskArns[]' )
			            ecs_tasks_array=(${ecs_tasks})
				        if [[ ${#ecs_tasks_array[@]} -ne 0 ]]; then
					        for task_name in ${ecs_tasks_array[@]}; do
                                echo "    Task : ${task_name}"
                                task_name_fmt=$( echo ${task_name} | awk -F"/" '{print $NF}' )
                                task_private_ip=$( aws --region ${awsRegion} ecs describe-tasks --cluster ${cluster_name} --tasks ${task_name_fmt} | jq -r '.tasks[].attachments[].details[] | select( .name == "privateIPv4Address" ) | .value' )
                                payload=$( echo {\"private_ip\":\"${task_private_ip}:443\"} | base64 -w 0 )
                                rm outputfile.txt 2>/dev/null
                                cert_expiration_dt=$( aws --region ${awsRegion} lambda invoke --function-name get_ssl_cert_expiry_${ecs_service_vpc} --payload "${payload}" outputfile.txt >/dev/null; cat outputfile.txt | sed "s/,/ /g" )
                                if [[ -z ${cert_expiration_dt} ]]; then
                                	cert_expiration_dt=NotAvailable
                                	cert_expiration_dt_epc=0
                            	else
                            		if [[ $( echo ${cert_expiration_dt} | egrep -iv error | egrep "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]" | wc -l ) -eq 1 ]]; then
                                		cert_expiration_dt_epc=$( date -d "${cert_expiration_dt}" '+%s' )
                                	else
                                    	cert_expiration_dt_epc=0
                                	fi
                            	fi
                                notify_for_expiry=0
                                if [[ ${cert_expiration_dt_epc} -ne 0 ]]; then
                            		epc_diff=$( echo ${cert_expiration_dt_epc} - ${cts_epc} | bc )
                             		days_for_expiry=$( echo ${epc_diff} / 3600 / 24 | bc )
                                    if [[ ${days_for_expiry} -le ${notify_days} ]]; then
                                    	notify_for_expiry=1
                                    fi
                        		else
                             		days_for_expiry=ERROR
                        		fi
								if [[ -s ${prjOut}/server_ssl_certificate_expiry.ecs.allowlist ]]; then
									if [[ $( echo ${service_name_fmt} | egrep -f ${prjOut}/server_ssl_certificate_expiry.ecs.allowlist | wc -l ) -ne 0 ]]; then
										days_for_expiry=IGNORE
									fi
								fi
                                #AWS Account Number
							    #AWS Account Name
                                #AWS Region
							    #Cluster Name
                                #Service Name
                                #VPC
							    #Task ID
							    #Task Private IP
                                #SSL Certificate Expiry Date
                                #Days For Expiry
                                echo "${currentAWSAccount},${currentAWSAccountAlias},${awsRegion},${cluster_name_fmt},${service_name_fmt},${ecs_service_vpc},${task_name_fmt},${task_private_ip},${cert_expiration_dt},${days_for_expiry},${notify_for_expiry}" >>${prjOut}/report.ecs.csv
                            done
                        fi
				    done
			    fi
			done
        fi
    	#
    	# elbv2
    	#
    	elbv2Arns=$( aws --region ${awsRegion} elbv2 describe-load-balancers | jq -r '.LoadBalancers[].LoadBalancerArn' )
    	#elbv2Arns=''
    	elbv2Arns_array=(${elbv2Arns})
    	echo "Reading ${#elbv2Arns_array[@]} load balancers (alb,nlb)"

    	if [[ ${#elbv2Arns_array[@]} -ne 0 ]]; then
      		for elbv2Arn in ${elbv2Arns_array[@]}; do
				echo "Load Balancer : ${elbv2Arn}"
        		aws --region ${awsRegion} elbv2 describe-load-balancers --load-balancer-arns ${elbv2Arn} >${prjOut}/elbv2.json

        		lbName=$( cat ${prjOut}/elbv2.json | jq -r '.LoadBalancers[].LoadBalancerName' )
                lbType=$( cat ${prjOut}/elbv2.json | jq -r '.LoadBalancers[].Type')
                if [[ ${lbType} == "application" ]]; then
                	lbArnShortName=$( cat ${prjOut}/elbv2.json | jq -r '.LoadBalancers[].LoadBalancerArn' | awk -F':' '{print $NF}' | sed "s/loadbalancer\///g" )
                	lbNetworkInterfacesDescription=$( echo "ELB ${lbArnShortName}" )
                	lb_vpc=$( aws --region ${awsRegion} ec2 describe-network-interfaces | jq -r --arg lbNetworkInterfacesDescription "${lbNetworkInterfacesDescription}" '.NetworkInterfaces[] | select( .Description == "'"$lbNetworkInterfacesDescription"'" ) | .VpcId' | sort -u )
                	lb_private_ips=$( aws --region ${awsRegion} ec2 describe-network-interfaces | jq -r --arg lbNetworkInterfacesDescription "${lbNetworkInterfacesDescription}" '.NetworkInterfaces[] | select( .Description == "'"${lbNetworkInterfacesDescription}"'" ) | .PrivateIpAddress' )
                	lb_private_ips_array=(${lb_private_ips})
                	if [[ ${#lb_private_ips_array[@]} -ne 0 ]]; then
                		for lbPrivateIp in ${lb_private_ips_array[@]}; do
                        	payload=$( echo {\"private_ip\":\"${lbPrivateIp}:443\"} | base64 -w 0 )
                            rm outputfile.txt 2>/dev/null
                        	cert_expiration_dt=$( aws --region ${awsRegion} lambda invoke --function-name get_ssl_cert_expiry_${lb_vpc} --payload "${payload}" outputfile.txt >/dev/null; cat outputfile.txt | sed "s/,/ /g" )
                            if [[ -z ${cert_expiration_dt} ]]; then
                                cert_expiration_dt=NA
                                cert_expiration_dt_epc=0
                            else
                            	if [[ $( echo ${cert_expiration_dt} | egrep -iv error | egrep "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]" | wc -l ) -eq 1 ]]; then
                                	cert_expiration_dt_epc=$( date -d "${cert_expiration_dt}" '+%s' )
                                else
                                    cert_expiration_dt_epc=0
                                fi
                            fi
                            notify_for_expiry=0
                            if [[ ${cert_expiration_dt_epc} -ne 0 ]]; then
                            	epc_diff=$( echo ${cert_expiration_dt_epc} - ${cts_epc} | bc )
                             	days_for_expiry=$( echo ${epc_diff} / 3600 / 24 | bc )
                                if [[ ${days_for_expiry} -le ${notify_days} ]]; then
                                    notify_for_expiry=1
                                fi
                        	else
                             	days_for_expiry=ERROR
                        	fi
							if [[ -s ${prjOut}/server_ssl_certificate_expiry.lb.allowlist ]]; then
								if [[ $( echo ${lbName} | egrep -f ${prjOut}/server_ssl_certificate_expiry.lb.allowlist | wc -l ) -ne 0 ]]; then
									days_for_expiry=IGNORE
								fi
							fi
                            #AWS Account Number
						    #AWS Account Name
                            #AWS Region
						    #Load Balancer Name
                            #Type
                            #VPC
						    #Task Private IP
                            #SSL Certificate Expiry Date
                            #Days For Expiry
            				echo "${currentAWSAccount},${currentAWSAccountAlias},${awsRegion},${lbName},${lbType},${lb_vpc},${lbPrivateIp},${cert_expiration_dt},${days_for_expiry},${notify_for_expiry}" >>${prjOut}/report.lb.csv
                    	done
                	fi
                fi
      		done
    	fi
	else
		echo "ERROR: AssumeRole operation"
	fi
  
	rm -f awscre-${currentAWSAccount} 2>/dev/null
done
# end of loop for AWS Roles
done
# end of loop for AWS Regions

if [ -s ${prjOut}/report.ecs.csv ]; then
	cp -p ${prjOut}/report.ecs.csv ${prjOut}/report.ecs.all.csv
	cat ${prjOut}/report.ecs.csv | egrep -v ",IGNORE," | egrep ",1$|,ERROR"	>${prjOut}/report.ecs.notify.csv
fi
if [ -s ${prjOut}/report.lb.csv ]; then
	cp -p ${prjOut}/report.lb.csv ${prjOut}/report.lb.all.csv
	cat ${prjOut}/report.lb.csv | egrep -v ",IGNORE," | egrep ",1$|,ERROR"	>${prjOut}/report.lb.notify.csv
fi

# Create HTML report
echo "<html>
`header`
<h3>ECS Tasks SSL Certificates Expiry - ${cts}</h3>
<body>
<table border="1">
<tr>
<th bgcolor="lightblue">AWS-Account</th>
<th bgcolor="lightblue">AWS-Account Name</th>
<th bgcolor="lightblue">AWS-Region</th>
<th bgcolor="lightblue">ECS-Cluster-Name</th>
<th bgcolor="lightblue">ECS-Service-Name</th>
<th bgcolor="lightblue">VPC</th>
<th bgcolor="lightblue">Task-ID</th>
<th bgcolor="lightblue">Task-Private-Ip</th>
<th bgcolor="lightblue">SSL-Cert-Expiration-Date</th>
<th bgcolor="lightblue">Days-For-Expiry</th>
</tr>"	>${prjOut}/report.ecs.all.html

if [ -s ${prjOut}/report.ecs.all.csv ]; then
	cat ${prjOut}/report.ecs.all.csv | while read x
	do
    row_col=""
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
    col11=$( echo $x | awk -F"," '{print $11}' )
    if [[ ${col10} == "IGNORE" ]]; then
        row_col=blue
    elif [[ ${col10} == "ERROR" ]];then
        row_col=red
    fi
    if [[ ${col11} -eq 1 ]]; then
        row_col=red
    fi

		echo "<tr>
		<td><font color=${row_col}>${col1}</font></td>
		<td><font color=${row_col}>${col2}</font></td>
		<td><font color=${row_col}>${col3}</font></td>
		<td><font color=${row_col}>${col4}</font></td>
		<td><font color=${row_col}>${col5}</font></td>
		<td><font color=${row_col}>${col6}</font></td>
		<td><font color=${row_col}>${col7}</font></td>
		<td><font color=${row_col}>${col8}</font></td>
    <td><font color=${row_col}>${col9}</font></td>
    <td><font color=${row_col}>${col10}</font></td>
		</tr>"	>>${prjOut}/report.ecs.all.html
	done
else
	echo "<tr>Report NA</tr>" >>${prjOut}/report.ecs.all.html
fi
echo "</table></body></html>"	>>${prjOut}/report.ecs.all.html

echo "<html>
`header`
<h3>ECS Tasks SSL Certificates Expiry - ${cts}</h3>
<body>
<table border="1">
<tr>
<th bgcolor="lightblue">AWS-Account</th>
<th bgcolor="lightblue">AWS-Account Name</th>
<th bgcolor="lightblue">AWS-Region</th>
<th bgcolor="lightblue">ECS-Cluster-Name</th>
<th bgcolor="lightblue">ECS-Service-Name</th>
<th bgcolor="lightblue">VPC</th>
<th bgcolor="lightblue">Task-ID</th>
<th bgcolor="lightblue">Task-Private-Ip</th>
<th bgcolor="lightblue">SSL-Cert-Expiration-Date</th>
<th bgcolor="lightblue">Days-For-Expiry</th>
</tr>"	>${prjOut}/report.ecs.notify.html

if [ -s ${prjOut}/report.ecs.notify.csv ]; then
	cat ${prjOut}/report.ecs.notify.csv | while read x
	do
    row_col=""
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
    col11=$( echo $x | awk -F"," '{print $11}' )
    if [[ ${col10} == "IGNORE" ]]; then
        row_col=blue
    elif [[ ${col10} == "ERROR" ]];then
        row_col=red
    fi
    if [[ ${col11} -eq 1 ]]; then
        row_col=red
    fi

		echo "<tr>
		<td><font color=${row_col}>${col1}</font></td>
		<td><font color=${row_col}>${col2}</font></td>
		<td><font color=${row_col}>${col3}</font></td>
		<td><font color=${row_col}>${col4}</font></td>
		<td><font color=${row_col}>${col5}</font></td>
		<td><font color=${row_col}>${col6}</font></td>
		<td><font color=${row_col}>${col7}</font></td>
		<td><font color=${row_col}>${col8}</font></td>
    <td><font color=${row_col}>${col9}</font></td>
    <td><font color=${row_col}>${col10}</font></td>
		</tr>"	>>${prjOut}/report.ecs.notify.html
	done
else
	echo "<tr>Report NA</tr>" >>${prjOut}/report.ecs.notify.html
fi
echo "</table></body></html>"	>>${prjOut}/report.ecs.notify.html


# Create HTML report
echo "<html>
`header`
<h3>Load Balancer SSL Certificates Expiry - ${cts}</h3>
<body>
<table border="1">
<tr>
<th bgcolor="lightblue">AWS-Account</th>
<th bgcolor="lightblue">AWS-Account Name</th>
<th bgcolor="lightblue">AWS-Region</th>
<th bgcolor="lightblue">Load-Balancer-Name</th>
<th bgcolor="lightblue">Type</th>
<th bgcolor="lightblue">VPC</th>
<th bgcolor="lightblue">Task-Private-Ip</th>
<th bgcolor="lightblue">SSL-Cert-Expiration-Date</th>
<th bgcolor="lightblue">Days-For-Expiry</th>
</tr>"	>${prjOut}/report.lb.all.html

if [ -s ${prjOut}/report.lb.all.csv ]; then
	cat ${prjOut}/report.lb.all.csv | while read x
	do
    row_col=""
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
    if [[ ${col9} == "IGNORE" ]]; then
        row_col=blue
    elif [[ ${col9} == "ERROR" ]];then
        row_col=red
    fi
    if [[ ${col10} -eq 1 ]]; then
      	row_col=red
    fi

		echo "<tr>
		<td><font color=${row_col}>${col1}</font></td>
		<td><font color=${row_col}>${col2}</font></td>
		<td><font color=${row_col}>${col3}</font></td>
		<td><font color=${row_col}>${col4}</font></td>
		<td><font color=${row_col}>${col5}</font></td>
		<td><font color=${row_col}>${col6}</font></td>
		<td><font color=${row_col}>${col7}</font></td>
    <td><font color=${row_col}>${col8}</font></td>
    <td><font color=${row_col}>${col9}</font></td>
		</tr>"	>>${prjOut}/report.lb.all.html
	done
else
	echo "<tr>Report NA</tr>" >>${prjOut}/report.lb.all.html
fi
echo "</table></body></html>"	>>${prjOut}/report.lb.all.html


# Create HTML report
echo "<html>
`header`
<h3>Load Balancer SSL Certificates Expiry - ${cts}</h3>
<body>
<table border="1">
<tr>
<th bgcolor="lightblue">AWS-Account</th>
<th bgcolor="lightblue">AWS-Account Name</th>
<th bgcolor="lightblue">AWS-Region</th>
<th bgcolor="lightblue">Load-Balancer-Name</th>
<th bgcolor="lightblue">Type</th>
<th bgcolor="lightblue">VPC</th>
<th bgcolor="lightblue">Task-Private-Ip</th>
<th bgcolor="lightblue">SSL-Cert-Expiration-Date</th>
<th bgcolor="lightblue">Days-For-Expiry</th>
</tr>"	>${prjOut}/report.lb.notify.html

if [ -s ${prjOut}/report.lb.notify.csv ]; then
	cat ${prjOut}/report.lb.notify.csv | while read x
	do
    row_col=""
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
    if [[ ${col9} == "IGNORE" ]]; then
        row_col=blue
    elif [[ ${col9} == "ERROR" ]];then
        row_col=red
    fi
    if [[ ${col10} -eq 1 ]]; then
       	row_col=red
    fi

		echo "<tr>
		<td><font color=${row_col}>${col1}</font></td>
		<td><font color=${row_col}>${col2}</font></td>
		<td><font color=${row_col}>${col3}</font></td>
		<td><font color=${row_col}>${col4}</font></td>
		<td><font color=${row_col}>${col5}</font></td>
		<td><font color=${row_col}>${col6}</font></td>
		<td><font color=${row_col}>${col7}</font></td>
    <td><font color=${row_col}>${col8}</font></td>
    <td><font color=${row_col}>${col9}</font></td>
		</tr>"	>>${prjOut}/report.lb.notify.html
	done
else
	echo "<tr>Report NA</tr>" >>${prjOut}/report.lb.notify.html
fi
echo "</table></body></html>"	>>${prjOut}/report.lb.notify.html



# Notify Slack if any Server SSL Certs Expire in less than ${notify_days} days
if [[ -s ${prjOut}/report.lb.notify.csv ]]; then
	if [[ $( cat ${prjOut}/report.lb.notify.csv | wc -l ) -ne 0 ]]; then
    	echo "ERROR: We have $( cat ${prjOut}/report.lb.notify.csv | wc -l ) load balancers whose SSL Cert will expire in less than ${notify_days} days. Send alarm to slack if enabled."
    	exit 1
	fi
else
  echo "INFO: nothing to alarm"
fi
# Notify Slack if any Server SSL Certs Expire in less than ${notify_days} days
if [[ -s ${prjOut}/report.ecs.notify.csv ]]; then
	if [[ $( cat ${prjOut}/report.ecs.notify.csv | wc -l ) -ne 0 ]]; then
    	echo "ERROR: We have $( cat ${prjOut}/report.ecs.notify.csv | wc -l ) ECS tasks whose SSL Cert will expire in less than ${notify_days} days. Send alarm to slack if enabled."
    	exit 1
	fi
else
  echo "INFO: nothing to alarm"
fi


set -x
