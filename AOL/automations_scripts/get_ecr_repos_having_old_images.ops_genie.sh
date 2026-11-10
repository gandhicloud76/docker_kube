#!/usr/bin/sh 

set +x
cutoff_days_critical=83
testHome=$(pwd); export testHome
testOut=${testHome}/output; export testOut
mkdir -p ${testOut}
rm -f ${testOut}/report*csv  2>/dev/null

set +x
cp -p /var/lib/jenkins/workspace/Report_ECR_Old_Images/output/report.critical.old.csv ${testOut}/report.critical.old.csv

echo "<html>
<h3>List of Repositories having images OLDER than ${cutoff_days_critical} days</h3>
<body>
<table border="1">
<tr>
<th bgcolor="lightblue">AWS Account</th>
<th bgcolor="lightblue">AWS Account Name</th>
<th bgcolor="lightblue">AWS Region</th>
<th bgcolor="lightblue">Repository Name</th>
<th bgcolor="lightblue">Number of Images </th>
<th bgcolor="lightblue">Number of OLD Images (older than ${cutoff_days} days)</th>
</tr>"	>${testOut}/report.html

if [ -s ${testOut}/report.critical.old.csv ]; then
	cat ${testOut}/report.critical.old.csv | while read x
	do
		col1=$( echo $x | awk -F"," '{print $1}' )
		col2=$( echo $x | awk -F"," '{print $2}' )
        col3=$( echo $x | awk -F"," '{print $3}' )
		col4=$( echo $x | awk -F"," '{print $4}' )
		col5=$( echo $x | awk -F"," '{print $5}' )
        col6=$( echo $x | awk -F"," '{print $6}' )
        fg_color=''
		if [[ ${col6} -ge 1 ]]; then
          fg_color='red'
        fi
        
		echo "<tr style=\"color: ${fg_color};\">
		<td>${col1}</td>
		<td>${col2}</td>
        <td>${col3}</td>
		<td>${col4}</td>
        <td>${col5}</td>
        <td>${col6}</td>
		</tr>"	>>${testOut}/report.html
	done
else
	echo "<tr>Report NA</tr>"
fi
echo "</table></body></html>"	>>${testOut}/report.html



# if the list has any repository having image older than cut off days then the job fails to trigger OpsGenie alert via post build actions
if [ -s ${testOut}/report.critical.old.csv ]; then
  if [[ $( cat ${testOut}/report.critical.old.csv | egrep "obi" | wc -l ) -ne 0 ]]; then
    echo "INFO: OBI Repositories"
    cat ${testOut}/report.critical.old.csv | egrep "obi"
    echo "ERROR: We have $( cat ${testOut}/report.critical.old.csv | egrep "obi" | wc -l ) repositories (maintained by OBI team) having images older than ${cutoff_days_critical} days. Send Ops Genie alarm if enabled."
    exit 1
  else
    echo "INFO: We have $( cat ${testOut}/report.critical.old.csv | egrep "obi" | wc -l ) repositories (maintained by OBI team) having images older than ${cutoff_days_critical} days. Send Ops Genie alarm if enabled."
  fi
else
  echo "INFO: nothing to alarm"
fi



set -x
