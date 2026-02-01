import json
import boto3
import os
from decimal import Decimal

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
            'headers': {
                'Access-Control-Allow-Origin': '*',  
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Allow-Methods': 'OPTIONS,POST,GET'
            },
            'body': json.dumps({'count': visit_count})
        }
    except Exception as e:
        print(e)
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }