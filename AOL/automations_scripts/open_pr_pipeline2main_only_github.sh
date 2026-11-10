#!/usr/bin/sh

## __author__ = 'Anil Reddy Dalli'
##
## Open PR reports older than 10 days for projects in Github ONLY that are also present in Gitlab
## 

prjHome=$(pwd)
prjTmp="${prjHome}/tmp"
prjOut="${prjHome}/output"

rm -rf ${prjTmp} ${prjOut} 2>/dev/null
mkdir -p ${prjTmp} ${prjOut}

pr_cutoff_date_epc=$( date -d "-7 days" '+%s' )

github_base_api="https://git.ouryahoo.com/api/v3"
## gitlab_base_api="https://scm.obieng.com/api/v4"

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

## # Below variables are staored as secret text(s) and are used in the Jenkins Build Environment
## #github_api_token=""
## #gitlab_api_token=""
## 
## # get Gitlab active repositories (i.e. archived=false)
## #
## gitlab_api_repos="${gitlab_base_api}/projects?private_token=${gitlab_api_token}&per_page=100"
## 
## curl --head -H 'Content-Type: application/json' "${gitlab_api_repos}"	2>/dev/null >${prjTmp}/repos.head.json
## if [ $( cat ${prjTmp}/repos.head.json | egrep "HTTP/1.1 200 OK" | wc -l | sed "s/ //g" ) -ne 1 ]; then
## 	echo "ERROR: Gitlab Curl Failed (gitlab_api_repos). Exit."
##     exit 1
## fi
## 
## reposLastPage=$( cat ${prjTmp}/repos.head.json | egrep "X-Total-Pages:" | awk -F":" '{print $NF}' | sed "s/ //g" | head -1 )
## reposLastPage=${reposLastPage//[$'\t\r\n ']}
## if [ -z ${reposLastPage} ]; then
##     reposLastPage=1
## fi
## i=1
## while [ ${i} -le ${reposLastPage} ]; do
## 	curl -H 'Content-Type: application/json' "${gitlab_api_repos}&page=${i}"	2>/dev/null
## 	i=$( echo ${i} + 1 | bc )
## done | sed "s/\]\[/,/g" 	>${prjTmp}/repos.json
## 
## repoNamesAll_array=($( cat ${prjTmp}/repos.json | jq '.[].path_with_namespace' | sed "s/\"//g" | sed "s/ //g" | egrep -v "AlexanderLepekhin|PuneetSharma" | sort -d | tr '\n' ' ' ))
## repoNamesActive_array=($( cat ${prjTmp}/repos.json | jq '.[] | select( "\(.archived)" == "false" ) | "\(.path_with_namespace)#\(.id)"' | sed "s/\"//g" | sed "s/ //g" | egrep -v "AlexanderLepekhin|PuneetSharma" | sort -d | tr '\n' ' ' ))    
## 
## for repoFullNameId in ${repoNamesActive_array[@]}; do
##     repoNameId=$( echo "${repoFullNameId}" | awk -F'/' '{print $NF}' )
##     repoNamesActive_array_gl+=(${repoNameId})
## done
## echo "#########################################################################"
## echo "### Gitlab : active repos ${#repoNamesActive_array[@]} (total ${#repoNamesAll_array[@]})"

# get Github active repositories (i.e. archived=false)
#
repoOwner=OBI
github_api_repos="${github_base_api}/orgs/${repoOwner}/repos"

curl --head -H 'Content-Type: application/json' -H "Authorization: Bearer ${github_api_token}" "${github_api_repos}"	2>/dev/null >${prjTmp}/repos.head.json
if [ $( cat ${prjTmp}/repos.head.json | egrep "HTTP/1.1 200 OK" | wc -l | sed "s/ //g" ) -ne 1 ]; then
	echo "ERROR: Github Curl Failed (github_api_repos). Exit."
    exit 1
fi
	
reposLastPage=$( cat ${prjTmp}/repos.head.json | egrep "Link:" | egrep "last" | awk -F"/" '{print $NF}' | awk -F">" '{print $1}' | awk -F"=" '{print $NF}' )
if [ -z ${reposLastPage} ]; then
    reposLastPage=1
fi
i=1
while [ ${i} -le ${reposLastPage} ]; do
	curl -H 'Content-Type: application/json' -H "Authorization: Bearer ${github_api_token}" "${github_api_repos}?page=${i}"	2>/dev/null
	i=$( echo ${i} + 1 | bc )
done | sed "s/\]\[/,/g" 	>${prjTmp}/repos.json
	
repoNamesAll_array=($( cat ${prjTmp}/repos.json | jq '.[].full_name' | sed "s/\"//g" | sort -d | tr '\n' ' ' ))
repoNamesActive_array=($( cat ${prjTmp}/repos.json | jq '.[] | select( "\(.archived)" == "false" ) | "\(.full_name)"' | sed "s/\"//g" | sort -d | tr '\n' ' ' ))
	
for repoFullName in ${repoNamesActive_array[@]}; do
    repoName=$( echo "${repoFullName}" | awk -F"/" '{print $NF}' )
    repoNamesActive_array_gh+=(${repoName})
done
echo "### Github : active repos ${#repoNamesActive_array[@]} (total ${#repoNamesAll_array[@]})"

## # consider repositories present in Gitlab that are present Github repository list
## #
## rm -f ${prjTmp}/repos.gh_gl.lst ${prjTmp}/repos.gh_no_gl.lst
## for repoNameId_gl in ${repoNamesActive_array_gl[@]}; do
##     repoName_gl=$( echo "${repoNameId_gl}" | awk -F"/" '{print $NF}' | awk -F'#' '{print $1}')
##     for i in "${!repoNamesActive_array_gh[@]}"; do
##         if [[ ${repoNamesActive_array_gh[i]} == $repoName_gl ]]; then
##             echo ${repoNamesActive_array_gh[i]} >>${prjTmp}/repos.gh_gl.lst
##         fi
##     done
## done
## repoNamesActive_array_gh_gl=($( cat ${prjTmp}/repos.gh_gl.lst | sort -u ))
## echo "### Github :  ${#repoNamesActive_array_gh_gl[@]} (mirrored from Gitlab, now need to be scanned for open PRs"
## echo "#########################################################################"

# loop through project repositories and scan for open PRs
#
#for repoName in ${repoNamesActive_array_gh_gl[@]}; do
for repoName in ${repoNamesActive_array_gh[@]}; do
   

    base_api="https://git.ouryahoo.com/api/v3"
    api_token=${github_api_token}
    
		github_api_pulls="${base_api}/repos/${repoOwner}/${repoName}/pulls?state=open&per_page=100"

		curl --head -H 'Content-Type: application/json' -H "Authorization: Bearer ${api_token}" "${github_api_pulls}"	2>/dev/null >${prjTmp}/pulls.head.json
		if [ $( cat ${prjTmp}/pulls.head.json | egrep "HTTP/1.1 200 OK" | wc -l | sed "s/ //g" ) -ne 1 ]; then
			echo "ERROR: Github Curl Failed (github_api_pulls). Exit."
    	exit 1
		fi
	
		reposLastPage=$( cat ${prjTmp}/pulls.head.json| egrep "Link:" | egrep "last" | awk -F"/" '{print $NF}' | awk -F">" '{print $1}' | awk -F"=" '{print $NF}' )
		if [ -z ${reposLastPage} ]; then
    		reposLastPage=1
		fi
		i=1
		while [ ${i} -le ${reposLastPage} ]; do
			curl -H 'Content-Type: application/json' -H "Authorization: Bearer ${api_token}" "${github_api_pulls}&page=${i}"	2>/dev/null
			i=$( echo ${i} + 1 | bc )
		done | sed "s/\]\[/,/g" 	>${prjTmp}/pulls.${repoName}.json
        
    for key in $( cat ${prjTmp}/pulls.${repoName}.json | jq '. | keys | .[]' ); do
        cat ${prjTmp}/pulls.${repoName}.json | jq .[${key}]	>${prjTmp}/pulls.key.json

        git_pull_url=$( cat ${prjTmp}/pulls.key.json | jq '.html_url' | sed "s/\"//g" )
        git_pull_user=$( cat ${prjTmp}/pulls.key.json | jq '.user.login' | sed "s/\"//g" )
        git_pull_created_at=$( cat ${prjTmp}/pulls.key.json | jq '.created_at' | sed "s/\"//g" | sed "s/T/ /g" | sed "s/Z//g" )
        git_pull_updated_at=$( cat ${prjTmp}/pulls.key.json | jq '.updated_at' | sed "s/\"//g" | sed "s/T/ /g" | sed "s/Z//g" )
        git_pull_title=$( cat ${prjTmp}/pulls.key.json | jq '.title' | sed "s/\"//g" | sed "s/,//g" | sed "s/\\\//g" )
        git_pull_draft=$( cat ${prjTmp}/pulls.key.json | jq '.draft' | sed "s/\"//g" )
        
        if [[ $( echo ${git_pull_title} | egrep -i "^WIP" | wc -l ) -eq 0 ]]; then
            if [[ ${git_pull_draft} == "false" ]]; then
                echo "${repoOwner},${repoName},${git_pull_url},${git_pull_user},${git_pull_created_at},${git_pull_updated_at},${git_pull_title}"	>>${prjTmp}/pulls.csv
            fi
        fi
    done

    num_prs_maxkey=$( cat ${prjTmp}/pulls.${repoName}.json | jq '. | keys | .[]' | tail -1 )
    if [[ -z ${num_prs_maxkey} ]]; then
        num_prs=0
    else
        num_prs=$( echo ${num_prs_maxkey} + 1 | bc )
    fi 
    echo "${base_api} : ${repoName} : ${num_prs}"

done

mv ${prjTmp}/pulls.csv ${prjTmp}/pulls.${repoOwner}.csv

cat ${prjTmp}/pulls.${repoOwner}.csv | sort -r -t',' -k4  >${prjOut}/open_pr_pipeline2main.csv

# create HTML report
#
echo "
<html>
`header`
<h3>OBI - List of Open Pull Requests (pipeline to main) : $(date '+%Y-%m-%d')</h3>
<body>
<table id="myTable" border="1">
<thead>
<tr>
<th bgcolor="lightblue">Sl.No</th>
<th bgcolor="lightblue">RepoOrg</th>
<th bgcolor="lightblue">Repository</th>
<th bgcolor="lightblue">Url</th>
<th bgcolor="lightblue">User</th>
<th bgcolor="lightblue">Created</th>
<th bgcolor="lightblue">Updated</th>
<th bgcolor="lightblue">Title</th>
</tr>
</thead>
<tbody>
">${prjOut}/open_pr_pipeline2main.html

sl_num=1
cat ${prjOut}/open_pr_pipeline2main.csv | while read line
do
repo_org=$( echo ${line} | awk -F',' '{print $1}' )
repo_name=$( echo ${line} | awk -F',' '{print $2}' )
pull_url=$( echo ${line} | awk -F',' '{print $3}' )
pull_user=$( echo ${line} | awk -F',' '{print $4}' )
pull_created_at=$( echo ${line} | awk -F',' '{print $5}' )
pull_created_at_epc=$( date -d "${pull_created_at}" '+%s' )
pull_created_at_fmt=$( date -d "${pull_created_at}" '+%Y-%m-%d %H:%M' )
pull_updated_at=$( echo ${line} | awk -F',' '{print $6}' )
pull_updated_at_fmt=$( date -d "${pull_updated_at}" '+%Y-%m-%d %H:%M' )
pull_title=$( echo ${line} | awk -F',' '{print $7}' )

if [[ ${pull_created_at_epc} -le ${pr_cutoff_date_epc} ]]; then
echo "
<tr>
<td>${sl_num}</td>
<td>${repo_org}</td>
<td>${repo_name}</td>
<td><a href="${pull_url}">${pull_url}</a></td>
<td>${pull_user}</td>
<td>${pull_created_at_fmt}</td>
<td>${pull_updated_at_fmt}</td>
<td>${pull_title}</td>
</tr>
">>${prjOut}/open_pr_pipeline2main.html
sl_num=$( echo ${sl_num} + 1 | bc )
fi
done

echo "
</tbody>
</table>
</body>
</html>">>${prjOut}/open_pr_pipeline2main.html
