import boto3
import os
from pprint import pprint
import time
import json

logs = boto3.client('logs')
ssm = boto3.client('ssm')

def get_log_groups():
    ssm_response = ssm.get_parameter(Name=os.environ["SSM_LOG_GROUP_PARAM"])
    ssm_value = ssm_response['Parameter']['Value']
    return json.loads(ssm_value)

def lambda_handler(event, context):
    extra_args = {'limit': 50, 'includeLinkedAccounts': True}
    log_groups_to_export = []
    
    if 'S3_BUCKET' not in os.environ:
        print("Error: S3_BUCKET not defined")
        return
    
    print("--> S3_BUCKET=%s SSM_LOG_GROUP_PARAM=%s" % (os.environ["S3_BUCKET"], os.environ["SSM_LOG_GROUP_PARAM"]))
    
    log_groups_prefixes = get_log_groups()
    
    while len(log_groups_prefixes) > 0:
        extra_args['logGroupNamePrefix'] = log_groups_prefixes.pop()
        print("--> Getting log groups with prefix %s" % extra_args['logGroupNamePrefix'])

        while True:
            response = logs.describe_log_groups(**extra_args)
            log_groups_to_export = log_groups_to_export + response['logGroups']
            
            if not 'nextToken' in response:
                break
            extra_args['nextToken'] = response['nextToken']
        
    for log_group in log_groups_to_export:
        print(log_group)
        log_group_name = log_group['logGroupName']
        ssm_parameter_name = ("/log-exporter-last-export/%s" % log_group_name).replace("//", "/")
        print("--> log_group_name %s ssm_parameter_name %s" % (log_group_name, ssm_parameter_name))
        try:
            ssm_response = ssm.get_parameter(Name=ssm_parameter_name)
            ssm_value = ssm_response['Parameter']['Value']
        except ssm.exceptions.ParameterNotFound:
            # try: 
            #     print("    Setting retention policy to 30 days for %s" % log_group_name)
            #     put_retention_policy_response = logs.put_retention_policy(
            #         logGroupName=log_group_name,
            #         retentionInDays=30
            #     )
            #     print("    Retention policy set to 30 days %s" % put_retention_policy_response)
            # except Exception as e:
            #     print("    Error setting retention policy %s" % getattr(e, 'message', repr(e)))
            ssm_value = "0"
        
        export_to_time = int(round(time.time() * 1000))
        
        print("--> Exporting %s to %s" % (log_group_name, os.environ['S3_BUCKET']))
        
        if export_to_time - int(ssm_value) < (24 * 60 * 60 * 1000):
            # Haven't been 24hrs from the last export of this log group
            print("    Skipped until 24hrs from last export is completed")
            continue
        
        max_retries = 10
        while max_retries > 0:
            try:
                response = logs.create_export_task(
                    logGroupName=log_group_name,
                    fromTime=int(ssm_value),
                    to=export_to_time,
                    destination=os.environ['S3_BUCKET'],
                    destinationPrefix=os.environ['AWS_ACCOUNT'] + '/' + log_group_name.strip('/')
                )
                print("    Task created: %s" % response['taskId'])
                ssm_response = ssm.put_parameter(
                    Name=ssm_parameter_name,
                    Type="String",
                    Value=str(export_to_time),
                    Overwrite=True)

                break
                
            except logs.exceptions.LimitExceededException:
                max_retries = max_retries - 1
                print("    Need to wait until all tasks are finished (LimitExceededException). Continuing %s additional times" % (max_retries))
                time.sleep(5)
                continue
            
            except Exception as e:
                print("    Error exporting %s: %s" % (log_group_name, getattr(e, 'message', repr(e))))
                break
            
if __name__ == '__main__':
    lambda_handler(None, None)