import mongomock
from fastapi.testclient import TestClient

from app.db import get_database
from app.main import app

fake_client = mongomock.MongoClient()


def override_get_database():
    return fake_client["library_test"]


app.dependency_overrides[get_database] = override_get_database
client = TestClient(app)


def test_health() -> None:
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


def test_create_and_get_book() -> None:
    payload = {
        "title": "Дюна",
        "author": "Френк Герберт",
        "genre": "sci-fi",
        "year": 1965,
        "isbn": "978-0441013593",
    }
    resp = client.post("/books", json=payload)
    assert resp.status_code == 201
    body = resp.json()
    assert body["title"] == "Дюна"
    book_id = body["id"]

    resp = client.get(f"/books/{book_id}")
    assert resp.status_code == 200
    assert resp.json()["author"] == "Френк Герберт"


def test_list_books_filtered_by_genre() -> None:
    client.post(
        "/books",
        json={"title": "1984", "author": "Джордж Орвелл", "genre": "dystopia", "year": 1949},
    )
    client.post(
        "/books",
        json={"title": "Фундація", "author": "Айзек Азімов", "genre": "sci-fi", "year": 1951},
    )

    resp = client.get("/books", params={"genre": "dystopia"})
    assert resp.status_code == 200
    titles = [b["title"] for b in resp.json()]
    assert "1984" in titles
    assert "Фундація" not in titles


def test_get_unknown_book_returns_404() -> None:
    resp = client.get("/books/000000000000000000000000")
    assert resp.status_code == 404


def test_get_book_invalid_id_returns_400() -> None:
    resp = client.get("/books/not-a-valid-id")
    assert resp.status_code == 400
