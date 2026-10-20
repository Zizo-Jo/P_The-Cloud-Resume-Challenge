"""Unit tests for the visitor-counter Lambda, run against a fake DynamoDB (moto)."""

import importlib.util
import json
from pathlib import Path

import boto3
import pytest
from moto import mock_aws

FUNC_PATH = Path(__file__).resolve().parents[1] / "src" / "lambda" / "func.py"
TABLE = "visitors-test"


def load_func():
    # "lambda" is a reserved word in Python, so load the file by path instead of importing it.
    spec = importlib.util.spec_from_file_location("func", FUNC_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture
def aws(monkeypatch):
    """Fake AWS with the visitors table and the env vars the Lambda expects."""
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "test")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "test")
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")
    monkeypatch.setenv("TABLE_NAME", TABLE)
    with mock_aws():
        boto3.client("dynamodb").create_table(
            TableName=TABLE,
            KeySchema=[{"AttributeName": "id", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "id", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )
        yield


def test_first_visit_returns_count_of_one(aws):
    response = load_func().lambda_handler({}, None)

    assert response["statusCode"] == 200
    assert json.loads(response["body"]) == {"count": 1}


def test_counter_increments_on_every_call(aws):
    func = load_func()

    counts = [json.loads(func.lambda_handler({}, None)["body"])["count"] for _ in range(3)]

    assert counts == [1, 2, 3]


def test_count_is_stored_in_dynamodb(aws):
    func = load_func()
    func.lambda_handler({}, None)
    func.lambda_handler({}, None)

    item = boto3.resource("dynamodb").Table(TABLE).get_item(Key={"id": "count"})["Item"]

    assert int(item["visitor_count"]) == 2


def test_database_error_returns_generic_500(aws):
    func = load_func()
    boto3.client("dynamodb").delete_table(TableName=TABLE)

    response = func.lambda_handler({}, None)

    assert response["statusCode"] == 500
    # Internal details (table name, AWS error text) must not reach the caller.
    assert json.loads(response["body"]) == {"error": "Internal server error"}
    assert TABLE not in response["body"]
