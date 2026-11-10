echo "### INFO: Destroy sshca-creds for ec2-user"
sshca-creds -u ec2-user destroy

echo "### INFO: Load sshca-creds for ec2-user"
sshca-creds -u ec2-user load -z https://zts.athenz.ouroath.com:4443/zts/v1/ -a 3

echo "### INFO: List sshca-creds for ec2-user"
sshca-creds -u ec2-user  ls --format "{{.Socket}}"

echo "### INFO: Export SSH_AUTH_SOCK"
export SSH_AUTH_SOCK=$( sshca-creds -u ec2-user  ls --format "{{.Socket}}" ) 
