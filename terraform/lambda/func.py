import json
import boto3

# Connect to dynamo
dynamodb = boto3.resource('dynamodb')
# Find our table
table = dynamodb.Table('visitors-terraform')

def lambda_handler(event, context):
    # 1. Atomic Update
    response = table.update_item(
        Key={
            'id': 'count'
        },
        UpdateExpression='SET visitor_count = visitor_count + :inc',
        ExpressionAttributeValues={
            ':inc': 1
        },
        ReturnValues="UPDATED_NEW"
    )
    
    # 2. Get the updated value
    visitor_count = response['Attributes']['visitor_count']
    
    # 3. Build the data that frontend will receive
    return {
        'statusCode': 200,
        'headers': {
            'Access-Control-Allow-Origin': '*',  # Allowing any website to use API
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Allow-Methods': 'OPTIONS,POST,GET'
        },
        'body': json.dumps({'count': int(visitor_count)})
    }