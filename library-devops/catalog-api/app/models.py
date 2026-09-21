from pydantic import BaseModel, Field


class BookIn(BaseModel):
    title: str
    author: str
    genre: str
    year: int = Field(..., ge=0, le=2100)
    isbn: str | None = None


class BookOut(BookIn):
    id: str