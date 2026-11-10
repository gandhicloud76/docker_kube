#
# run awsfed2 to select the aws account
# export AWS_PROFILE=federate
# python list_available_ips_per_subnet.py <your-vpc-id>
#
#
#

import boto3
import ipaddress
import argparse

def get_vpc_cidr(vpc_id):
    ec2 = boto3.client('ec2')
    response = ec2.describe_vpcs(VpcIds=[vpc_id])
    return response['Vpcs'][0]['CidrBlock']

def list_subnets(vpc_id):
    ec2 = boto3.client('ec2')
    response = ec2.describe_subnets(Filters=[{'Name': 'vpc-id', 'Values': [vpc_id]}])
    subnets = response['Subnets']
    return subnets

def list_allocated_ips(vpc_id):
    ec2 = boto3.client('ec2')

    # Get IPs from instances
    instances = ec2.describe_instances(Filters=[{'Name': 'vpc-id', 'Values': [vpc_id]}])
    instance_ips = [instance['PrivateIpAddress'] for reservation in instances['Reservations'] for instance in reservation['Instances']]

    # Get IPs from network interfaces
    interfaces = ec2.describe_network_interfaces(Filters=[{'Name': 'vpc-id', 'Values': [vpc_id]}])
    interface_ips = [interface['PrivateIpAddress'] for interface in interfaces['NetworkInterfaces']]

    # Get IPs from NAT gateways
    nat_gateways = ec2.describe_nat_gateways(Filter=[{'Name': 'vpc-id', 'Values': [vpc_id]}])
    nat_ips = [nat['NatGatewayAddresses'][0]['PrivateIp'] for nat in nat_gateways['NatGateways']]

    allocated_ips = set(instance_ips + interface_ips + nat_ips)
    return allocated_ips

def get_available_ips(subnet_cidr, allocated_ips):
    network = ipaddress.ip_network(subnet_cidr)
    available_ips = [str(ip) for ip in network.hosts() if str(ip) not in allocated_ips]
    return available_ips

def main(vpc_id):
    vpc_cidr = get_vpc_cidr(vpc_id)
    subnets = list_subnets(vpc_id)
    allocated_ips = list_allocated_ips(vpc_id)

    print(f"VPC CIDR: {vpc_cidr}")
    print("Subnets and their CIDR blocks with available IP counts:")
    for subnet in subnets:
        subnet_id = subnet['SubnetId']
        subnet_cidr = subnet['CidrBlock']
        available_ips = get_available_ips(subnet_cidr, allocated_ips)
        available_ip_count = len(available_ips)
        print(f"Subnet ID: {subnet_id}, CIDR: {subnet_cidr}, Available IPs: {available_ip_count}")
        print("Available IP addresses:")
        for ip in available_ips:
            print(ip)
        print()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Script to list available IP addresses in a VPC's subnets")
    parser.add_argument("vpc_id", help="The ID of the VPC")
    args = parser.parse_args()

    main(args.vpc_id)

