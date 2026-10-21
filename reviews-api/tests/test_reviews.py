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


def test_create_and_list_review() -> None:
    payload = {
        "book_id": "book-1",
        "reviewer_name": "Оксана",
        "rating": 5,
        "comment": "Чудова книга!",
    }
    resp = client.post("/reviews", json=payload)
    assert resp.status_code == 201
    body = resp.json()
    assert body["book_id"] == "book-1"
    assert "id" in body

    resp = client.get("/reviews/book-1")
    assert resp.status_code == 200
    reviews = resp.json()
    assert len(reviews) == 1
    assert reviews[0]["rating"] == 5


def test_rating_summary_averages_correctly() -> None:
    for rating in (4, 5, 3):
        client.post(
            "/reviews",
            json={"book_id": "book-2", "reviewer_name": f"user{rating}", "rating": rating},
        )

    resp = client.get("/reviews/book-2/summary")
    assert resp.status_code == 200
    body = resp.json()
    assert body["reviews_count"] == 3
    assert body["average_rating"] == 4.0


def test_rating_summary_for_book_without_reviews() -> None:
    resp = client.get("/reviews/no-reviews-book/summary")
    body = resp.json()
    assert body["reviews_count"] == 0
    assert body["average_rating"] is None


def test_invalid_rating_rejected() -> None:
    resp = client.post(
        "/reviews",
        json={"book_id": "book-3", "reviewer_name": "Хтось", "rating": 7},
    )
    assert resp.status_code == 422
