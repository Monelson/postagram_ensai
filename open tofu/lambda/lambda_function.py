import json
from urllib.parse import unquote_plus
import boto3
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')
rekognition = boto3.client('rekognition')

table = dynamodb.Table(os.getenv("DYNAMO_TABLE"))


def lambda_handler(event, context):
    logger.info(json.dumps(event, indent=2))

    bucket = event["Records"][0]["s3"]["bucket"]["name"]
    key = unquote_plus(event["Records"][0]["s3"]["object"]["key"])

    # key format: user/post_id/image_name
    user, post_id = key.split('/')[:2]

    label_data = rekognition.detect_labels(
        Image={
            "S3Object": {
                "Bucket": bucket,
                "Name": key
            }
        },
        MaxLabels=5,
        MinConfidence=75
    )
    logger.info(f"Labels data : {label_data}")

    labels = [label["Name"] for label in label_data["Labels"]]
    logger.info(f"Labels detected : {labels}")

    table.update_item(
        Key={
            'user': f'USER#{user}',
            'id': f'POST#{post_id}',
        },
        UpdateExpression="SET image = :img, labels = :lbl",
        ExpressionAttributeValues={
            ":img": key,
            ":lbl": labels,
        },
    )
