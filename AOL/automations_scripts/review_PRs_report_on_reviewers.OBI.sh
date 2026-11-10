#!/usr/bin/sh

## __author__ = 'Anil Reddy Dalli'
##
## Generate Reports on Pull Request Reviews from Gitlab and Github (for OBI team) for Reviewers 
## 

prjHome=$(pwd)
prjTmp="${prjHome}/tmp"
prjOut="${prjHome}/output"

rm -rf ${prjTmp} ${prjOut} 2>/dev/null
mkdir -p ${prjTmp} ${prjOut}

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

# Epoch value for date 2021-01-01
pr_cutoff_date='2021-01-01'
pr_cutoff_date_epc=$( date -d "${pr_cutoff_date}T00:00:00Z" '+%s' )

# get input file created by Review_PRs_RawData job
# input is created by https://jenkins.legacy.obieng.com:8443/view/Automations/job/Review_PRs_RawData/
#
if [ -s /var/lib/jenkins/git_pr_data/pr_reviews.csv ]; then
	cp -p /var/lib/jenkins/git_pr_data/pr_reviews.csv ${prjTmp}/pr_reviews.raw.csv
else
	echo "Error: File /var/lib/jenkins/git_pr_data/pr_reviews.csv Not Available"
    exit 1
fi

last_good_file=$( ls -1 /var/lib/jenkins/git_pr_data/pr_reviews.good.*.csv | tail -1 )
last_good_file_name=$( basename ${last_good_file} )
if [ -s ${last_good_file} ]; then
	cp -p ${last_good_file} ${prjTmp}/${last_good_file_name}
else
	touch ${prjTmp}/${last_good_file_name}
fi


if [ $( cat ${prjTmp}/pr_reviews.raw.csv | wc -l ) -ge $( cat ${prjTmp}/${last_good_file_name} | wc -l ) ]; then
	cp -p ${prjTmp}/pr_reviews.raw.csv ${prjTmp}/pr_reviews.csv
else
	cp -p ${prjTmp}/${last_good_file_name} ${prjTmp}/pr_reviews.csv
fi
echo "Info: Report will be based on the last good raw data generated on $( date -r ${prjTmp}/pr_reviews.csv -u +"%Y-%m-%d %H:%M:%S" )"


# get reviews which are APPROVED 
# 
cat ${prjTmp}/pr_reviews.csv | egrep ",APPROVED," >${prjTmp}/pr_reviews.approved.csv

# create detailed PR Reviews data
#
cat ${prjTmp}/pr_reviews.approved.csv | while read line
do
	pr_reviewer=$( echo ${line} | awk -F',' '{print $1}' )
    pr_url=$( echo ${line} | awk -F',' '{print $3}' )
    repo=$( echo ${pr_url} | awk -F'/' '{print $5}' )

    pr_submitted_at=$( echo ${line} | awk -F',' '{print $4}' )
	pr_submitted_at_epc=$( date -d "${pr_submitted_at}" '+%s' )
    yr=$( echo ${pr_submitted_at} | awk -F'-' '{print $1}' )
    yr_mon=$( echo ${pr_submitted_at} | awk -F'-' '{print $1"-"$2}' )

	echo "${pr_reviewer},${repo},${pr_url},${pr_submitted_at},${pr_submitted_at_epc},${yr},${yr_mon}"
done >${prjTmp}/pr_reviews.approved.detailed.csv

# create detailed PR Reviews data (starting 2021-01-01)
#
cat ${prjTmp}/pr_reviews.approved.detailed.csv | while read line
do
	pr_submitted_at_epc=$( echo ${line} | awk -F',' '{print $5}' )

	if [[ ${pr_submitted_at_epc} -ge ${pr_cutoff_date_epc} ]]; then
		echo "${line}"
	fi
done >${prjTmp}/pr_reviews.approved.detailed.${pr_cutoff_date}.csv


# create raw data for each user to show as hyperlink
#
cat ${prjTmp}/pr_reviews.approved.detailed.csv | awk -F',' '{print $1}' | sort -u | while read reviewer
do
	cat ${prjTmp}/pr_reviews.approved.detailed.csv | egrep "^${reviewer}," | awk -F',' '{print $1","$2","$3","$4}' | sort -r -t',' -k4 >${prjTmp}/pr_reviews.rolling_yearly.${reviewer}.csv
    
    echo "<html>`header`<body><table id="myTable" border=1>
    <thead>
    <tr>
    <th bgcolor=lightblue>Reviewer</th>
	<th bgcolor=lightblue>Repository</th>
	<th bgcolor=lightblue>Pull Request</th>
	<th bgcolor=lightblue>PR Create Date</th>
	</tr></thead><tbody>" >${prjOut}/pr_reviews.rolling_yearly.${reviewer}.html
    
    cat ${prjTmp}/pr_reviews.rolling_yearly.${reviewer}.csv | while read line
	do
		echo "<tr>" 
		echo ${line} | tr ',' '\n' | while read col 
		do
			echo "<td>$col</td>" 
		done 
		echo "</tr>"
	done >>${prjOut}/pr_reviews.rolling_yearly.${reviewer}.html
    
    echo "</tbody></table></body></html>" >>${prjOut}/pr_reviews.rolling_yearly.${reviewer}.html
    
done 


cat ${prjTmp}/pr_reviews.approved.detailed.${pr_cutoff_date}.csv | awk -F',' '{print $1}' | sort -u | while read reviewer
do
	cat ${prjTmp}/pr_reviews.approved.detailed.${pr_cutoff_date}.csv | egrep "^${reviewer}," | awk -F',' '{print $1","$2","$3","$4}' | sort -r -t',' -k4 >${prjTmp}/pr_reviews.rolling_monthly.${reviewer}.csv
    
    echo "<html>`header`<body><table id="myTable" border=1><thead>
    <tr>
    <th bgcolor=lightblue>Reviewer</th>
	<th bgcolor=lightblue>Repository</th>
	<th bgcolor=lightblue>Pull Request</th>
	<th bgcolor=lightblue>PR Create Date</th>
	</tr></thead><tbody>" >${prjOut}/pr_reviews.rolling_monthly.${reviewer}.html
    
    cat ${prjTmp}/pr_reviews.rolling_monthly.${reviewer}.csv | while read line
	do
		echo "<tr>" 
		echo ${line} | tr ',' '\n' | while read col 
		do
			echo "<td>$col</td>" 
		done 
		echo "</tr>"
	done >>${prjOut}/pr_reviews.rolling_monthly.${reviewer}.html
    
    echo "</tbody></table></body></html>" >>${prjOut}/pr_reviews.rolling_monthly.${reviewer}.html
done


# generate PR Reviews Count Report - Rolling Yearly
# reviewer -> count of PRs
#
cat ${prjTmp}/pr_reviews.approved.detailed.csv | awk -F',' '{print $6}' | sort -u >${prjTmp}/yr.list
cat ${prjTmp}/pr_reviews.approved.detailed.csv | awk -F',' '{print $1","$6}' | sort | uniq -c | awk '{print $2","$1}' >${prjTmp}/pr_reviews.count.rolling_yearly.1.csv

cat ${prjTmp}/pr_reviews.approved.detailed.csv | awk -F',' '{print $1}' | sort -u | while read reviewer
do
    cat ${prjTmp}/yr.list | while read yr
    do
        count=$( cat ${prjTmp}/pr_reviews.count.rolling_yearly.1.csv | egrep "${reviewer},${yr}," | awk -F',' '{print $3}' )
        if [ -z ${count} ]; then
            count=0
        fi
        echo -n "${count},"
    done >${prjTmp}/pr_reviews.count.rolling_yearly.1.tmp
    pr_count=$( cat ${prjTmp}/pr_reviews.count.rolling_yearly.1.tmp | sed "s/,$//g" )
    echo "${reviewer}:${pr_count}"
done >${prjTmp}/pr_reviews.count.rolling_yearly.2.csv

# add a summary record as all_OBI_repositories for Rolling Yearly
#
cp ${prjTmp}/pr_reviews.count.rolling_yearly.2.csv ${prjOut}/pr_reviews.count.rolling_yearly.csv

col_cnt=1
cat ${prjTmp}/yr.list | while read yr
do
    summ_cnt=$( cat ${prjTmp}/pr_reviews.count.rolling_yearly.2.csv | awk -F':' '{print $2}' | awk -v a=$col_cnt -F',' '{print $a}' | paste -sd+ - | bc )
    col_cnt=$( echo ${col_cnt} + 1 | bc )
    echo -n "${summ_cnt},"
done >${prjTmp}/pr_reviews.count.rolling_yearly.3.tmp
pr_count=$( cat ${prjTmp}/pr_reviews.count.rolling_yearly.3.tmp | sed "s/,$//g" )
echo "all_OBI_repositories:${pr_count}" >>${prjOut}/pr_reviews.count.rolling_yearly.csv

# create HTML report
#
echo "
<html>
`header`
<h3>OBI - PR Reviews Count Report for Reviewers  - Rolling Yearly : $(date '+%Y-%m-%d')</h3>
<h4>Note: Report data was generated on $( date -r ${prjTmp}/pr_reviews.csv -u +"%Y-%m-%d %H:%M:%S" )</h4>
<body>
<table id="myTable" border="1">
<thead>
<tr>
<th bgcolor="lightblue">Reviewer</th>
">${prjOut}/pr_reviews.count.rolling_yearly.html

cat ${prjTmp}/yr.list | while read yr
do
    echo "<th bgcolor="lightblue">${yr}</th>"
done >>${prjOut}/pr_reviews.count.rolling_yearly.html

echo "</tr></thead><tbody>"    >>${prjOut}/pr_reviews.count.rolling_yearly.html

cat ${prjOut}/pr_reviews.count.rolling_yearly.csv | while read line
do
    reviewer=$( echo ${line} | awk -F':' '{print $1}' )
    yr_count=$( echo ${line} | awk -F':' '{print $2}' )
    
    echo "<tr>"
    echo "<td><a href="pr_reviews.rolling_yearly.${reviewer}.html">${reviewer}</a></td>"
    echo ${yr_count} | tr ',' '\n' | while read col
    do
        echo "<td>${col}</td>"
    done
    echo "</tr>"
done >>${prjOut}/pr_reviews.count.rolling_yearly.html

echo "
</tbody>
</table>
</body>
</html>
">>${prjOut}/pr_reviews.count.rolling_yearly.html

# generate PR Reviews Count Report for Reviewers - Rolling Monthly (starting 2021-01-01)
# reviewer -> count of PRs
#
cat ${prjTmp}/pr_reviews.approved.detailed.${pr_cutoff_date}.csv | awk -F',' '{print $7}' | sort -u >${prjTmp}/yr_mon.list
cat ${prjTmp}/pr_reviews.approved.detailed.${pr_cutoff_date}.csv | awk -F',' '{print $1","$7}' | sort | uniq -c | awk '{print $2","$1}' >${prjTmp}/pr_reviews.count.rolling_monthly.1.csv

cat ${prjTmp}/pr_reviews.approved.detailed.${pr_cutoff_date}.csv | awk -F',' '{print $1}' | sort -u | while read reviewer
do
    cat ${prjTmp}/yr_mon.list | while read yr_mon
    do
        count=$( cat ${prjTmp}/pr_reviews.count.rolling_monthly.1.csv | egrep "${reviewer},${yr_mon}," | awk -F',' '{print $3}' )
        if [ -z ${count} ]; then
            count=0
        fi
        echo -n "${count},"
    done >${prjTmp}/pr_reviews.count.rolling_monthly.1.tmp
    pr_count=$( cat ${prjTmp}/pr_reviews.count.rolling_monthly.1.tmp | sed "s/,$//g" )
    echo "${reviewer}:${pr_count}"
done >${prjTmp}/pr_reviews.count.rolling_monthly.2.csv

# add a summary record as all_OBI_repositories for Rolling Yearly
#
cp ${prjTmp}/pr_reviews.count.rolling_monthly.2.csv ${prjOut}/pr_reviews.count.rolling_monthly.csv

col_cnt=1
cat ${prjTmp}/yr_mon.list | while read yr_mon
do
    summ_cnt=$( cat ${prjTmp}/pr_reviews.count.rolling_monthly.2.csv | awk -F':' '{print $2}' | awk -v a=$col_cnt -F',' '{print $a}' | paste -sd+ - | bc )
    col_cnt=$( echo ${col_cnt} + 1 | bc )
    echo -n "${summ_cnt},"
done >${prjTmp}/pr_reviews.count.rolling_monthly.3.tmp
pr_count=$( cat ${prjTmp}/pr_reviews.count.rolling_monthly.3.tmp | sed "s/,$//g" )
echo "all_OBI_repositories:${pr_count}" >>${prjOut}/pr_reviews.count.rolling_monthly.csv


# create HTML report
#
echo "
<html>
`header`
<h3>OBI - PR Reviews Count Report - Rolling Monthly : $(date '+%Y-%m-%d')</h3>
<h4>Note: This report is on PRs created after ${pr_cutoff_date}</h4>
<h4>Note: Report data was generated on $( date -r ${prjTmp}/pr_reviews.csv -u +"%Y-%m-%d %H:%M:%S" )</h4>
<body>
<table id="myTable" border="1"><thead>
<tr>
<th bgcolor="lightblue">Reviewer</th>
">${prjOut}/pr_reviews.count.rolling_monthly.html

cat ${prjTmp}/yr_mon.list | while read yr_mon
do
    echo "<th bgcolor="lightblue">${yr_mon}</th>"
done >>${prjOut}/pr_reviews.count.rolling_monthly.html

echo "</tr></thead><tbody>"    >>${prjOut}/pr_reviews.count.rolling_monthly.html

num_fields_rm=$( cat ${prjOut}/pr_reviews.count.rolling_monthly.csv | awk -F',' '{print NF}' | sort -nr -u | head -1 )
cat ${prjOut}/pr_reviews.count.rolling_monthly.csv | sort -nr -t ',' -k | while read line
do
	reviewer=$( echo ${line} | awk -F':' '{print $1}' )
    yr_mon_count=$( echo ${line} | awk -F':' '{print $2}' )
    
    echo "<tr>"
    echo "<td><a href="pr_reviews.rolling_monthly.${reviewer}.html">${reviewer}</a></td>"
    echo ${yr_mon_count} | tr ',' '\n' | while read col
    do
        echo "<td>${col}</td>"
    done
    echo "</tr>"
done >>${prjOut}/pr_reviews.count.rolling_monthly.html

echo "
</tbody>
</table>
</body>
</html>
">>${prjOut}/pr_reviews.count.rolling_monthly.html

#copy to home
cp -p ${prjOut}/pr_reviews.count.rolling_yearly.csv /home/ec2-user/pr_reviews.count.rolling_yearly.csv
cp -p ${prjOut}/pr_reviews.count.rolling_monthly.csv /home/ec2-user/pr_reviews.count.rolling_monthly.csv
