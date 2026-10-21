import os

from pymongo import MongoClient
from pymongo.database import Database

MONGO_URI = os.getenv("MONGO_URI", "mongodb://localhost:27017")
DB_NAME = os.getenv("DB_NAME", "library")

_client: MongoClient | None = None


def get_client() -> MongoClient:
    global _client
    if _client is None:
        _client = MongoClient(MONGO_URI)
    return _client


def get_database() -> Database:
    """FastAPI dependency: returns the MongoDB database instance."""
    return get_client()[DB_NAME]
