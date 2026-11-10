#!/usr/bin/sh

set +x

# Initialize variables
#
prjHome=$(pwd)
prjTmp="${prjHome}/tmp"
prjOut="${prjHome}/output"
cts=$( date '+%Y%m%d_%H%M%S' )
num_weeks_for_report=4

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
	cat ${targetDir}/pr.full.csv | sort -u | egrep -v ",ignoreclosed," >${prjTmp}/pr.full.csv
    cp -p ${prjTmp}/pr.full.csv ${prjTmp}/pr.0.csv
    echo "### PR raw data"
    ls -l ${prjTmp}/pr.0.csv
    wc -l ${prjTmp}/pr.0.csv
fi

# exclude Managers, non OBI, whitesource app etc
cp ${prjHome}/automations/git_weekly_report_exclude_list.txt ${prjOut}/git_weekly_report_exclude_list.txt

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

# PR raw data - Cleanup #1 
# Exclude PRs from pipeline to main i.e. PRs with title "Pull request for prod release"
#
cat ${prjTmp}/pr.0.csv | egrep -v "Pull request for prod release" >${prjTmp}/pr.1.csv
echo "### PR raw data (exclude Pull request for prod release)"
ls -l ${prjTmp}/pr.1.csv
wc -l ${prjTmp}/pr.1.csv
calc_timetaken

# ---- List of fields (${prjTmp}/pr.0.csv)
#
# no change

# PR raw data - Cleanup #2A (for top creator)
# Drop fields - gitType, git_pr_url_md5sum,git_pr_title,git_pr_created_at_yyyy,git_pr_created_at_yyyymm
#             - git_pr_last_updated_at_yyyy,git_pr_last_updated_at_yyyymm, git_pr_reviewer, git_pr_review_state
# Organize the fields
cat ${prjTmp}/pr.1.csv | awk -F',' '{print $2","$4","$6","$7","$8}' | sort -u >${prjTmp}/pr.2a.csv
echo "### PR raw data (for top creator)"
ls -l ${prjTmp}/pr.2a.csv
wc -l ${prjTmp}/pr.2a.csv
calc_timetaken
# ---- List of fields (${prjTmp}/pr.2a.csv)
#
#repoName,
#git_pr_url,
#git_pr_state,
#git_pr_creator,
#git_pr_created_at



# PR raw data - Cleanup #2B (for top reviewer)
# Drop fields - gitType, git_pr_url_md5sum,git_pr_title, git_pr_creator,git_pr_created_at_yyyy,git_pr_created_at_yyyymm,
#             - git_pr_last_updated_at_yyyy,git_pr_last_updated_at_yyyymm, git_pr_review_state
# Organize the fields
cat ${prjTmp}/pr.1.csv | egrep -v ",NA$" | awk -F',' '{print $2","$4","$6","$14","$11}' | sort -u >${prjTmp}/pr.2b.csv
echo "### PR raw data (for top reviewer)"
ls -l ${prjTmp}/pr.2b.csv
wc -l ${prjTmp}/pr.2b.csv
calc_timetaken
# ---- List of fields (${prjTmp}/pr.2b.csv)
#
#repoName,
#git_pr_url,
#git_pr_state,
#git_pr_reviewer,
#git_pr_last_updated_at

# PR raw data - Cleanup #2C (for weekly)
# Drop fields - gitType, git_pr_url_md5sum,git_pr_title,git_pr_creator,git_pr_created_at_yyyy,git_pr_created_at_yyyymm,
#             - git_pr_last_updated_at_yyyy,git_pr_last_updated_at_yyyymm, git_pr_reviewer, git_pr_review_state
# Organize the fields
cat ${prjTmp}/pr.1.csv | awk -F',' '{print $2","$4","$8","$11","$6}' >${prjTmp}/pr.2c.csv
echo "### PR raw data (weekly raw, have dupes)"
ls -l ${prjTmp}/pr.2c.csv
wc -l ${prjTmp}/pr.2c.csv
calc_timetaken
# ---- List of fields (${prjTmp}/pr.2c.csv - have dupes)
#
#repoName,
#git_pr_url,
#git_pr_created_at,
#git_pr_last_updated_at, 
#git_pr_state

# PR raw data - Cleanup #3 (weekly raw, remove dupes)
# For Weekly Report to get Total Open PRs, New PRs, Closed PRs
#
cat ${prjTmp}/pr.2c.csv | awk -F',' '{print $1","$2","$3}' | sort -u | while read col_1_2_3
do
    col_4_5=$( cat ${prjTmp}/pr.2c.csv | egrep "${col_1_2_3}," | awk -F',' '{print $4","$5}' | sort -u | tail -1 )
    echo "${col_1_2_3},${col_4_5}"
done >${prjTmp}/pr.3.csv

echo "### PR raw data (prepare raw data for weekly - cleanup dupes)"
ls -l ${prjTmp}/pr.3.csv
wc -l ${prjTmp}/pr.3.csv
# ---- List of fields (${prjTmp}/pr.3.csv)
#
#repoName,
#git_pr_url,
#git_pr_created_at,
#git_pr_last_updated_at,
#git_pr_state

echo "### PR raw data (rename)"
cat ${prjTmp}/pr.2a.csv  | sort -u | sort -t',' -k5	>${prjTmp}/pr.raw.top_creators.csv
cat ${prjTmp}/pr.2b.csv  | sort -u | sort -t',' -k4	>${prjTmp}/pr.raw.top_reviewers.csv
cat ${prjTmp}/pr.3.csv  | sort -u 	>${prjTmp}/pr.raw.rolling_wkly.csv
ls -l ${prjTmp}/pr.raw.*.csv
wc -l ${prjTmp}/pr.raw.*.csv
calc_timetaken

# set current week start date
#
week_start_dt_tmp=$( date --date='last Thursday' '+%Y-%m-%d' )
week_start_dt_tmp_epc=$( date -d "${week_start_dt_tmp} 00:00:00" '+%s' )

week_end_dt=$( date --date='last Wednesday' '+%Y-%m-%d' )
week_end_dt_epc=$( date -d "${week_end_dt} 23:59:59" '+%s' )

if [[ ${week_start_dt_tmp_epc} -gt ${week_end_dt_epc} ]]; then
        week_start_dt=$( date -d "-7 days ${week_start_dt_tmp}" '+%Y-%m-%d' )
        week_start_dt_epc=$( date -d "${week_start_dt} 00:00:00" '+%s' )
else
        week_start_dt=${week_start_dt_tmp}
        week_start_dt_epc=${week_start_dt_tmp_epc}
fi

this_week_start_dt=${week_start_dt}
this_week_start_dt_epc=${week_start_dt_epc}

this_week_end_dt=${week_end_dt}
this_week_end_dt_epc=${week_end_dt_epc}

# prepare weekly schedule for last ${num_weeks_for_report} weeks
#
this_week=0
while [ ${this_week} -lt ${num_weeks_for_report} ]; do
	week_num_days=$( echo "${this_week} * 7"| bc )
	echo "$( date -d "-${week_num_days} days ${week_start_dt}" '+%Y-%m-%d'),$( date -d "-${week_num_days} days ${week_end_dt}" '+%Y-%m-%d')"
	this_week=$( echo $this_week + 1 | bc )
done >${prjTmp}/report_week_schedule.txt
calc_timetaken

###
### top creator and reviewer report
###

cat ${prjTmp}/report_week_schedule.txt | head -1 | while read week_range
do
	start_dt=$( echo ${week_range} | awk -F',' '{print $1}' | awk '{print $1}' | sed "s/-//g" )
	end_dt=$( echo ${week_range} | awk -F',' '{print $2}' | awk '{print $1}' | sed "s/-//g" )

	if [[ -z ${start_dt} ]];then
    	echo "### ERROR: week_start_dt is empty"
    	exit 1
	fi

	if [[ -z ${end_dt} ]];then
    	echo "### ERROR: week_end_dt is empty"
    	exit 1
	fi

    while [ "${start_dt}" -le "${end_dt:-${end_dt}}" ];do
        echo $(date -d"${start_dt}" +%Y-%m-%d)
	    start_dt=$(date -d"${start_dt} +1 day" +%Y%m%d)
    done
done >${prjTmp}/pr.weekly.dates

cat ${prjTmp}/report_week_schedule.txt | head -1 | while read week_range
do
	start_dt=$( echo ${week_range} | awk -F',' '{print $2}' | awk -F'-' '{print $1$2"01"}' )
	end_dt=$( echo ${week_range} | awk -F',' '{print $2}' | awk '{print $1}' | sed "s/-//g" )

	if [[ -z ${start_dt} ]];then
    	echo "### ERROR: week_start_dt is empty"
    	exit 1
	fi

	if [[ -z ${end_dt} ]];then
    	echo "### ERROR: week_end_dt is empty"
    	exit 1
	fi

    while [ "${start_dt}" -le "${end_dt:-${end_dt}}" ];do
        echo $(date -d"${start_dt}" +%Y-%m-%d)
	    start_dt=$(date -d"${start_dt} +1 day" +%Y%m%d)
    done
done >${prjTmp}/pr.mtd.dates

cat ${prjTmp}/report_week_schedule.txt | head -1 | while read week_range
do
	start_dt=$( echo ${week_range} | awk -F',' '{print $2}' | awk -F'-' '{print $1"0101"}' )
	end_dt=$( echo ${week_range} | awk -F',' '{print $2}' | awk '{print $1}' | sed "s/-//g" )

	if [[ -z ${start_dt} ]];then
    	echo "### ERROR: week_start_dt is empty"
    	exit 1
	fi

	if [[ -z ${end_dt} ]];then
    	echo "### ERROR: week_end_dt is empty"
    	exit 1
	fi

    while [ "${start_dt}" -le "${end_dt:-${end_dt}}" ];do
        echo $(date -d"${start_dt}" +%Y-%m-%d)
	    start_dt=$(date -d"${start_dt} +1 day" +%Y%m%d)
    done
done >${prjTmp}/pr.ytd.dates
calc_timetaken

cat ${prjTmp}/pr.raw.top_reviewers.csv | egrep -v -f ${prjOut}/git_weekly_report_exclude_list.txt | egrep -f ${prjTmp}/pr.weekly.dates | awk -F',' '{print $2","$5","$4}'	>${prjTmp}/pr.weekly.reviewers.csv
cat ${prjTmp}/pr.raw.top_creators.csv | egrep -v -f ${prjOut}/git_weekly_report_exclude_list.txt | egrep -f ${prjTmp}/pr.weekly.dates | awk -F',' '{print $2","$5","$4}'	>${prjTmp}/pr.weekly.creators.csv

top_reviewer_weekly_prs=$( cat ${prjTmp}/pr.raw.top_reviewers.csv | egrep -v -f ${prjOut}/git_weekly_report_exclude_list.txt | egrep -f ${prjTmp}/pr.weekly.dates | awk -F',' '{print $4}' | sort | uniq -c | awk '{print $2","$1}' | sort -rn -t',' -k2 | head -1 | awk -F',' '{print $2}' )
top_reviewer_weekly=$( cat ${prjTmp}/pr.raw.top_reviewers.csv | egrep -v -f ${prjOut}/git_weekly_report_exclude_list.txt | egrep -f ${prjTmp}/pr.weekly.dates | awk -F',' '{print $4}' | sort | uniq -c | awk '{print $2","$1}' | sort -rn -t',' -k2 | egrep ",${top_reviewer_weekly_prs}$" | awk -F',' '{print $1}' | tr '\n' ',' | sed "s/,$//g" )

top_reviewer_mtd_prs=$( cat ${prjTmp}/pr.raw.top_reviewers.csv | egrep -v -f ${prjOut}/git_weekly_report_exclude_list.txt | egrep -f ${prjTmp}/pr.mtd.dates | awk -F',' '{print $4}' | sort | uniq -c | awk '{print $2","$1}' | sort -rn -t',' -k2 | head -1 | awk -F',' '{print $2}' )
top_reviewer_mtd=$( cat ${prjTmp}/pr.raw.top_reviewers.csv | egrep -v -f ${prjOut}/git_weekly_report_exclude_list.txt | egrep -f ${prjTmp}/pr.mtd.dates | awk -F',' '{print $4}' | sort | uniq -c | awk '{print $2","$1}' | sort -rn -t',' -k2 | egrep ",${top_reviewer_mtd_prs}$" | awk -F',' '{print $1}' | tr '\n' ',' | sed "s/,$//g" )

top_reviewer_ytd_prs=$( cat ${prjTmp}/pr.raw.top_reviewers.csv | egrep -v -f ${prjOut}/git_weekly_report_exclude_list.txt | egrep -f ${prjTmp}/pr.ytd.dates | awk -F',' '{print $4}' | sort | uniq -c | awk '{print $2","$1}' | sort -rn -t',' -k2 | head -1 | awk -F',' '{print $2}' )
top_reviewer_ytd=$( cat ${prjTmp}/pr.raw.top_reviewers.csv | egrep -v -f ${prjOut}/git_weekly_report_exclude_list.txt | egrep -f ${prjTmp}/pr.ytd.dates | awk -F',' '{print $4}' | sort | uniq -c | awk '{print $2","$1}' | sort -rn -t',' -k2 | egrep ",${top_reviewer_ytd_prs}$" | awk -F',' '{print $1}' | tr '\n' ',' | sed "s/,$//g" )

echo "### top_reviewer_weekly"
echo "$top_reviewer_weekly_prs"
echo "$top_reviewer_weekly"
echo "### top_reviewer_mtd"
echo "$top_reviewer_mtd_prs"
echo "$top_reviewer_mtd"
echo "### top_reviewer_ytd"
echo "$top_reviewer_ytd_prs"
echo "$top_reviewer_ytd"
calc_timetaken

top_creator_weekly_prs=$( cat ${prjTmp}/pr.raw.top_creators.csv | egrep -v -f ${prjOut}/git_weekly_report_exclude_list.txt | egrep -f ${prjTmp}/pr.weekly.dates | awk -F',' '{print $4}' | sort | uniq -c | awk '{print $2","$1}' | sort -rn -t',' -k2 | head -1 | awk -F',' '{print $2}' )
top_creator_weekly=$( cat ${prjTmp}/pr.raw.top_creators.csv | egrep -v -f ${prjOut}/git_weekly_report_exclude_list.txt | egrep -f ${prjTmp}/pr.weekly.dates | awk -F',' '{print $4}' | sort | uniq -c | awk '{print $2","$1}' | sort -rn -t',' -k2 | egrep ",${top_creator_weekly_prs}$" | awk -F',' '{print $1}' | tr '\n' ',' | sed "s/,$//g" )

top_creator_mtd_prs=$( cat ${prjTmp}/pr.raw.top_creators.csv | egrep -v -f ${prjOut}/git_weekly_report_exclude_list.txt | egrep -f ${prjTmp}/pr.mtd.dates | awk -F',' '{print $4}' | sort | uniq -c | awk '{print $2","$1}' | sort -rn -t',' -k2 | head -1 | awk -F',' '{print $2}' )
top_creator_mtd=$( cat ${prjTmp}/pr.raw.top_creators.csv | egrep -v -f ${prjOut}/git_weekly_report_exclude_list.txt | egrep -f ${prjTmp}/pr.mtd.dates | awk -F',' '{print $4}' | sort | uniq -c | awk '{print $2","$1}' | sort -rn -t',' -k2 | egrep ",${top_creator_mtd_prs}$" | awk -F',' '{print $1}' | tr '\n' ',' | sed "s/,$//g" )

top_creator_ytd_prs=$( cat ${prjTmp}/pr.raw.top_creators.csv | egrep -v -f ${prjOut}/git_weekly_report_exclude_list.txt | egrep -f ${prjTmp}/pr.ytd.dates | awk -F',' '{print $4}' | sort | uniq -c | awk '{print $2","$1}' | sort -rn -t',' -k2 | head -1 | awk -F',' '{print $2}' )
top_creator_ytd=$( cat ${prjTmp}/pr.raw.top_creators.csv | egrep -v -f ${prjOut}/git_weekly_report_exclude_list.txt | egrep -f ${prjTmp}/pr.ytd.dates | awk -F',' '{print $4}' | sort | uniq -c | awk '{print $2","$1}' | sort -rn -t',' -k2 | egrep ",${top_creator_ytd_prs}$" | awk -F',' '{print $1}' | tr '\n' ',' | sed "s/,$//g" )

echo "### top_creator_weekly"
echo "$top_creator_weekly_prs"
echo "$top_creator_weekly"
echo "### top_creator_mtd"
echo "$top_creator_mtd_prs"
echo "$top_creator_mtd"
echo "### top_creator_ytd"
echo "$top_creator_ytd_prs"
echo "$top_creator_ytd"
calc_timetaken

echo "### Weekly Schedule for last ${num_weeks_for_report} weeks"
cat ${prjTmp}/report_week_schedule.txt
calc_timetaken

cat ${prjTmp}/report_week_schedule.txt | while read week_range
do
	echo "###"
	echo "### Running for week : $week_start_dt_epc - $week_end_dt_epc"
	echo "###"

	week_start_dt=$( echo ${week_range} | awk -F',' '{print $1}' )
	week_start_dt_epc=$( date -d "${week_start_dt} 00:00:00" '+%s' )

	week_end_dt=$( echo ${week_range} | awk -F',' '{print $2}' )
	week_end_dt_epc=$( date -d "${week_end_dt} 23:59:59" '+%s' )

	week_num=$( cat ${prjTmp}/report_week_schedule.txt | egrep -n "${week_start_dt}," | awk -F':' '{print $1}' )
	week_num_tmp=$( echo "${week_num} -1" | bc )
	exclude_week_num_days=$( echo "${week_num_tmp} * 7"| bc )
	
	n=0
	while [ ${n} -lt ${exclude_week_num_days} ]; do
		mydt=$( date -d "-${n} days ${this_week_end_dt}" '+%Y-%m-%d')
		n=$( echo "$n + 1" | bc )
		echo ${mydt}
	done >${prjTmp}/days_to_exclude.lst

	if [[ -f ${prjTmp}/days_to_exclude.lst ]]; then
		touch ${prjTmp}/days_to_exclude.lst
	fi

    #repoName,
    #git_pr_url,
    #git_pr_created_at,
    #git_pr_last_updated_at,
    #git_pr_state
    
	cat ${prjTmp}/pr.raw.rolling_wkly.csv | egrep ",open$" | awk -F',' '{print $1","$2","$3","$5}' | egrep -v -f ${prjTmp}/days_to_exclude.lst >${prjTmp}/pr.total_open.${week_start_dt}.${week_end_dt}.still.full.csv
	
    rm -f ${prjTmp}/pr.total_open.${week_start_dt}.${week_end_dt}.still.csv 2>/dev/null
	cat ${prjTmp}/pr.total_open.${week_start_dt}.${week_end_dt}.still.full.csv | while read line
	do
		repo_name=$( echo ${line} | awk -F',' '{print $1}' )
        pr_url=$( echo ${line} | awk -F',' '{print $2}' )
        pr_created_dt=$( echo ${line} | awk -F',' '{print $3}' )
        pr_created_dt_epc=$( date -d "${pr_created_dt}" '+%s' )
        pr_state=$( echo ${line} | awk -F',' '{print $4}' )

		if [[ ${pr_created_dt_epc} -le ${this_week_end_dt_epc} ]]; then
			echo "${repo_name},${pr_url},${pr_created_dt},${pr_state}"  >>${prjTmp}/pr.total_open.${week_start_dt}.${week_end_dt}.still.csv
		fi
	done

	if [[ ! -f ${prjTmp}/pr.total_open.${week_start_dt}.${week_end_dt}.still.csv ]]; then
        	touch ${prjTmp}/pr.total_open.${week_start_dt}.${week_end_dt}.still.csv
	fi

	cat ${prjTmp}/pr.raw.rolling_wkly.csv | while read line
	do
        repo_name=$( echo ${line} | awk -F',' '{print $1}' )
	    pr_url=$( echo ${line} | awk -F',' '{print $2}' )
        pr_created_dt=$( echo ${line} | awk -F',' '{print $3}' )
	    pr_created_dt_epc=$( date -d "${pr_created_dt}" '+%s' )
        pr_last_updated_dt=$( echo ${line} | awk -F',' '{print $4}' )
	    if [[ ${pr_last_updated_dt} == "null" ]]; then
	            pr_last_updated_dt="1970-01-01"
        fi
	    pr_last_updated_dt_epc=$( date -d "${pr_last_updated_dt}" '+%s' )
	    pr_state=$( echo ${line} | awk -F',' '{print $5}' )
	
        if [[ ${pr_created_dt_epc} -ge ${week_start_dt_epc} ]]; then
	        if [[ ${pr_created_dt_epc} -le ${week_end_dt_epc} ]]; then
	            echo "${repo_name},${pr_url},${pr_created_dt},${pr_state}"  >>${prjTmp}/pr.last_week.${week_start_dt}.${week_end_dt}.new_prs.csv
	        fi
	    fi
        if [[ ! -f ${prjTmp}/pr.last_week.${week_start_dt}.${week_end_dt}.new_prs.csv ]]; then
        	touch ${prjTmp}/pr.last_week.${week_start_dt}.${week_end_dt}.new_prs.csv
		fi
	
    	if [[ ${pr_state} == "closed" ]]; then
        	if [[ ${pr_last_updated_dt_epc} -ge ${week_start_dt_epc} ]]; then
	        	if [[ ${pr_last_updated_dt_epc} -le ${week_end_dt_epc} ]]; then
	            	echo "${repo_name},${pr_url},${pr_last_updated_dt},${pr_state}"    >>${prjTmp}/pr.last_week.${week_start_dt}.${week_end_dt}.closed_prs.csv
	        	fi
	    	fi

			if [[ ${pr_created_dt_epc} -le ${week_end_dt_epc} ]]; then
				if [[ ${pr_last_updated_dt_epc} -ge ${week_end_dt_epc} ]]; then
					if [[ ${pr_last_updated_dt_epc} -le ${this_week_end_dt_epc} ]]; then
						echo "${repo_name},${pr_url},${pr_created_dt},${pr_state}"  >>${prjTmp}/pr.total_open.${week_start_dt}.${week_end_dt}.closed.csv
					else
						echo "${repo_name},${pr_url},${pr_created_dt},${pr_state}"  >>${prjTmp}/pr.total_open.${week_start_dt}.${week_end_dt}.closed.after.csv
					fi
				fi
            fi
		 fi
	
	done

	cat ${prjTmp}/pr.total_open.${week_start_dt}.${week_end_dt}.still.csv           2>/dev/null >${prjTmp}/pr.total_open.${week_start_dt}.${week_end_dt}.csv
	cat ${prjTmp}/pr.total_open.${week_start_dt}.${week_end_dt}.closed.csv          2>/dev/null >>${prjTmp}/pr.total_open.${week_start_dt}.${week_end_dt}.csv
    cat ${prjTmp}/pr.total_open.${week_start_dt}.${week_end_dt}.closed.after.csv	2>/dev/null >>${prjTmp}/pr.total_open.${week_start_dt}.${week_end_dt}.csv

	if [[ ! -f ${prjTmp}/pr.last_week.${week_start_dt}.${week_end_dt}.closed_prs.csv ]]; then
    	touch ${prjTmp}/pr.last_week.${week_start_dt}.${week_end_dt}.closed_prs.csv
	fi

	total_prs_open=$( cat ${prjTmp}/pr.total_open.${week_start_dt}.${week_end_dt}.csv | wc -l )
	new_prs_last_week=$( cat ${prjTmp}/pr.last_week.${week_start_dt}.${week_end_dt}.new_prs.csv | wc -l )
	closed_prs_last_week=$( cat ${prjTmp}/pr.last_week.${week_start_dt}.${week_end_dt}.closed_prs.csv | wc -l )

	echo "${week_start_dt},${week_end_dt},${total_prs_open},${new_prs_last_week},${closed_prs_last_week}" >>${prjTmp}/pr.weekly.report.csv
 
    #
    # compute time taken
    calc_timetaken
done
cat ${prjTmp}/pr.weekly.report.csv


# Copy to output
#

cp -p ${prjTmp}/pr.weekly.report.csv ${prjOut}/pr.weekly.report.csv
cp -p ${prjTmp}/pr.weekly.creators.csv ${prjOut}/pr.weekly.creators.csv
cp -p ${prjTmp}/pr.weekly.reviewers.csv ${prjOut}/pr.weekly.reviewers.csv
cp -p ${prjTmp}/pr.total_open.* ${prjOut}/
cp -p ${prjTmp}/pr.last_week.* ${prjOut}/



# create HTML report
#
echo "
<html>
<h3>OBI - Weekly Pull Requests Report : ${this_week_end_dt}</h3>
<body>
<table id="myTable" border="1">
<thead>
<tr>
<th bgcolor="lightblue">Metrics</th>
<th bgcolor="lightblue">Start Date</th>
<th bgcolor="lightblue">End Date</th>
<th bgcolor="lightblue">Top Creator</th>
<th bgcolor="lightblue">PRs Created</th>
<th bgcolor="lightblue">Top Reviewer</th>
<th bgcolor="lightblue">PRs Reviewed</th>
</tr>
</thead>
<tbody>
<tr>
<td>Weekly</td>
<td>$( cat ${prjTmp}/pr.weekly.dates | head -1 )</td>
<td>$( cat ${prjTmp}/pr.weekly.dates | tail -1 )</td>
<td>${top_creator_weekly}</td>
<td>${top_creator_weekly_prs}</td>
<td>${top_reviewer_weekly}</td>
<td>${top_reviewer_weekly_prs}</td>
</tr>
<tr>
<td>MTD</td>
<td>$( cat ${prjTmp}/pr.mtd.dates | head -1 )</td>
<td>$( cat ${prjTmp}/pr.mtd.dates | tail -1 )</td>
<td>${top_creator_mtd}</td>
<td>${top_creator_mtd_prs}</td>
<td>${top_reviewer_mtd}</td>
<td>${top_reviewer_mtd_prs}</td>
</tr>
<tr>
<td>YTD</td>
<td>$( cat ${prjTmp}/pr.ytd.dates | head -1 )</td>
<td>$( cat ${prjTmp}/pr.ytd.dates | tail -1 )</td>
<td>${top_creator_ytd}</td>
<td>${top_creator_ytd_prs}</td>
<td>${top_reviewer_ytd}</td>
<td>${top_reviewer_ytd_prs}</td>
</tr>
</tbody>
</table>
<br>
<table id="myTable" border="1">
<thead>
<tr>
<th bgcolor="lightblue">Week Start Date</th>
<th bgcolor="lightblue">Week End Date</th>
<th bgcolor="lightblue">Total PRs Open</th>
<th bgcolor="lightblue">New PRs</th>
<th bgcolor="lightblue">Closed PRs</th>
</tr>
</thead>
<tbody>
">${prjOut}/pr.weekly.report.html

cat ${prjOut}/pr.weekly.report.csv | while read line
do
	week_start_dt=$( echo ${line} | awk -F',' '{print $1}' )
	week_end_dt=$( echo ${line} | awk -F',' '{print $2}' )
	total_prs_open=$( echo ${line} | awk -F',' '{print $3}' )
	new_prs_last_week=$( echo ${line} | awk -F',' '{print $4}' )
	closed_prs_last_week=$( echo ${line} | awk -F',' '{print $5}' )

echo "
<tr>
<td>${week_start_dt}</td>
<td>${week_end_dt}</td>
<td>${total_prs_open}</td>
<td>${new_prs_last_week}</td>
<td>${closed_prs_last_week}</td>
</tr>
">>${prjOut}/pr.weekly.report.html

done

echo "
</tbody>
</table>
<br><br>
<h3>Creators Last Week [ ${this_week_start_dt} - ${this_week_end_dt} ]</h4>
<body>
<table id="myTable" border="1">
<thead>
<tr>
<th bgcolor="lightblue">Pull Request</th>
<th bgcolor="lightblue">Create Date</th>
<th bgcolor="lightblue">Creator</th>
</tr>
</thead>
<tbody>
">>${prjOut}/pr.weekly.report.html

cat ${prjOut}/pr.weekly.creators.csv | while read line
do
        pr_closed_url=$( echo ${line} | awk -F',' '{print $1}' )
        pr_closed_dt=$( echo ${line} | awk -F',' '{print $2}' )
        pr_reviewer=$( echo ${line} | awk -F',' '{print $3}' )

echo "
<tr>
<td>${pr_closed_url}</td>
<td>${pr_closed_dt}</td>
<td>${pr_reviewer}</td>
</tr>
">>${prjOut}/pr.weekly.report.html

done

echo "
</tbody>
</table>
<br>
<table id="myTable" border="1">
<thead>
<tr>
<th bgcolor="lightblue">Creator</th>
<th bgcolor="lightblue">Number of PRs Created</th>
</tr>
</thead>
<tbody>
">>${prjOut}/pr.weekly.report.html

cat ${prjOut}/pr.weekly.creators.csv | awk -F',' '{print $3}' | sort | uniq -c | awk '{print $2","$1}' | sort -rn -t',' -k2 | while read line
do
        pr_creator=$( echo ${line} | awk -F',' '{print $1}' )
        num_prs_created=$( echo ${line} | awk -F',' '{print $2}' )

echo "
<tr>
<td>${pr_creator}</td>
<td>${num_prs_created}</td>
</tr>
">>${prjOut}/pr.weekly.report.html

done

echo "
</tbody>
</table>
<br><br>
<h3>Reviewers Last Week [ ${this_week_start_dt} - ${this_week_end_dt} ]</h4>
<body>
<table id="myTable" border="1">
<thead>
<tr>
<th bgcolor="lightblue">Pull Request</th>
<th bgcolor="lightblue">Last Update Date</th>
<th bgcolor="lightblue">Reviewer</th>
</tr>
</thead>
<tbody>
">>${prjOut}/pr.weekly.report.html

cat ${prjOut}/pr.weekly.reviewers.csv | while read line
do
        pr_closed_url=$( echo ${line} | awk -F',' '{print $1}' )
        pr_closed_dt=$( echo ${line} | awk -F',' '{print $2}' )
        pr_reviewer=$( echo ${line} | awk -F',' '{print $3}' )

echo "
<tr>
<td>${pr_closed_url}</td>
<td>${pr_closed_dt}</td>
<td>${pr_reviewer}</td>
</tr>
">>${prjOut}/pr.weekly.report.html

done

echo "
</tbody>
</table>
<br>
<table id="myTable" border="1">
<thead>
<tr>
<th bgcolor="lightblue">Reviewer</th>
<th bgcolor="lightblue">Number of PRs Reviewed</th>
</tr>
</thead>
<tbody>
">>${prjOut}/pr.weekly.report.html

cat ${prjOut}/pr.weekly.reviewers.csv | awk -F',' '{print $3}' | sort | uniq -c | awk '{print $2","$1}' | sort -rn -t',' -k2 | while read line
do
        pr_reviewer=$( echo ${line} | awk -F',' '{print $1}' )
        num_prs_reviewed=$( echo ${line} | awk -F',' '{print $2}' )

echo "
<tr>
<td>${pr_reviewer}</td>
<td>${num_prs_reviewed}</td>
</tr>
">>${prjOut}/pr.weekly.report.html

done

echo "
</tbody>
</table>
<br><br>
<h4>New PRs Last Week [ ${this_week_start_dt} - ${this_week_end_dt} ]</h4>
<body>
<table id="myTable" border="1">
<thead>
<tr>
<th bgcolor="lightblue">Sl No</th>
<th bgcolor="lightblue">Repository</th>
<th bgcolor="lightblue">Pull Request URL</th>
<th bgcolor="lightblue">Created Date</th>
<th bgcolor="lightblue">Status</th>
</tr>
</thead>
<tbody>
">>${prjOut}/pr.weekly.report.html

new_sl=0
cat ${prjOut}/pr.last_week.${this_week_start_dt}.${this_week_end_dt}.new_prs.csv | while read line
do
	new_sl=$( echo $new_sl + 1 | bc )
        repo_name=$( echo ${line} | awk -F',' '{print $1}' )
        pr_url=$( echo ${line} | awk -F',' '{print $2}' )
        created_dt=$( echo ${line} | awk -F',' '{print $3}' )
        status=$( echo ${line} | awk -F',' '{print $4}' )

echo "
<tr>
<td>${new_sl}</td>
<td>${repo_name}</td>
<td>${pr_url}</td>
<td>${created_dt}</td>
<td>${status}</td>
</tr>
">>${prjOut}/pr.weekly.report.html

done

echo "
</tbody>
</table>
<br><br>
<h4>Closed PRs Last Week [ ${this_week_start_dt} - ${this_week_end_dt} ]</h4>
<body>
<table id="myTable" border="1">
<thead>
<tr>
<th bgcolor="lightblue">Sl No</th>
<th bgcolor="lightblue">Repository</th>
<th bgcolor="lightblue">Pull Request URL</th>
<th bgcolor="lightblue">Closed Date</th>
<th bgcolor="lightblue">Status</th>
</tr>
</thead>
<tbody>
">>${prjOut}/pr.weekly.report.html

closed_sl=0
cat ${prjOut}/pr.last_week.${this_week_start_dt}.${this_week_end_dt}.closed_prs.csv | while read line
do
        closed_sl=$( echo $closed_sl + 1 | bc )
        repo_name=$( echo ${line} | awk -F',' '{print $1}' )
        pr_url=$( echo ${line} | awk -F',' '{print $2}' )
        closed_dt=$( echo ${line} | awk -F',' '{print $3}' )
        status=$( echo ${line} | awk -F',' '{print $4}' )

echo "
<tr>
<td>${closed_sl}</td>
<td>${repo_name}</td>
<td>${pr_url}</td>
<td>${closed_dt}</td>
<td>${status}</td>
</tr>
">>${prjOut}/pr.weekly.report.html

done

echo "
</tbody>
</table>
<br><br>
<h4>Total PRs Open [ ${this_week_start_dt} - ${this_week_end_dt} ]</h4>
<body>
<table id="myTable" border="1">
<thead>
<tr>
<th bgcolor="lightblue">Sl No</th>
<th bgcolor="lightblue">Repository</th>
<th bgcolor="lightblue">Pull Request URL</th>
<th bgcolor="lightblue">Created Date</th>
<th bgcolor="lightblue">Status</th>
</tr>
</thead>
<tbody>
">>${prjOut}/pr.weekly.report.html

total_open_sl=0
cat ${prjOut}/pr.total_open.${this_week_start_dt}.${this_week_end_dt}.csv | while read line
do
        total_open_sl=$( echo $total_open_sl + 1 | bc )
        repo_name=$( echo ${line} | awk -F',' '{print $1}' )
        pr_url=$( echo ${line} | awk -F',' '{print $2}' )
        created_dt=$( echo ${line} | awk -F',' '{print $3}' )
        status=$( echo ${line} | awk -F',' '{print $4}' )

echo "
<tr>
<td>${total_open_sl}</td>
<td>${repo_name}</td>
<td>${pr_url}</td>
<td>${created_dt}</td>
<td>${status}</td>
</tr>
">>${prjOut}/pr.weekly.report.html

done

echo "
</tbody>
</table>
<br><h5>Note: Exclude automated PRs for overall reporting. Top creator and reviewer report also excludes managers, non OBI members, and whitesource-app.</h5><br>
</body>
</html>">>${prjOut}/pr.weekly.report.html

#
# compute time taken
calc_timetaken

