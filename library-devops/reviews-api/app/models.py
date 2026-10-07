from datetime import datetime

from pydantic import BaseModel, Field


class ReviewIn(BaseModel):
    book_id: str
    reviewer_name: str
    rating: int = Field(..., ge=1, le=5)
    comment: str | None = None
    timestamp: datetime | None = None


class ReviewOut(ReviewIn):
    id: str
    timestamp: datetime


class RatingSummary(BaseModel):
    book_id: str
    average_rating: float | None
    reviews_count: int