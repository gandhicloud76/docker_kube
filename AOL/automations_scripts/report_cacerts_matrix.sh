#!/usr/bin/bash

workDir="./cacerts_matrix_work"
rm -rf ${workDir} 2>/dev/null
mkdir -p ${workDir}

cacerts_arr=("java8" "java17" "webapp-base" "webapp-base-secure" "springboot-base" "springboot-base-secure" "webapp-base-java17" "webapp-base-secure-java17" "springboot-base-java17" "springboot-base-secure-java17")
#cacerts_arr=("java17" "springboot-base-secure-java17")
echo "##### Reading ${#cacerts_arr[@]} cacerts"

#
# generate cacerts input files for cacerts matrix
for cacerts_name in "${cacerts_arr[@]}"; do
    #
    # get source of the cacerts
    echo "##### Get info for ${cacerts_name} cacerts"
    if [[ ${cacerts_name} == "athenz-yahoo" ]]; then
        cat /opt/yahoo/share/ssl/certs/*certificate_bundle.jks 2>/dev/null >${workDir}/${cacerts_name}.jks
        cacerts_src="${workDir}/${cacerts_name}.jks"
    elif [[ ${cacerts_name} == "java8" ]]; then
        cacerts_src=$( find / -name cacerts 2>/dev/null | egrep jvm | egrep "java-1.8" | head -1 )
    elif [[ ${cacerts_name} == "java17" ]]; then
        cacerts_src=$( find / -name cacerts 2>/dev/null | egrep jvm | egrep "java-17" | head -1 )  
    else
        cacerts_src="${cacerts_name}/cacerts"
    fi

    #
    # copy cacerts to local work directory
    if [[ -f ${cacerts_src} ]]; then
        cp -p ${cacerts_src} ${workDir}/${cacerts_name}.cacerts
        ls -l ${workDir}/${cacerts_name}.cacerts
    else
        echo "ERROR: ${cacerts_src} file not found"
        exit 1
    fi

    #
    # get cacerts file having list of trustedCertEntry
    keytool -list -keystore ${workDir}/${cacerts_name}.cacerts -storepass changeit >${workDir}/${cacerts_name}.cacerts.list
    ls -l ${workDir}/${cacerts_name}.cacerts.list

    #
    # get unique trustedCertEntry IDs for each cacert
    cat ${workDir}/${cacerts_name}.cacerts.list	| egrep "trustedCertEntry" | awk -F',' '{print $1}'	| sort -u >${workDir}/${cacerts_name}.cacerts.uniq_ids
    ls -l ${workDir}/${cacerts_name}.cacerts.uniq_ids

    #
    # get Certificate fingerprint sha256sum for respective trustedCertEntry ID
    cat ${workDir}/${cacerts_name}.cacerts.uniq_ids | while read tce_id; do
		
    	tce_id_fmt=$( echo "${tce_id}" | sed 's/(/\\(/g' | sed 's/)/\\)/g' )
		tce_value=$( egrep -A1 "${tce_id_fmt}, " ${workDir}/${cacerts_name}.cacerts.list | egrep "Certificate fingerprint" | awk -F"): " '{print $2}' | head -1 )
		if [[ -z ${tce_value} ]]; then
			tce_value_sha256sum=NA
		else
			tce_value_sha256sum=$( echo -n "${tce_value}" | sha256sum | awk '{print $1}' )
		fi
    	echo "${tce_value_sha256sum},${tce_value}" >>${workDir}/cacerts.fingerprint_sha256sum_lkp
		echo "${tce_id},${tce_value_sha256sum}"
	done >${workDir}/${cacerts_name}.cacerts.info
    ls -l ${workDir}/${cacerts_name}.cacerts.info
done

#
# define input files for cacerts matrix output
echo "##### Create cacerts matrix report"
temp_files=()

#
# extract all unique IDs from all files
for cacerts_name in "${cacerts_arr[@]}"; do
    awk -F, '{print $1}' ${workDir}/${cacerts_name}.cacerts.info
done | sort -u > ${workDir}/cacerts.unique_ids
ls -l ${workDir}/cacerts.unique_ids

#
# process each file to create temporary files
for cacerts_name in "${cacerts_arr[@]}"; do
    # 
    # create a temporary file for the current file's values
    temp_file=$(mktemp)
    temp_files+=("${temp_file}")

    # 
    # initialize the temporary file with all IDs and empty values
    cat ${workDir}/cacerts.unique_ids | awk '{print $0 ",NULL"}'  > "${temp_file}"

    # 
    # update the temporary file with actual values from the current file
    awk -F, 'NR==FNR{a[$1]=$2; next} {if($1 in a) {$2=a[$1]}; print}' ${workDir}/${cacerts_name}.cacerts.info "${temp_file}" >${workDir}/${cacerts_name}.cacerts.info.temp
    mv ${workDir}/${cacerts_name}.cacerts.info.temp "${temp_file}"
done

# 
# merge all temporary files into the final merged file
paste -d, ${workDir}/cacerts.unique_ids "${temp_files[@]}" | sed "s/,NULL/ NULL/g"	>${workDir}/cacerts.merged
ls -l ${workDir}/cacerts.merged

#
# create matrix file
cat ${workDir}/cacerts.merged | awk '{for(i=1; i<=NF; i++) {split($i, a, ","); if (i == 1) {printf "%s", a[2]} else {printf ",%s", a[1]}}; print ""}' >${workDir}/cacerts.matrix.csv
ls -l ${workDir}/cacerts.matrix.csv

echo "<html>
<h3>CACERTS Matrix</h3>
<head>
<title>CACERTS-Matrix</title>
</head>
<body>
<table border="1">
<tr>
<th bgcolor="lightblue">Trusted Certificate Entry ID</th>" >${workDir}/cacerts.matrix.html

for cacerts_name in "${cacerts_arr[@]}"; do
    echo "<th bgcolor="lightblue">${cacerts_name}</th>" 
done >>${workDir}/cacerts.matrix.html
echo "</tr>" >>${workDir}/cacerts.matrix.html

#
# read the input file and generate an html report
while IFS=, read -r line; do
  id=$(echo ${line} | cut -d, -f1)
  values=$(echo ${line} | cut -d, -f2-)

  echo "<tr><td>${id}</td>" >>${workDir}/cacerts.matrix.html
  
  IFS=',' read -r -a valueArray <<< "$values"
  for value in "${valueArray[@]}"; do
    if [ "${value}" == "NULL" ]; then
      echo "<td><font color=red>X</td>" >>${workDir}/cacerts.matrix.html
    else
      actual_value=$( cat ${workDir}/cacerts.fingerprint_sha256sum_lkp | egrep "${value}," | awk -F',' '{print $2}' | sort -u )
      echo "<td><font color=green>${actual_value}</td>" >>${workDir}/cacerts.matrix.html
    fi
  done
  
  echo "</tr>" >>${workDir}/cacerts.matrix.html
done <${workDir}/cacerts.matrix.csv


# End HTML
echo "</table></body></html>" >> ${workDir}/cacerts.matrix.html

ls -l ${workDir}/cacerts.matrix.html
