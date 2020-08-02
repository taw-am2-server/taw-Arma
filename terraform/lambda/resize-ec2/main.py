import boto3
import json
import logging
from os import environ

logger = logging.getLogger()
logger.setLevel(logging.INFO)

client = boto3.client('ec2')

instanceID = environ.get('INSTANCE_ID')
if instanceID == None:
    logger.error('Environment variable "INSTANCE_ID" must be set')
    raise Exception('Environment variable "INSTANCE_ID" must be set')

instanceSize = environ.get('INSTANCE_SIZE')
if instanceSize == None:
    logger.error('Environment variable "INSTANCE_SIZE" must be set')
    raise Exception('Environment variable "INSTANCE_SIZE" must be set')


def lambda_handler(event, context):
    # Stop the instance
    client.stop_instances(InstanceIds=[instanceID])
    waiter=client.get_waiter('instance_stopped')
    waiter.wait(InstanceIds=[instanceID])

    # Change the instance type
    client.modify_instance_attribute(InstanceId=instanceID, Attribute='instanceType', Value=instanceSize)

    # Start the instance
    client.start_instances(InstanceIds=[instanceID])

    logger.info('Resize complete!')
