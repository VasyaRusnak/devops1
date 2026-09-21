from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class ReviewIn(BaseModel):
    book_id: str
    reviewer_name: str
    rating: int = Field(..., ge=1, le=5)
    comment: Optional[str] = None
    timestamp: Optional[datetime] = None


class ReviewOut(ReviewIn):
    id: str
    timestamp: datetime


class RatingSummary(BaseModel):
    book_id: str
    average_rating: Optional[float]
    reviews_count: int
