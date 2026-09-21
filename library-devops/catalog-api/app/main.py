from fastapi import Depends, FastAPI, HTTPException
from pymongo.database import Database

from .db import get_database
from .models import BookIn, BookOut

app = FastAPI(title="Library Catalog API")


def serialize(doc: dict) -> BookOut:
    doc = dict(doc)
    doc["id"] = str(doc.pop("_id"))
    return BookOut(**doc)


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.post("/books", response_model=BookOut, status_code=201)
def create_book(book: BookIn, db: Database = Depends(get_database)) -> BookOut:
    payload = book.model_dump()
    result = db.books.insert_one(payload)
    payload["_id"] = result.inserted_id
    return serialize(payload)


@app.get("/books", response_model=list[BookOut])
def list_books(
    genre: str | None = None,
    author: str | None = None,
    db: Database = Depends(get_database),
) -> list[BookOut]:
    query = {}
    if genre:
        query["genre"] = genre
    if author:
        query["author"] = author
    docs = db.books.find(query)
    return [serialize(doc) for doc in docs]


@app.get("/books/{book_id}", response_model=BookOut)
def get_book(book_id: str, db: Database = Depends(get_database)) -> BookOut:
    from bson import ObjectId
    from bson.errors import InvalidId

    try:
        doc = db.books.find_one({"_id": ObjectId(book_id)})
    except InvalidId:
        raise HTTPException(status_code=400, detail="Invalid book_id")

    if doc is None:
        raise HTTPException(status_code=404, detail="Book not found")
    return serialize(doc)