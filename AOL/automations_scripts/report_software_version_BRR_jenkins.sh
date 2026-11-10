#!/usr/bin/sh 
java_version=$( java -version 2>&1 | head -1 | cut -d'"' -f2 )
aws_version=$( aws --version | cut -d' ' -f1 | cut -d'/' -f2 )
python_version=$( python --version 2>&1 | awk -F' ' '{print $2}')
docker_version=$( docker -v | cut -d' ' -f3 | sed "s/,//g" )
terraform_version=$( terraform -v 2>&1 | head -1 | cut -d'v' -f2 )
newrelic_version=$( newrelic-infra --version | awk -F':' '{print $2}' | sed "s/ //g" | awk -F',' '{print $1}' )
jq_version=$( jq --version | cut -d'-' -f2 )
calypso_version=$( calypso -yversion  | cut -d' ' -f2 | cut -d',' -f1 )


echo "<table border='1'>
<tr>
  <th>Software</th>
  <th>Command</th>
  <th>Version</th>
</tr>
<tr>
  <td>java</td>
  <td>java -version</td>
  <td>${java_version}</td>
</tr>
<tr>
  <td>awscli</td>
  <td>aws --version</td>
  <td>${aws_version}</td>
</tr>
<tr>
    <td>python</td>
    <td>python -V</td>
    <td>${python_version}</td>
  </tr>
<tr>
  <td>docker</td>
  <td>docker -v</td>
  <td>${docker_version}</td>
</tr>
<tr>
  <td>terraform</td>
  <td>terraform -v</td>
  <td>${terraform_version}</td>
</tr>
<tr>
  <td>newrelic</td>
  <td>newrelic-infra --version</td>
  <td>${newrelic_version}</td>
</tr>
<tr>
  <td>jq</td>
  <td>jq --version</td>
  <td>${jq_version}</td>
</tr>
<tr>
  <td>calypso</td>
  <td>calypso -yversion</td>
  <td>${calypso_version}</td>
</tr>
</table>" > output.html
