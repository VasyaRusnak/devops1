from datetime import datetime
from typing import List

from fastapi import Depends, FastAPI
from pymongo.database import Database

from .db import get_database
from .logic import compute_rating_summary
from .models import RatingSummary, ReviewIn, ReviewOut

app = FastAPI(title="Library Reviews API")


def serialize(doc: dict) -> ReviewOut:
    doc = dict(doc)
    doc["id"] = str(doc.pop("_id"))
    return ReviewOut(**doc)


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.post("/reviews", response_model=ReviewOut, status_code=201)
def create_review(review: ReviewIn, db: Database = Depends(get_database)) -> ReviewOut:
    payload = review.model_dump()
    payload["timestamp"] = payload["timestamp"] or datetime.utcnow()
    result = db.reviews.insert_one(payload)
    payload["_id"] = result.inserted_id
    return serialize(payload)


@app.get("/reviews/{book_id}", response_model=List[ReviewOut])
def list_reviews(book_id: str, db: Database = Depends(get_database)) -> List[ReviewOut]:
    docs = db.reviews.find({"book_id": book_id}).sort("timestamp", -1)
    return [serialize(doc) for doc in docs]


@app.get("/reviews/{book_id}/summary", response_model=RatingSummary)
def rating_summary(book_id: str, db: Database = Depends(get_database)) -> dict:
    ratings = [doc["rating"] for doc in db.reviews.find({"book_id": book_id}, {"rating": 1})]
    return compute_rating_summary(book_id, ratings)
