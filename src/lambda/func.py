import json
import boto3
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# DynamoDB
dynamodb = boto3.resource('dynamodb')
table_name = os.environ.get('TABLE_NAME')
table = dynamodb.Table(table_name)

def lambda_handler(event, context):
    try:
        # Atomic increment of visitor count
        response = table.update_item(
            Key={'id': 'count'},
            UpdateExpression="SET visitor_count = if_not_exists(visitor_count, :start) + :inc",
            ExpressionAttributeValues={
                ':inc': 1,
                ':start': 0
            },
            ReturnValues="UPDATED_NEW"
        )
        
        
        visit_count = int(response['Attributes']['visitor_count'])
        
        return {
            'statusCode': 200,
            # CORS headers are added by API Gateway (see the backend module).
            'body': json.dumps({'count': visit_count})
        }
    except Exception:
        # Full details go to CloudWatch; the caller gets nothing internal.
        logger.exception("Failed to update the visitor count")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Internal server error'})
        }
