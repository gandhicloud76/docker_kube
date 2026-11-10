#!/usr/bin/sh

#__author__ = 'anildalli'

## Scan code in all GIT repos for text-match of words like whitelist, blacklist, master, slave (social commitment)
## Repo Owners: OBI,OATH-COMMERCE,CCARE,SCC-devops,GAP,CLIENT,CLIENTDEV,WAS,MCP repos

prjHome=$(pwd)
prjTmp="${prjHome}/tmp"
prjOut="${prjHome}/output"
gitAPI="https://git.vzbuilders.com/api/v3"
currDate=$( date '+%Y-%m-%d' )

mkdir -p ${prjTmp}
mkdir -p ${prjOut}
rm -f ${prjTmp}/*json ${prjTmp}/*csv 	2>/dev/null

## get all repo names for the Org
for repoOwner in $( echo ${REPO_OWNERS_LIST} | sed "s/,/ /g" )
do
	urlRepo="${gitAPI}/orgs/${repoOwner}/repos"
	curl --head -H 'Content-Type: application/json' -H "Authorization: Bearer ${GIT_TOKEN}" "${urlRepo}"	>${prjTmp}/repos.${repoOwner}.head.json 2>/dev/null

	if [ $( cat ${prjTmp}/repos.${repoOwner}.head.json | egrep "Status: 401 Unauthorized" | wc -l | sed "s/ //g" ) -eq 1 ]; then
		echo "ERROR: Curl Status: 401 Unauthorized. Exiting..."
    		exit 1
	fi
	
	reposLastPage=1
	reposLastPage=$( cat ${prjTmp}/repos.${repoOwner}.head.json | egrep "Link:" | egrep "last" | awk -F"/" '{print $NF}' | awk -F">" '{print $1}' | awk -F"=" '{print $NF}' )
	if [ -z ${reposLastPage} ]; then 
		reposLastPage=1;
	fi

	i=1
	while [ ${i} -le ${reposLastPage} ]; do
		curl -H 'Content-Type: application/json' -H "Authorization: Bearer ${GIT_TOKEN}" "${urlRepo}?page=${i}"	2>/dev/null
		i=$( echo ${i} + 1 | bc )
	done | sed "s/\]\[/,/g" 	>${prjTmp}/repos.${repoOwner}.json
	
	repoNamesAll=$( cat ${prjTmp}/repos.${repoOwner}.json | jq '.[].full_name' | sed "s/\"//g" | sort -d | tr '\n' ' ' )
	repoNamesActive=$( cat ${prjTmp}/repos.${repoOwner}.json | jq '.[] | select( "\(.archived)" == "false" ) | "\(.full_name)"' | sed "s/\"//g" | sort -d | tr '\n' ' ' )
	repoNamesAll_array=(${repoNamesAll})
	repoNamesActive_array=(${repoNamesActive})

	echo ""
	echo "${repoOwner} : Repositories [${#repoNamesActive_array[@]} Active] [${#repoNamesAll_array[@]} Total]"
	echo "... Scan Active Repositories for keywords - $( echo ${SOCIAL_COMMITMENT_WORDS} | tr '\n' ',' | sed "s/,$//g" ) ]"
	echo ""
	
	rm -f ${prjTmp}/owner.code_search_kw.csv 2>/dev/null	

	for repoName in ${repoNamesActive_array[@]}; do
		repoNameOnly=$( echo "${repoName}" | awk -F"/" '{print $NF}' )
		rm -f ${prjTmp}/repo.code_search*csv 2>/dev/null
        
		for searchKeyword in $(echo ${SOCIAL_COMMITMENT_WORDS} | sed "s/,/ /g" ); do
			search_qry="search/code?q=${searchKeyword}+repo:${repoName}"

            curl --head -H "Accept: application/vnd.github.mercy-preview+json" -H "Authorization: Bearer ${GIT_TOKEN}" ${gitAPI}/${search_qry}	>${prjTmp}/repo.code_search.head.json 2>/dev/null
            if [ $( cat ${prjTmp}/repo.code_search.head.json | egrep "Status: 401 Unauthorized" | wc -l | sed "s/ //g" ) -eq 1 ]; then
		        echo "ERROR: Curl Status: 401 Unauthorized. Exiting..."
    		    exit 1
	        fi
	
	        codesearchLastPage=1
	        codesearchLastPage=$( cat ${prjTmp}/repo.code_search.head.json | egrep "Link:" | egrep "last" | awk -F"/" '{print $NF}' | awk -F">" '{print $1}' | awk -F"=" '{print $NF}' )
	        if [ -z ${codesearchLastPage} ]; then 
		        codesearchLastPage=1;
	        fi

            i=1
	        while [ ${i} -le ${codesearchLastPage} ]; do
		        curl -H "Accept: application/vnd.github.mercy-preview+json" -H "Authorization: Bearer ${GIT_TOKEN}" "${gitAPI}/${search_qry}&page=${i}" 2>/dev/null
                i=$( echo ${i} + 1 | bc )
	        done | sed "s/\]\[/,/g" 	>${prjTmp}/repo.code_search.json

			if [ $( cat ${prjTmp}/repo.code_search.json 2>/dev/null | egrep "Status: 401 Unauthorized" | wc -l | sed "s/ //g" ) -eq 1 ]; then	
				echo "ERROR: Curl Status: 401 Unauthorized. Exiting..."
    				exit 1
			else
				if [ $( cat ${prjTmp}/repo.code_search.json 2>/dev/null | jq '.total_count' | sort -u ) -ge 1 ]; then
					cat ${prjTmp}/repo.code_search.json 2>/dev/null | jq '.items[].path' | sed "s/$/,${searchKeyword}/g"	>>${prjTmp}/repo.code_search.csv
				fi
			fi
		done
		
		cat ${prjTmp}/repo.code_search.csv 2>/dev/null | sort -u | sed "s/^/${repoOwner},${repoNameOnly},/g" | sed "s/\"//g" >>${prjTmp}/repo.code_search.fmt.csv
		#put searched keywords found in the last column
		cat ${prjTmp}/repo.code_search.fmt.csv | awk -F"," '{print $1","$2","$3}' | sort -u | while read line
		do
			searchKeywordAll=$( cat ${prjTmp}/repo.code_search.fmt.csv | egrep "${line}," | awk -F',' '{print $NF}' | tr '\n' ':' | sed "s/:$//g" )
			echo "${line},${searchKeywordAll}"
		done >${prjTmp}/repo.code_search_kw.csv

        echo -e "       $( cat ${prjTmp}/repo.code_search_kw.csv 2>/dev/null | sort -u | wc -l ) files\t: ${repoName}"
        cat ${prjTmp}/repo.code_search_kw.csv 2>/dev/null | sort -u >>${prjTmp}/owner.code_search_kw.csv
	done
	echo -e "       $( cat ${prjTmp}/owner.code_search_kw.csv | wc -l ) files\t: ${repoOwner}"
	cat ${prjTmp}/owner.code_search_kw.csv | sort -u >>${prjTmp}/all.code_search.csv
	cat ${prjTmp}/owner.code_search_kw.csv | awk -F','  '{print $1","$2}' | sort | uniq -c | awk '{print $2","$1}' | sort -nr -t',' -k3	>>${prjTmp}/report.csv
done
cp -p ${prjTmp}/report.csv ${prjOut}/report.${currDate}.csv

echo "Owner,Active Repository,Filename,Keywords present"	>${prjOut}/all.code_search.${currDate}.csv
cat ${prjTmp}/all.code_search.csv 							>>${prjOut}/all.code_search.${currDate}.csv


echo ""
echo ""
echo "Overall: $( cat ${prjTmp}/all.code_search.csv | wc -l ) files"
echo "       : [output csv] ${prjOut}/all.code_search.${currDate}.csv"
echo ""
echo ""

# Create HTML report
echo "<html>
<h3>Search Keywords in Git Code - ${currDate}</h3>
<body>
<table border="1">
<tr>
<th bgcolor="lightblue">Owner</th>
<th bgcolor="lightblue">Active Repository Name</th>
<th bgcolor="lightblue">Number of files having the keywords</th>
</tr>"	>${prjOut}/report.html

if [ -s ${prjTmp}/report.csv ]; then
	cat ${prjTmp}/report.csv | while read x
	do
		col1=$( echo $x | awk -F"," '{print $1}' )
		col2=$( echo $x | awk -F"," '{print $2}' )
		col3=$( echo $x | awk -F"," '{print $3}' )

		echo "<tr>
		<td>${col1}</td>
		<td>${col2}</td>
		<td>${col3}</td>
		</tr>"	>>${prjOut}/report.html
	done
else
	echo "<tr>all good...</tr>"
fi
echo "</table></body></html>"	>>${prjOut}/report.html
