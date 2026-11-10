#!/usr/bin/sh

set +x

# Initialize variables
#
prjHome=$(pwd)
prjTmp="${prjHome}/tmp"
prjOut="${prjHome}/output"
cts=$( date '+%Y%m%d_%H%M%S' )

# Common Target directory
#
targetDir="/var/lib/jenkins/git_reports"


# Cleanup previous run
#
rm -rf ${prjTmp} ${prjOut} 2>/dev/null
mkdir -p ${prjTmp} ${prjOut} 
mkdir -p ${targetDir}
ls -l ${targetDir}/*csv 2>/dev/null
wc -l ${targetDir}/*csv 2>/dev/null

# calculate the time taken in seconds
#
calc_timetaken() {
    if [[ $epmystarttime == "" ]]; then
        epmystarttime=$( date +%s )
    fi
    epmyendtime=$( date +%s )
    eptimediff=$( expr $epmyendtime - $epmystarttime )
    epmystarttime=$( echo -e $epmyendtime )

	echo "timetaken $eptimediff secs"
}
calc_timetaken  >/dev/null

if [[ -s ${targetDir}/pr.full.csv ]]; then
	cat ${targetDir}/pr.full.csv | sort -u  | egrep -v ",ignoreclosed," >${prjTmp}/pr.full.csv
    cp -p ${prjTmp}/pr.full.csv ${prjTmp}/pr.0.csv
    echo "### PR raw data"
    ls -l ${prjTmp}/pr.0.csv
    wc -l ${prjTmp}/pr.0.csv
fi

# ---- List of fields (${prjTmp}/pr.0.csv)
#
#gitType,
#repoName,
#git_pr_url_md5sum,
#git_pr_url,
#git_pr_title,
#git_pr_state,
#git_pr_creator,
#git_pr_created_at,
#git_pr_created_at_yyyy,
#git_pr_created_at_yyyymm,
#git_pr_last_updated_at,
#git_pr_last_updated_at_yyyy,
#git_pr_last_updated_at_yyyymm,
#git_pr_reviewer,
#git_pr_review_state

##########################
# PR raw data - Cleanup #1 
# Exclude PRs from pipeline to main i.e. PRs with title "Pull request for prod release"
#
cat ${prjTmp}/pr.0.csv | egrep -v "Pull request for prod release|obi_tools" >${prjTmp}/pr.1.csv
echo "### PR raw data (exclude Pull request for prod release and obi_tools)"
ls -l ${prjTmp}/pr.1.csv
wc -l ${prjTmp}/pr.1.csv
calc_timetaken

# ---- List of fields (${prjTmp}/pr.0.csv)
#
# no change

##########################
# PR raw data - Cleanup #2 (for creators)
# Drop fields - gitType, git_pr_url_md5sum,git_pr_title
#             - git_pr_last_updated_at_yyyy,git_pr_last_updated_at_yyyymm, git_pr_reviewer, git_pr_review_state
# Organize the fields
# Remove dupes
cat ${prjTmp}/pr.1.csv | awk -F',' '{print $2","$4","$6","$7","$8","$9","$10}' | sort -u >${prjTmp}/pr.2a.csv
echo "### PR raw data (for creators)"
ls -l ${prjTmp}/pr.2a.csv
wc -l ${prjTmp}/pr.2a.csv

cat ${prjTmp}/pr.2a.csv | awk -F',' '{print $1","$2","$3}' | sort -u | while read col_123
do
    col_4567=$( cat ${prjTmp}/pr.2a.csv | egrep "${col_123}," | awk -F',' '{print $4","$5","$6","$7}' | sort -u | tail -1 )
    echo "${col_123},${col_4567}"
done >${prjTmp}/pr.2b.csv

echo "### PR raw data (prepare raw data for weekly - cleanup dupes)"
ls -l ${prjTmp}/pr.2b.csv
wc -l ${prjTmp}/pr.2b.csv

calc_timetaken
# ---- List of fields (${prjTmp}/pr.2a.csv and ${prjTmp}/pr.2b.csv )
#
#repoName,
#git_pr_url,
#git_pr_state,
#git_pr_creator,
#git_pr_created_at
#git_pr_created_at_yyyy,
#git_pr_created_at_yyyymm,



##########################
# PR raw data - Cleanup #3 (for reviewers
# Drop fields - gitType, git_pr_url_md5sum,git_pr_title, git_pr_creator,git_pr_created_at_yyyy,git_pr_created_at_yyyymm,
#             - git_pr_review_state
# Organize the fields
cat ${prjTmp}/pr.1.csv | egrep -v ",NA$" | awk -F',' '{print $2","$4","$6","$14","$11","$12","$13}' | sort -u >${prjTmp}/pr.3.csv
echo "### PR raw data (for top reviewer)"
ls -l ${prjTmp}/pr.3.csv
wc -l ${prjTmp}/pr.3.csv
calc_timetaken
# ---- List of fields (${prjTmp}/pr.3.csv)
#
#repoName,
#git_pr_url,
#git_pr_state,
#git_pr_reviewer,
#git_pr_last_updated_at
#git_pr_last_updated_at_yyyy,
#git_pr_last_updated_at_yyyymm,

echo "### PR raw data (rename)"
cat ${prjTmp}/pr.2b.csv  | sort -u | sort -t',' -k5 >${prjTmp}/pr.raw.creators.csv
cat ${prjTmp}/pr.3.csv  | sort -u | sort -t',' -k4 >${prjTmp}/pr.raw.reviewers.csv
ls -l ${prjTmp}/pr.raw.*.csv
wc -l ${prjTmp}/pr.raw.*.csv


##
## Rolling Yearly
echo "### Rolling Yearly reports"
num_years_rpt=3
while [ ${num_years_rpt} -ge 0 ]; do
  date -d "-${num_years_rpt} years" '+%Y'
  num_years_rpt=$( echo "${num_years_rpt} - 1"| bc )
done >${prjTmp}/yr.list

#
# ------------------- CREATORS ###########################################################################
cat ${prjTmp}/yr.list | while read yr
do
    cat ${prjTmp}/pr.raw.creators.csv | sort -u | sort -t',' -k6 | egrep ",${yr}," | awk -F',' '{print $4}' | sort | uniq -c | awk '{print $2","$1}' | sed "s/^/${yr},/g"
done >${prjTmp}/pr.raw.creators.roll_yr.csv

cat ${prjTmp}/pr.raw.creators.roll_yr.csv | awk -F',' '{print $2}' | sort -u | while read creator
do
    cat ${prjTmp}/yr.list | while read yr
    do
        count=$( cat ${prjTmp}/pr.raw.creators.roll_yr.csv | egrep "${yr},${creator}," | awk -F',' '{print $3}' )
        if [ -z ${count} ]; then
            count=0
        fi
        echo -n "${count},"
    done >${prjTmp}/pr.tmp
    pr_count=$( cat ${prjTmp}/pr.tmp | sed "s/,$//g" )
    echo "${creator}:${pr_count}"	>>${prjTmp}/pr.creators.roll_yr.csv
done

#
# ------------------- REVIEWERS
cat ${prjTmp}/yr.list | while read yr
do
    cat ${prjTmp}/pr.raw.reviewers.csv | sort -u | sort -t',' -k6 | egrep ",${yr}," | awk -F',' '{print $4}' | sort | uniq -c | awk '{print $2","$1}' | sed "s/^/${yr},/g"
done >${prjTmp}/pr.raw.reviewers.roll_yr.csv

cat ${prjTmp}/pr.raw.reviewers.roll_yr.csv | awk -F',' '{print $2}' | sort -u | while read reviewer
do
    cat ${prjTmp}/yr.list | while read yr
    do
        count=$( cat ${prjTmp}/pr.raw.reviewers.roll_yr.csv | egrep "${yr},${reviewer}," | awk -F',' '{print $3}' )
        if [ -z ${count} ]; then
            count=0
        fi
        echo -n "${count},"
    done >${prjTmp}/pr.tmp
    pr_count=$( cat ${prjTmp}/pr.tmp | sed "s/,$//g" )
    echo "${reviewer}:${pr_count}"	>>${prjTmp}/pr.reviewers.roll_yr.csv
done
calc_timetaken
##
## Rolling Monthly ###########################################################################
echo "### Rolling Monthly reports"
num_months_rpt=15
while [ ${num_months_rpt} -ge 0 ]; do
  date -d "-${num_months_rpt} months" '+%Y%m'
  num_months_rpt=$( echo "${num_months_rpt} - 1"| bc )
done >${prjTmp}/mths.list

#
# ------------------- CREATORS
cat ${prjTmp}/mths.list | while read mth
do
    cat ${prjTmp}/pr.raw.creators.csv | sort -u | sort -t',' -k7 | egrep ",${mth}$" | awk -F',' '{print $4}' | sort | uniq -c | awk '{print $2","$1}' | sed "s/^/${mth},/g"
done >${prjTmp}/pr.raw.creators.roll_mths.csv

cat ${prjTmp}/pr.raw.creators.roll_mths.csv | awk -F',' '{print $2}' | sort -u | while read creator
do
    cat ${prjTmp}/mths.list | while read mth
    do
        count=$( cat ${prjTmp}/pr.raw.creators.roll_mths.csv | egrep "${mth},${creator}," | awk -F',' '{print $3}' )
        if [ -z ${count} ]; then
            count=0
        fi
        echo -n "${count},"
    done >${prjTmp}/pr.tmp
    pr_count=$( cat ${prjTmp}/pr.tmp | sed "s/,$//g" )
    echo "${creator}:${pr_count}"	>>${prjTmp}/pr.creators.roll_mths.csv
done


#
# ------------------- REVIEWERS
cat ${prjTmp}/mths.list | while read mth
do
    cat ${prjTmp}/pr.raw.reviewers.csv | sort -u | sort -t',' -k7 | egrep ",${mth}$" | awk -F',' '{print $4}' | sort | uniq -c | awk '{print $2","$1}' | sed "s/^/${mth},/g"
done >${prjTmp}/pr.raw.reviewers.roll_mths.csv

cat ${prjTmp}/pr.raw.reviewers.roll_mths.csv | awk -F',' '{print $2}' | sort -u | while read reviewer
do
    cat ${prjTmp}/mths.list | while read mth
    do
        count=$( cat ${prjTmp}/pr.raw.reviewers.roll_mths.csv | egrep "${mth},${reviewer}," | awk -F',' '{print $3}' )
        if [ -z ${count} ]; then
            count=0
        fi
        echo -n "${count},"
    done >${prjTmp}/pr.tmp
    pr_count=$( cat ${prjTmp}/pr.tmp | sed "s/,$//g" )
    echo "${reviewer}:${pr_count}"	>>${prjTmp}/pr.reviewers.roll_mths.csv
done
calc_timetaken
cp -p ${prjTmp}/pr.creators.*.csv ${prjOut}/
cp -p ${prjTmp}/pr.reviewers.*.csv ${prjOut}/


#
# create PRs for creators and reviewers for links from main report
#
echo "### HTML reports"
# ------------------- CREATORS
cat ${prjTmp}/pr.raw.creators.csv | awk -F',' '{print $4}' | sort -u | while read creator
do
  	cat ${prjTmp}/pr.raw.creators.csv | egrep ",${creator}," | egrep -f ${prjTmp}/yr.list | awk -F',' '{print $4","$1","$2","$5}' | sort -r -t',' -k4 >${prjTmp}/pr.creators.roll_yr.${creator}.csv
    echo "<html>`header`<body><table id="myTable" border=1><thead>
    <tr>
      <th bgcolor=lightblue>Creator</th>
      <th bgcolor=lightblue>Repository</th>
      <th bgcolor=lightblue>Pull Request</th>
      <th bgcolor=lightblue>Create Date</th>
    </tr></thead><tbody>" >${prjOut}/pr.creators.roll_yr.${creator}.html

    cat ${prjTmp}/pr.creators.roll_yr.${creator}.csv | while read line
  	do
    	echo "<tr>"
    	echo ${line} | tr ',' '\n' | while read col
    	do
      		echo "<td>$col</td>"
    	done
    	echo "</tr>"
  	done >>${prjOut}/pr.creators.roll_yr.${creator}.html

    echo "</tbody></table></body></html>" >>${prjOut}/pr.creators.roll_yr.${creator}.html
done

cat ${prjTmp}/pr.raw.creators.csv | awk -F',' '{print $4}' | sort -u | while read creator
do
  	cat ${prjTmp}/pr.raw.creators.csv | egrep ",${creator}," | egrep -f ${prjTmp}/mths.list | awk -F',' '{print $4","$1","$2","$5}' | sort -r -t',' -k4 >${prjTmp}/pr.creators.roll_mths.${creator}.csv
    echo "<html>`header`<body><table id="myTable" border=1><thead>
    <tr>
      <th bgcolor=lightblue>Creator</th>
      <th bgcolor=lightblue>Repository</th>
      <th bgcolor=lightblue>Pull Request</th>
      <th bgcolor=lightblue>Create Date</th>
    </tr></thead><tbody>" >${prjOut}/pr.creators.roll_mths.${creator}.html

    cat ${prjTmp}/pr.creators.roll_mths.${creator}.csv | while read line
  	do
    	echo "<tr>"
    	echo ${line} | tr ',' '\n' | while read col
    	do
      		echo "<td>$col</td>"
    	done
    	echo "</tr>"
  	done >>${prjOut}/pr.creators.roll_mths.${creator}.html

    echo "</tbody></table></body></html>" >>${prjOut}/pr.creators.roll_mths.${creator}.html
done

#
# ------------------- REVIEWERS

cat ${prjTmp}/pr.raw.reviewers.csv | awk -F',' '{print $4}' | sort -u | while read reviewer
do
  	cat ${prjTmp}/pr.raw.reviewers.csv | egrep ",${reviewer}," | egrep -f ${prjTmp}/yr.list | awk -F',' '{print $4","$1","$2","$5}' | sort -r -t',' -k4 >${prjTmp}/pr.reviewers.roll_yr.${reviewer}.csv
    echo "<html>`header`<body><table id="myTable" border=1><thead>
    <tr>
      <th bgcolor=lightblue>Reviewer</th>
      <th bgcolor=lightblue>Repository</th>
      <th bgcolor=lightblue>Pull Request</th>
      <th bgcolor=lightblue>Review Date</th>
    </tr></thead><tbody>" >${prjOut}/pr.reviewers.roll_yr.${reviewer}.html

    cat ${prjTmp}/pr.reviewers.roll_yr.${reviewer}.csv | while read line
  	do
    	echo "<tr>"
    	echo ${line} | tr ',' '\n' | while read col
    	do
      		echo "<td>$col</td>"
    	done
    	echo "</tr>"
  	done >>${prjOut}/pr.reviewers.roll_yr.${reviewer}.html

    echo "</tbody></table></body></html>" >>${prjOut}/pr.reviewers.roll_yr.${reviewer}.html
done

cat ${prjTmp}/pr.raw.reviewers.csv | awk -F',' '{print $4}' | sort -u | while read reviewer
do
  	cat ${prjTmp}/pr.raw.reviewers.csv | egrep ",${reviewer}," | egrep -f ${prjTmp}/mths.list | awk -F',' '{print $4","$1","$2","$5}' | sort -r -t',' -k4 >${prjTmp}/pr.reviewers.roll_mths.${reviewer}.csv
    echo "<html>`header`<body><table id="myTable" border=1><thead>
    <tr>
      <th bgcolor=lightblue>Reviewer</th>
      <th bgcolor=lightblue>Repository</th>
      <th bgcolor=lightblue>Pull Request</th>
      <th bgcolor=lightblue>Review Date</th>
    </tr></thead><tbody>" >${prjOut}/pr.reviewers.roll_mths.${reviewer}.html

    cat ${prjTmp}/pr.reviewers.roll_mths.${reviewer}.csv | while read line
  	do
    	echo "<tr>"
    	echo ${line} | tr ',' '\n' | while read col
    	do
      		echo "<td>$col</td>"
    	done
    	echo "</tr>"
  	done >>${prjOut}/pr.reviewers.roll_mths.${reviewer}.html

    echo "</tbody></table></body></html>" >>${prjOut}/pr.reviewers.roll_mths.${reviewer}.html
done

# create HTML reports
#
echo "
<html>
<h3>OBI - Creators - Rolling Yearly PR report: $(date '+%Y-%m-%d')</h3>
<h4>Note: Report data was generated on $( date -r ${targetDir}/pr.full.csv -u +"%Y-%m-%d %H:%M" )</h4>
<body>
<table id="myTable" border="1">
<thead>
<tr>
<th bgcolor="lightblue">Creator</th>
">${prjOut}/pr.creators.roll_yr.html

cat ${prjTmp}/yr.list | while read yr
do
      echo "<th bgcolor="lightblue">${yr}</th>"
done >>${prjOut}/pr.creators.roll_yr.html

echo "</tr></thead><tbody>"    >>${prjOut}/pr.creators.roll_yr.html

cat ${prjOut}/pr.creators.roll_yr.csv | while read line
do
    creator=$( echo ${line} | awk -F':' '{print $1}' )
    yr_count=$( echo ${line} | awk -F':' '{print $2}' )

    echo "<tr>"
    echo "<td><a href="pr.creators.roll_yr.${creator}.html">${creator}</a></td>"
    echo ${yr_count} | tr ',' '\n' | while read col
    do
        echo "<td>${col}</td>"
    done
    echo "</tr>"
done >>${prjOut}/pr.creators.roll_yr.html

echo "</tbody></table></body></html>">>${prjOut}/pr.creators.roll_yr.html

echo "
<html>
<h3>OBI - Creators - Rolling Monthly PR report: $(date '+%Y-%m-%d')</h3>
<h4>Note: Report data was generated on $( date -r ${targetDir}/pr.full.csv -u +"%Y-%m-%d %H:%M" )</h4>
<body>
<table id="myTable" border="1">
<thead>
<tr>
<th bgcolor="lightblue">Creator</th>
">${prjOut}/pr.creators.roll_mths.html

cat ${prjTmp}/mths.list | while read mth
do
      echo "<th bgcolor="lightblue">${mth}</th>"
done >>${prjOut}/pr.creators.roll_mths.html

echo "</tr></thead><tbody>"    >>${prjOut}/pr.creators.roll_mths.html

cat ${prjOut}/pr.creators.roll_mths.csv | while read line
do
    creator=$( echo ${line} | awk -F':' '{print $1}' )
    mth_count=$( echo ${line} | awk -F':' '{print $2}' )

    echo "<tr>"
    echo "<td><a href="pr.creators.roll_mths.${creator}.html">${creator}</a></td>"
    echo ${mth_count} | tr ',' '\n' | while read col
    do
        echo "<td>${col}</td>"
    done
    echo "</tr>"
done >>${prjOut}/pr.creators.roll_mths.html

echo "</tbody></table></body></html>">>${prjOut}/pr.creators.roll_mths.html


echo "
<html>
<h3>OBI - Reviewers - Rolling Yearly PR report: $(date '+%Y-%m-%d')</h3>
<h4>Note: Report data was generated on $( date -r ${targetDir}/pr.full.csv -u +"%Y-%m-%d %H:%M" )</h4>
<body>
<table id="myTable" border="1">
<thead>
<tr>
<th bgcolor="lightblue">Reviewer</th>
">${prjOut}/pr.reviewers.roll_yr.html

cat ${prjTmp}/yr.list | while read yr
do
      echo "<th bgcolor="lightblue">${yr}</th>"
done >>${prjOut}/pr.reviewers.roll_yr.html

echo "</tr></thead><tbody>"    >>${prjOut}/pr.reviewers.roll_yr.html

cat ${prjOut}/pr.reviewers.roll_yr.csv | while read line
do
    reviewer=$( echo ${line} | awk -F':' '{print $1}' )
    yr_count=$( echo ${line} | awk -F':' '{print $2}' )

    echo "<tr>"
    echo "<td><a href="pr.reviewers.roll_yr.${reviewer}.html">${reviewer}</a></td>"
    echo ${yr_count} | tr ',' '\n' | while read col
    do
        echo "<td>${col}</td>"
    done
    echo "</tr>"
done >>${prjOut}/pr.reviewers.roll_yr.html

echo "</tbody></table></body></html>">>${prjOut}/pr.reviewers.roll_yr.html

echo "
<html>
<h3>OBI - Reviewers - Rolling Monthly PR report: $(date '+%Y-%m-%d')</h3>
<h4>Note: Report data was generated on $( date -r ${targetDir}/pr.full.csv -u +"%Y-%m-%d %H:%M" )</h4>
<body>
<table id="myTable" border="1">
<thead>
<tr>
<th bgcolor="lightblue">Reviewer</th>
">${prjOut}/pr.reviewers.roll_mths.html

cat ${prjTmp}/mths.list | while read mth
do
      echo "<th bgcolor="lightblue">${mth}</th>"
done >>${prjOut}/pr.reviewers.roll_mths.html

echo "</tr></thead><tbody>"    >>${prjOut}/pr.reviewers.roll_mths.html

cat ${prjOut}/pr.reviewers.roll_mths.csv | while read line
do
    reviewer=$( echo ${line} | awk -F':' '{print $1}' )
    mth_count=$( echo ${line} | awk -F':' '{print $2}' )

    echo "<tr>"
    echo "<td><a href="pr.reviewers.roll_mths.${reviewer}.html">${reviewer}</a></td>"
    echo ${mth_count} | tr ',' '\n' | while read col
    do
        echo "<td>${col}</td>"
    done
    echo "</tr>"
done >>${prjOut}/pr.reviewers.roll_mths.html

echo "</tbody></table></body></html>">>${prjOut}/pr.reviewers.roll_mths.html

calc_timetaken
