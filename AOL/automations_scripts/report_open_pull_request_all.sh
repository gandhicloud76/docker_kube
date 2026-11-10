#!/usr/bin/sh

## __author__ = 'Anil Reddy Dalli'
##
## Get list of open PRs from Github
## 
## Scan through all active repositories of Github to generate report on open Pull Requests. 
## [+] Active repositories are those where archived state is false 
## [+] Exclude Pull/Merge requests which are created in last 1 week

prjHome=$(pwd)
prjTmp="${prjHome}/tmp"
prjOut="${prjHome}/output"

rm -rf ${prjTmp} ${prjOut} 2>/dev/null
mkdir -p ${prjTmp} ${prjOut}

pr_cutoff_date_epc=$( date -d "-7 days" '+%s' )

github_base_api="https://git.vzbuilders.com/api/v3"

repoOwnersList="OBI,OATH-COMMERCE,CCARE,SCC-devops,GAP,CLIENT,CLIENTDEV,WAS,MCP,MSCDI"
#repoOwnersList="GAP"
excludeDisabledRepos="GAP/cloudtrail-alerts"

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

# Below variables are stored as secret text(s) and are used in the Jenkins Build Environment
#github_api_token=""

# get Github active repositories for each Org (i.e. archived=false)
#
for repoOwner in $( echo ${repoOwnersList} | sed "s/,/ /g" )
do
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
    done | sed "s/\]\[/,/g" 	>${prjTmp}/${repoOwner}.repos.json
	
    repoNamesAll_array=($( cat ${prjTmp}/${repoOwner}.repos.json | jq '.[].full_name' | sed "s/\"//g" | sort -d | tr '\n' ' ' ))
    repoNamesActive_array=($( cat ${prjTmp}/${repoOwner}.repos.json | jq '.[] | select( "\(.archived)" == "false" ) | "\(.full_name)"' | sed "s/\"//g" | egrep -v "${excludeDisabledRepos}" | sort -d | tr '\n' ' ' ))
	
    echo "####################################################"
    echo "###  ${repoOwner} : active repos ${#repoNamesActive_array[@]} (total ${#repoNamesAll_array[@]})"
    echo "###  -----------------------------------------------"
    
    # loop through project repositories and scan for open PRs
    #
    for repoNameFull in ${repoNamesActive_array[@]}; do
        repoName=$( echo ${repoNameFull} | awk -F'/' '{print $2}' )
	    github_api_pulls="${github_base_api}/repos/${repoOwner}/${repoName}/pulls?state=open&per_page=100"

	    curl --head -H 'Content-Type: application/json' -H "Authorization: Bearer ${github_api_token}" "${github_api_pulls}"	2>/dev/null >${prjTmp}/pulls.head.json
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
		    curl -H 'Content-Type: application/json' -H "Authorization: Bearer ${github_api_token}" "${github_api_pulls}?page=${i}"	2>/dev/null
		    i=$( echo ${i} + 1 | bc )
	    done | sed "s/\]\[/,/g" 	>${prjTmp}/${repoOwner}.${repoName}.pulls.json
        
        for key in $( cat ${prjTmp}/${repoOwner}.${repoName}.pulls.json | jq '. | keys | .[]' ); do
            cat ${prjTmp}/${repoOwner}.${repoName}.pulls.json | jq .[${key}]	>${prjTmp}/pulls.key.json

    	    git_pull_url=$( cat ${prjTmp}/pulls.key.json | jq '.html_url' | sed "s/\"//g" )
    	    git_pull_user=$( cat ${prjTmp}/pulls.key.json | jq '.user.login' | sed "s/\"//g" )
            git_pull_created_at=$( cat ${prjTmp}/pulls.key.json | jq '.created_at' | sed "s/\"//g" )
    	    git_pull_updated_at=$( cat ${prjTmp}/pulls.key.json | jq '.updated_at' | sed "s/\"//g" )
    	    git_pull_title=$( cat ${prjTmp}/pulls.key.json | jq '.title' | sed "s/\"//g" | sed "s/,//g" | sed "s/\\\//g" )
        
            echo "${repoOwner},${repoName},${git_pull_url},${git_pull_user},${git_pull_created_at},${git_pull_updated_at},${git_pull_title}"	>>${prjTmp}/pulls.csv
        done

        num_prs_maxkey=$( cat ${prjTmp}/${repoOwner}.${repoName}.pulls.json | jq '. | keys | .[]' | tail -1 )
        if [[ -z ${num_prs_maxkey} ]]; then
            num_prs=0
        else
            num_prs=$( echo ${num_prs_maxkey} + 1 | bc )
        fi 
        echo "###  ${repoOwner}/${repoName} : ${num_prs}"
    done
    sleep 20
done

cp -p ${prjTmp}/pulls.csv ${prjOut}/pulls.csv
cat ${prjTmp}/pulls.csv | sort -r -t',' -k4     >${prjOut}/open_pull_requests.ALL.csv

# create HTML report
#
echo "
<html>
`header`
<h3> - List of Open Pull Requests : $(date '+%Y-%m-%d')</h3>
<h4>Considerations: [*] Only Active repositories (archived state is false) [*] Exclude Pull/Merge Requests which are created in last 1 week</h4>
<body>
<table id="myTable" border="1">
<thead>
<tr>
<th bgcolor="lightblue">Owner</th>
<th bgcolor="lightblue">Repository</th>
<th bgcolor="lightblue">Url</th>
<th bgcolor="lightblue">User</th>
<th bgcolor="lightblue">Created</th>
<th bgcolor="lightblue">Updated</th>
<th bgcolor="lightblue">Title</th>
</tr>
</thead>
<tbody>
">${prjOut}/open_pull_requests.ALL.html

cat ${prjOut}/open_pull_requests.ALL.csv | while read line
do
repo_owner=$( echo ${line} | awk -F',' '{print $1}' )
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
<td>${repo_owner}</td>
<td>${repo_name}</td>
<td><a href="${pull_url}">${pull_url}</a></td>
<td>${pull_user}</td>
<td>${pull_created_at_fmt}</td>
<td>${pull_updated_at_fmt}</td>
<td>${pull_title}</td>
</tr>
">>${prjOut}/open_pull_requests.ALL.html
fi
done

echo "
</tbody>
</table>
</body>
</html>">>${prjOut}/open_pull_requests.ALL.html
