import os
from pymongo import MongoClient

# MongoDB Atlas Connection String
MONGO_URI = os.getenv(
    "MONGO_URI",
    "mongodb+srv://yuvaankaarthikeyaa1206_db_user:aykal_1206@attendlens.riy59cn.mongodb.net/?appName=Attendlens"
)

client = MongoClient(MONGO_URI)
db = client.get_database("attendlens")

def get_db():
    yield db

def get_next_id(collection_name: str) -> int:
    """Auto-increment sequence generator for clean integer IDs (like SQL id column)."""
    counter = db.counters.find_one_and_update(
        {"_id": collection_name},
        {"$inc": {"seq": 1}},
        upsert=True,
        return_document=True
    )
    return counter["seq"]
