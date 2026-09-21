from typing import Optional

from pydantic import BaseModel, Field


class BookIn(BaseModel):
    title: str
    author: str
    genre: str
    year: int = Field(..., ge=0, le=2100)
    isbn: Optional[str] = None


class BookOut(BookIn):
    id: str
